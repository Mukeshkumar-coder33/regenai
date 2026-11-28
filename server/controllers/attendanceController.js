import Attendance from '../models/Attendance.js';
import User from '../models/User.js';
import Company from '../models/Company.js';
import Leave from '../models/Leave.js';
import Holiday from '../models/Holiday.js';
import Payroll from '../models/Payroll.js';
import PayrollSetting from '../models/PayrollSetting.js';
import mongoose from 'mongoose';
import { resolveCompanyId } from '../utils/resolveCompanyId.js';
import { emitToCompany, emitToUser, getIO } from '../socket.js';
import {
  calculateWorkedHours,
  computeBreakDelayDeductionAmount,
  parseTimeToMinutes,
  round2,
} from '../utils/payrollCalculator.js';
import { createAndSendNotification } from './notificationController.js';
import { sendReportEmail } from '../utils/mailer.js';
import { calculateHaversineDistance, GEOFENCE_RADIUS_METRES } from '../utils/geofence.js';
import {
  assertCompanyReportAccess,
  resolveReportWindow,
  isDateInWindow,
  parseDateBreakdown,
  normalizeDateOnly,
  buildCompanyUserLookup,
  matchesEmployeeFilter,
  paginateItems,
  buildCsvDocument,
} from '../utils/reportHelpers.js';

export const verifyGeofenceOrThrow = async (companyId, coords) => {
  if (!companyId) {
    const err = new Error('Company context required');
    err.statusCode = 400;
    throw err;
  }

  const company = await Company.findById(companyId).select('officeLocation name').lean();
  if (!company) {
    const err = new Error('Company record not found');
    err.statusCode = 404;
    throw err;
  }

  const office = company.officeLocation;
  if (!office || typeof office.latitude !== 'number' || typeof office.longitude !== 'number') {
    const err = new Error('Company office location has not been configured. Please ask your company administrator to configure it in Company Settings.');
    err.statusCode = 400;
    err.code = 'OFFICE_LOCATION_NOT_SET';
    throw err;
  }

  const lat = Number(coords?.latitude ?? coords?.lat);
  const lon = Number(coords?.longitude ?? coords?.lon ?? coords?.lng);

  if (isNaN(lat) || lat < -90 || lat > 90 || isNaN(lon) || lon < -180 || lon > 180) {
    const err = new Error('Valid location coordinates (latitude and longitude) are required for attendance actions.');
    err.statusCode = 400;
    err.code = 'INVALID_COORDINATES';
    throw err;
  }

  const rawDistance = calculateHaversineDistance(lat, lon, office.latitude, office.longitude);
  const distance = Math.round(rawDistance * 10) / 10;

  if (distance > GEOFENCE_RADIUS_METRES) {
    const err = new Error('You must be within 5 metres of your registered office to perform this action.');
    err.statusCode = 403;
    err.code = 'OUTSIDE_GEOFENCE';
    err.distance = distance;
    err.maxAllowedDistance = GEOFENCE_RADIUS_METRES;
    throw err;
  }

  return {
    ok: true,
    distance,
    coords: {
      latitude: lat,
      longitude: lon,
      accuracy: coords?.accuracy ? Number(coords.accuracy) : undefined,
      distanceFromOffice: distance,
    }
  };
};

export const calculateBreakDelayDeduction = async (companyId, userId, delayMinutes) => {
  if (!delayMinutes || delayMinutes <= 0) return 0;
  try {
    const user = await User.findOne({ 
      $or: [
        { userId }, 
        { StaffId: userId }, 
        { username: userId }, 
        { name: userId }, 
        { _id: mongoose.isValidObjectId(userId) ? userId : null }
      ] 
    }).select('salary').lean();
    const monthlySalary = Number(user?.salary) || 0;
    const settings = await PayrollSetting.findOne({ companyId }).lean() || {};
    return computeBreakDelayDeductionAmount(delayMinutes, monthlySalary, settings);
  } catch (err) {
    console.error('calculateBreakDelayDeduction error:', err.message);
    return 0;
  }
};

export const recordAttendance = async (req, res) => {
  try {
    const body = { ...req.body };
    if (!body.id) body.id = new mongoose.Types.ObjectId().toString();
    const validStatuses = ['present', 'absent', 'late', 'half_day'];
    if (body.status && typeof body.status === 'object') {
      body.status = Object.keys(body.status)[0];
    }
    if (!validStatuses.includes(body.status)) {
      body.status = 'present';
    }
    body.companyId = await resolveCompanyId(req, body);

    // Prevent modifying/creating attendance inside a finalized/closed payroll month
    if (body.companyId && body.userId && body.date) {
      const targetMonth = String(body.date).slice(0, 7);
      const lockedPayroll = await Payroll.findOne({
        companyId: body.companyId,
        userId: body.userId,
        month: targetMonth,
        $or: [{ status: 'finalized' }, { isClosed: true }, { paymentStatus: { $in: ['paid', 'partially_paid'] } }],
      }).lean();
      if (lockedPayroll) {
        return res.status(400).json({ message: `Payroll for ${targetMonth} is finalized/closed. Cannot record or alter attendance.` });
      }
    }

    // Resolve employee name for direct persistence
    if (!body.employeeName && !body.userName && body.userId) {
      try {
        const u = await User.findOne({
          $or: [{ userId: body.userId }, { StaffId: body.userId }, { username: body.userId }]
        }).select('name username').lean();
        if (u) {
          body.employeeName = u.name || u.username;
          body.userName = u.name || u.username;
        }
      } catch (_) {}
    }

    // Evaluate Late status against company's work schedule (honoring graceMinutes)
    try {
      const settings = await PayrollSetting.findOne({ companyId: body.companyId }).lean();
      const checkInTargetStr = settings?.checkInTime || '09:30';
      const graceMins = Number(settings?.graceMinutes) >= 0 ? Number(settings.graceMinutes) : 0;
      const parts = checkInTargetStr.split(':').map(Number);
      const tH = parts[0] || 9;
      const tM = parts.length > 1 ? parts[1] : 30;
      const targetTotal = (tH * 60) + tM + graceMins;
      if (body.checkIn) {
        const cDate = new Date(body.checkIn);
        const actualTotal = (cDate.getHours() * 60) + cDate.getMinutes();
        if (actualTotal > targetTotal) {
          body.status = 'late';
        }
      }
    } catch (_) {}

    // Geofence verification for check-in action
    const geo = await verifyGeofenceOrThrow(body.companyId, {
      latitude: body.latitude ?? body.coords?.latitude ?? body.locationCoordinates?.latitude,
      longitude: body.longitude ?? body.coords?.longitude ?? body.locationCoordinates?.longitude,
      accuracy: body.accuracy ?? body.coords?.accuracy ?? body.locationCoordinates?.accuracy,
    });
    body.locationCoords = geo.coords;

    const attendance = new Attendance(body);
    await attendance.save();

    emitToCompany('attendance:change', attendance.companyId, { action: 'create', id: attendance.id, attendance });
    emitToCompany('payroll:change', attendance.companyId, { action: 'attendance_updated', userId: attendance.userId });
    if (attendance.userId) {
      emitToUser(attendance.userId, 'attendance:change', { action: 'create', id: attendance.id, attendance });
    }
    const io = getIO();
    if (io) {
      io.emit('attendance:change', { action: 'create', id: attendance.id, companyId: attendance.companyId, userId: attendance.userId });
    }

    // Send attendance check-in notification (late alert to employee + check-in summary to company owner/admin)
    try {
      const empName = attendance.employeeName || attendance.userName || attendance.userId;
      const checkInLabel = attendance.checkIn
        ? new Date(attendance.checkIn).toLocaleTimeString('en-IN', { hour: '2-digit', minute: '2-digit' })
        : '';
      if (attendance.userId && attendance.status === 'late') {
        await createAndSendNotification({
          id: `att-late-${attendance.id || attendance._id}`,
          companyId: attendance.companyId,
          userId: attendance.userId,
          type: 'attendance',
          title: 'Late Check-In Recorded',
          message: `You checked in late on ${attendance.date}${checkInLabel ? ` at ${checkInLabel}` : ''}.`,
          metadata: { attendanceId: attendance.id, date: attendance.date, status: 'late' },
        });
      }
      if (attendance.companyId) {
        const admins = await User.find({
          companyId: attendance.companyId,
          role: { $in: ['owner', 'admin'] },
          userId: { $ne: attendance.userId },
          status: { $ne: 'inactive' },
        }).select('userId').lean();
        for (const adm of admins) {
          await createAndSendNotification({
            id: `att-adm-${attendance.id || attendance._id}-${adm.userId}`,
            companyId: attendance.companyId,
            userId: adm.userId,
            type: 'attendance',
            title: `${attendance.status === 'late' ? 'Late Check-In' : 'Attendance Check-In'}: ${empName}`,
            message: `${empName} checked in on ${attendance.date}${checkInLabel ? ` at ${checkInLabel}` : ''}${attendance.status === 'late' ? ' (Late)' : ''}.`,
            senderId: attendance.userId,
            senderName: empName,
            metadata: { attendanceId: attendance.id, date: attendance.date, status: attendance.status || 'present' },
          });
        }
      }
    } catch (_) {}

    res.status(201).json(attendance);
  } catch (error) {
    res.status(error.statusCode || 400).json({ 
      message: error.message, 
      code: error.code, 
      distance: error.distance, 
      maxAllowedDistance: error.maxAllowedDistance 
    });
  }
};

export const getAllAttendance = async (req, res) => {
  try {
    const isEmsView = req.headers['x-portal-view'] === 'ems' || req.query.portalView === 'ems';
    const isSuperAdmin = req.user?.role === 'param' || req.user?.role === 'admin';
    const filter = (isSuperAdmin && !isEmsView) ? {} : (req.companyId ? { companyId: req.companyId } : {});
    const attendance = await Attendance.find(filter);
    res.status(200).json(attendance);
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
};

export const getUserAttendance = async (req, res) => {
  try {
    const filter = { userId: req.params.userId };
    if (req.companyId) filter.companyId = req.companyId;
    const attendance = await Attendance.find(filter);
    res.status(200).json(attendance);
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
};

export const updateAttendance = async (req, res) => {
  try {
    const id = req.body.id || req.params.id;
    const filter = mongoose.isValidObjectId(id) ? { $or: [{ id }, { _id: id }] } : { id };
    if (req.companyId) filter.companyId = req.companyId;
    const updateData = { ...req.body };
    const validStatuses = ['present', 'absent', 'late', 'half_day'];
    if (updateData.status) {
      if (typeof updateData.status === 'object') {
        updateData.status = Object.keys(updateData.status)[0];
      }
      if (!validStatuses.includes(updateData.status)) {
        delete updateData.status;
      }
    }

    const existing = await Attendance.findOne(filter);
    if (!existing) return res.status(404).json({ message: 'Attendance not found' });

    const companyId = existing.companyId || req.companyId;
    const userId = existing.userId || updateData.userId;

    // Lock check: prevent modifying attendance inside a finalized/closed payroll month
    const existingMonth = existing.date ? String(existing.date).slice(0, 7) : null;
    if (companyId && userId && existingMonth) {
      const lockedPayroll = await Payroll.findOne({
        companyId,
        userId,
        month: existingMonth,
        $or: [{ status: 'finalized' }, { isClosed: true }, { paymentStatus: { $in: ['paid', 'partially_paid'] } }],
      }).lean();
      if (lockedPayroll) {
        return res.status(400).json({ message: `Payroll for ${existingMonth} is finalized/closed and attendance cannot be modified.` });
      }
    }
    const settings = companyId ? await PayrollSetting.findOne({ companyId }).lean() : null;

    // Detect restricted attendance actions requiring 15-metre geofence validation:
    // 1) Check-out, 2) Start normal break, 3) End normal break, 4) Start casual break, 5) End casual break
    const isCheckOut = Boolean(updateData.checkOut && updateData.checkOut !== existing.checkOut);
    const isStartOfficial = Boolean(
      (updateData.activeBreakType === 'official' && updateData.breakStart && !existing.breakStart) ||
      (updateData.breakStart && updateData.breakStart !== existing.breakStart && !updateData.breakEnd)
    );
    const isEndOfficial = Boolean(
      (updateData.breakEnd && updateData.breakEnd !== existing.breakEnd) ||
      (existing.activeBreakType === 'official' && updateData.activeBreakType === 'none')
    );
    const isStartCasual = Boolean(
      (updateData.activeBreakType === 'casual' && updateData.casualBreakStart && !existing.casualBreakStart) ||
      (updateData.casualBreakStart && updateData.casualBreakStart !== existing.casualBreakStart && !updateData.casualBreakEnd)
    );
    const isEndCasual = Boolean(
      (updateData.casualBreakEnd && updateData.casualBreakEnd !== existing.casualBreakEnd) ||
      (existing.activeBreakType === 'casual' && updateData.activeBreakType === 'none')
    );

    const isRestrictedAction = isCheckOut || isStartOfficial || isEndOfficial || isStartCasual || isEndCasual;

    if (isRestrictedAction) {
      const geo = await verifyGeofenceOrThrow(companyId, {
        latitude: updateData.latitude ?? req.body.latitude ?? req.body.coords?.latitude,
        longitude: updateData.longitude ?? req.body.longitude ?? req.body.coords?.longitude,
        accuracy: updateData.accuracy ?? req.body.accuracy ?? req.body.coords?.accuracy,
      });
      updateData.locationCoords = geo.coords;
    }

    // If starting official break, clear stale breakEnd
    if (updateData.activeBreakType === 'official' && updateData.breakStart && !updateData.breakEnd) {
      updateData.breakEnd = null;
    }
    // If starting casual break, clear stale casualBreakEnd
    if (updateData.activeBreakType === 'casual' && updateData.casualBreakStart && !updateData.casualBreakEnd) {
      updateData.casualBreakEnd = null;
    }

    // Official break calculation
    const bStart = updateData.breakStart !== undefined ? updateData.breakStart : existing.breakStart;
    const bEnd = updateData.breakEnd !== undefined ? updateData.breakEnd : existing.breakEnd;
    if (bStart && bEnd && new Date(bEnd).getTime() >= new Date(bStart).getTime()) {
      const bMin = Math.max(0, Math.round((new Date(bEnd).getTime() - new Date(bStart).getTime()) / 60000));
      updateData.breakMinutes = bMin;
      const allowedBreak = settings?.breakTime !== undefined ? Number(settings.breakTime) : 60;
      updateData.breakDelayMinutes = Math.max(0, bMin - allowedBreak);
    }

    // Casual break calculation
    const cbStart = updateData.casualBreakStart !== undefined ? updateData.casualBreakStart : existing.casualBreakStart;
    const cbEnd = updateData.casualBreakEnd !== undefined ? updateData.casualBreakEnd : existing.casualBreakEnd;
    if (cbStart && cbEnd && new Date(cbEnd).getTime() >= new Date(cbStart).getTime()) {
      const cbMin = Math.max(0, Math.round((new Date(cbEnd).getTime() - new Date(cbStart).getTime()) / 60000));
      updateData.casualBreakMinutes = cbMin;
      const allowedCasual = settings?.casualBreakTime !== undefined ? Number(settings.casualBreakTime) : 15;
      updateData.casualBreakDelayMinutes = Math.max(0, cbMin - allowedCasual);
    }

    const bDelay = updateData.breakDelayMinutes !== undefined ? updateData.breakDelayMinutes : (existing.breakDelayMinutes || 0);
    const cbDelay = updateData.casualBreakDelayMinutes !== undefined ? updateData.casualBreakDelayMinutes : (existing.casualBreakDelayMinutes || 0);
    const totalDelay = (Number(bDelay) || 0) + (Number(cbDelay) || 0);
    updateData.totalBreakDelayMinutes = totalDelay;

    if (totalDelay > 0) {
      updateData.breakDeduction = await calculateBreakDelayDeduction(companyId, userId, totalDelay);
    } else {
      updateData.breakDeduction = 0;
    }

    // Compute total net working hours if checkOut is set
    const finalCheckIn = updateData.checkIn || existing.checkIn;
    const finalCheckOut = updateData.checkOut || existing.checkOut;
    if (finalCheckIn && finalCheckOut) {
      const inTime = new Date(finalCheckIn).getTime();
      const outTime = new Date(finalCheckOut).getTime();
      if (outTime >= inTime) {
        const totalBreakMinutes = (updateData.breakMinutes !== undefined ? updateData.breakMinutes : (existing.breakMinutes || 0)) +
                                  (updateData.casualBreakMinutes !== undefined ? updateData.casualBreakMinutes : (existing.casualBreakMinutes || 0));
        const netDurationMs = Math.max(0, (outTime - inTime) - (totalBreakMinutes * 60000));
        const netWorkingHours = Math.round((netDurationMs / 3600000) * 100) / 100;
        updateData.totalWorkingHours = netWorkingHours;
        updateData.workingHours = netWorkingHours;
      }
    }

    if (!existing.employeeName && !existing.userName && userId) {
      try {
        const u = await User.findOne({
          $or: [{ userId }, { StaffId: userId }, { username: userId }]
        }).select('name username').lean();
        if (u) {
          updateData.employeeName = u.name || u.username;
          updateData.userName = u.name || u.username;
        }
      } catch (_) {}
    }

    const attendance = await Attendance.findOneAndUpdate(filter, updateData, { new: true });
    if (!attendance) return res.status(404).json({ message: 'Attendance not found' });

    emitToCompany('attendance:change', attendance.companyId, { action: 'update', id: attendance.id, attendance });
    emitToCompany('payroll:change', attendance.companyId, { action: 'attendance_updated', userId: attendance.userId });
    if (attendance.userId) {
      emitToUser(attendance.userId, 'attendance:change', { action: 'update', id: attendance.id, attendance });

      // Notify employee on new break delay deduction or overtime earned
      try {
        const prevBreakDed = Number(existing.breakDeduction) || 0;
        const newBreakDed = Number(attendance.breakDeduction) || 0;
        if (newBreakDed > prevBreakDed) {
          const delta = round2(newBreakDed - prevBreakDed);
          await createAndSendNotification({
            companyId: attendance.companyId,
            userId: attendance.userId,
            title: 'Break Delay Deduction',
            message: `A break-delay deduction of ₹${delta.toLocaleString('en-IN')} (${attendance.totalBreakDelayMinutes || 0} mins excess break on ${attendance.date}) has been recorded.`,
            type: 'deduction',
            metadata: {
              date: attendance.date,
              amount: delta,
              totalBreakDelayMinutes: attendance.totalBreakDelayMinutes || 0,
              reason: 'Excess lunch/casual break delay',
            },
          });
        }

        if (req.body.checkOut && Number(attendance.totalWorkingHours) > 0) {
          const ps = await PayrollSetting.findOne({ companyId: attendance.companyId }).lean();
          const reqHours = Number(ps?.workingHoursPerDay) || 8;
          const otEnabled = ps?.overtimeEnabled !== false;
          const otHours = round2(Number(attendance.totalWorkingHours) - reqHours);
          if (otEnabled && otHours > 0 && ((otHours * 60) >= (Number(ps?.overtimeMinMinutes) || 0))) {
            await createAndSendNotification({
              companyId: attendance.companyId,
              userId: attendance.userId,
              title: 'Overtime Recorded',
              message: `You logged +${otHours}h overtime on ${attendance.date}. Overtime earnings will be added to your payroll.`,
              type: 'payroll',
              metadata: {
                date: attendance.date,
                overtimeHours: otHours,
                reason: 'Overtime work',
              },
            });
          }
        }
      } catch (_) {}
    }
    const io = getIO();
    if (io) {
      io.emit('attendance:change', { action: 'update', id: attendance.id, companyId: attendance.companyId, userId: attendance.userId });
    }

    res.status(200).json(attendance);
  } catch (error) {
    res.status(error.statusCode || 400).json({ 
      message: error.message, 
      code: error.code, 
      distance: error.distance, 
      maxAllowedDistance: error.maxAllowedDistance 
    });
  }
};

/**
 * Helper to build complete historical attendance report items and summary metrics
 * Supports: all | range | day | week | month | year, employee, department, status, search, pagination
 */
export const buildAttendanceReportData = async (companyId, queryParams = {}) => {
  const {
    userId: queryUserId,
    employeeId: queryEmployeeId,
    department,
    status,
    search,
  } = queryParams;

  const targetEmployeeFilter = queryUserId || queryEmployeeId || 'all';

  // Fetch company, payroll shift policy, earliest attendance date, and full employee lookup
  const [company, payrollSetting, earliestAtt, userLookup] = await Promise.all([
    Company.findById(companyId).select('name code email createdAt officeLocation').lean(),
    PayrollSetting.findOne({ companyId }).lean(),
    Attendance.findOne({ companyId }).sort({ date: 1 }).select('date').lean(),
    buildCompanyUserLookup(companyId),
  ]);

  const companyName = company?.name || 'Company';
  const companyCreatedDate = normalizeDateOnly(company?.createdAt);
  const earliestRecordDate = earliestAtt?.date || companyCreatedDate || '';
  const window = resolveReportWindow(queryParams, earliestRecordDate);

  const shiftStartMins = parseTimeToMinutes(payrollSetting?.checkInTime || '09:30');
  const shiftEndMins = parseTimeToMinutes(payrollSetting?.checkOutTime || '18:30');
  const graceMinutes = Number(payrollSetting?.graceMinutes) || 0;
  const requiredHours = Number(payrollSetting?.workingHoursPerDay) || 8;
  const officeRadius = Number(company?.officeLocation?.radius) || 5;

  const attQuery = { companyId };
  if (window.startDate && window.endDate) {
    attQuery.date = { $gte: window.startDate, $lte: window.endDate };
  } else if (window.startDate) {
    attQuery.date = { $gte: window.startDate };
  } else if (window.endDate) {
    attQuery.date = { $lte: window.endDate };
  }

  const leaveQuery = { companyId };
  if (window.startDate && window.endDate) {
    leaveQuery.startDate = { $lte: window.endDate };
    leaveQuery.endDate = { $gte: window.startDate };
  }

  const holidayQuery = { companyId };
  if (window.startDate && window.endDate) {
    holidayQuery.date = { $gte: window.startDate, $lte: window.endDate };
  }

  const [records, leaves, holidays] = await Promise.all([
    Attendance.find(attQuery).sort({ date: -1, checkIn: 1 }).lean(),
    Leave.find(leaveQuery).sort({ startDate: -1 }).lean(),
    Holiday.find(holidayQuery).sort({ date: -1 }).lean(),
  ]);

  const formatTimeDisplay = (timeStr) => {
    if (!timeStr) return '--';
    if (String(timeStr).includes('T')) {
      const d = new Date(timeStr);
      if (!isNaN(d.getTime())) {
        return d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', hour12: true });
      }
    }
    return String(timeStr);
  };

  // Enrich attendance rows with weekday/month/year, joining date, shift late/overtime, breaks, GPS verification, edit history
  let rows = records.map((r) => {
    const emp = userLookup.resolveUser(r.userId, r.employeeName || r.userName);
    const storedHours = Number(r.totalWorkingHours ?? r.workingHours);
    const workedHours = !isNaN(storedHours) && storedHours > 0
      ? round2(storedHours)
      : calculateWorkedHours(r.checkIn, r.checkOut, r.status, requiredHours);

    const dateMeta = parseDateBreakdown(r.date);
    const inMins = parseTimeToMinutes(r.checkIn);
    const outMins = parseTimeToMinutes(r.checkOut);

    let lateMinutes = 0;
    if (inMins !== null && shiftStartMins !== null) {
      const diffIn = Math.round(inMins - (shiftStartMins + graceMinutes));
      if (diffIn > 0 && (r.status === 'late' || r.status === 'present' || r.status === 'half_day')) {
        lateMinutes = diffIn;
      }
    }

    let earlyDepartureMinutes = 0;
    if (outMins !== null && shiftEndMins !== null && outMins < shiftEndMins && r.checkOut) {
      earlyDepartureMinutes = Math.round(shiftEndMins - outMins);
    }

    const overtimeHours = workedHours > requiredHours ? round2(workedHours - requiredHours) : 0;
    const coords = r.locationCoords || null;
    const hasCoords = coords && typeof coords.latitude === 'number' && typeof coords.longitude === 'number';
    const locationVerified = hasCoords
      ? (typeof coords.distance === 'number' ? coords.distance <= officeRadius : true)
      : false;

    const createdMs = r.createdAt ? new Date(r.createdAt).getTime() : 0;
    const updatedMs = r.updatedAt ? new Date(r.updatedAt).getTime() : 0;
    const wasModified = createdMs > 0 && updatedMs > createdMs + 5000;

    return {
      id: r.id || String(r._id),
      recordType: 'attendance',
      date: r.date,
      weekday: dateMeta.weekday,
      month: dateMeta.month,
      year: dateMeta.year,
      userId: emp.userId,
      staffId: emp.staffId,
      name: emp.name,
      department: emp.department,
      designation: emp.designation,
      joiningDate: emp.joiningDate,
      employeeStatus: emp.employeeStatus,
      status: r.status || 'present',
      checkIn: r.checkIn || null,
      checkOut: r.checkOut || null,
      checkInDisplay: formatTimeDisplay(r.checkIn),
      checkOutDisplay: formatTimeDisplay(r.checkOut),
      workingHours: workedHours,
      lateMinutes,
      isLate: r.status === 'late' || lateMinutes > 0,
      earlyDepartureMinutes,
      overtimeHours,
      workMode: r.workMode || 'office',
      breakStart: r.breakStart || null,
      breakEnd: r.breakEnd || null,
      breakStartDisplay: formatTimeDisplay(r.breakStart),
      breakEndDisplay: formatTimeDisplay(r.breakEnd),
      breakMinutes: Number(r.breakMinutes) || 0,
      breakDelayMinutes: Number(r.breakDelayMinutes) || 0,
      casualBreakStart: r.casualBreakStart || null,
      casualBreakEnd: r.casualBreakEnd || null,
      casualBreakStartDisplay: formatTimeDisplay(r.casualBreakStart),
      casualBreakEndDisplay: formatTimeDisplay(r.casualBreakEnd),
      casualBreakMinutes: Number(r.casualBreakMinutes) || 0,
      casualBreakDelayMinutes: Number(r.casualBreakDelayMinutes) || 0,
      totalBreakDelayMinutes: Number(r.totalBreakDelayMinutes) || 0,
      breakDeduction: Number(r.breakDeduction) || 0,
      activeBreakType: r.activeBreakType || 'none',
      location: r.location || (r.workMode === 'remote' ? 'Remote' : 'Main Office'),
      locationCoords: coords,
      locationVerified,
      notes: r.notes || '',
      createdAt: r.createdAt || null,
      updatedAt: r.updatedAt || null,
      wasModified,
      _userMeta: emp,
    };
  });

  // Map stored Leave records overlapping window
  let leaveRows = leaves.map((l) => {
    const emp = userLookup.resolveUser(l.userId, l.employeeName);
    const dateMeta = parseDateBreakdown(l.startDate);
    return {
      id: l.id || String(l._id),
      recordType: 'leave',
      date: l.startDate,
      endDate: l.endDate,
      weekday: dateMeta.weekday,
      month: dateMeta.month,
      year: dateMeta.year,
      userId: emp.userId,
      staffId: emp.staffId,
      name: emp.name,
      department: l.department || emp.department,
      designation: emp.designation,
      joiningDate: emp.joiningDate,
      employeeStatus: emp.employeeStatus,
      status: 'leave',
      leaveType: l.type || 'casual',
      leaveStatus: l.status || 'pending',
      workingDays: Number(l.workingDays) || 1,
      approvedByName: l.approvedByName || '',
      approvalDate: l.approvalDate || '',
      checkIn: null,
      checkOut: null,
      checkInDisplay: '--',
      checkOutDisplay: '--',
      workingHours: 0,
      lateMinutes: 0,
      earlyDepartureMinutes: 0,
      overtimeHours: 0,
      breakMinutes: 0,
      casualBreakMinutes: 0,
      totalBreakDelayMinutes: 0,
      breakDeduction: 0,
      workMode: 'leave',
      location: `${String(l.type || 'casual').toUpperCase()} Leave (${l.status})`,
      locationVerified: false,
      notes: l.reason || l.remarks || '',
      createdAt: l.createdAt || null,
      updatedAt: l.updatedAt || null,
      wasModified: false,
      _userMeta: emp,
    };
  });

  // Map stored Holiday records in window
  let holidayRows = holidays.map((h) => {
    const dateMeta = parseDateBreakdown(h.date);
    return {
      id: h.id || String(h._id),
      recordType: 'holiday',
      date: h.date,
      weekday: dateMeta.weekday,
      month: dateMeta.month,
      year: dateMeta.year,
      userId: 'ALL',
      staffId: 'HOLIDAY',
      name: h.name,
      department: 'All Departments',
      designation: 'Company Holiday',
      joiningDate: '',
      employeeStatus: 'active',
      status: 'holiday',
      checkIn: null,
      checkOut: null,
      checkInDisplay: '--',
      checkOutDisplay: '--',
      workingHours: 0,
      lateMinutes: 0,
      earlyDepartureMinutes: 0,
      overtimeHours: 0,
      breakMinutes: 0,
      casualBreakMinutes: 0,
      totalBreakDelayMinutes: 0,
      breakDeduction: 0,
      workMode: 'holiday',
      location: 'Public Holiday',
      locationVerified: false,
      notes: h.name,
      createdAt: h.createdAt || null,
      updatedAt: h.updatedAt || null,
      wasModified: false,
    };
  });

  const applyCommonFilters = (list, { includeEmployeeFilter = true } = {}) => {
    let out = list;
    if (includeEmployeeFilter && targetEmployeeFilter && targetEmployeeFilter !== 'all') {
      out = out.filter((r) => r._userMeta && matchesEmployeeFilter(r._userMeta, targetEmployeeFilter));
    }
    if (department && department !== 'all') {
      out = out.filter((r) => (r.department || '').toLowerCase() === String(department).toLowerCase());
    }
    if (search) {
      const q = String(search).toLowerCase().trim();
      out = out.filter((r) =>
        (r.name || '').toLowerCase().includes(q) ||
        (r.staffId || '').toLowerCase().includes(q) ||
        (r.userId || '').toLowerCase().includes(q) ||
        (r.department || '').toLowerCase().includes(q) ||
        (r.notes || '').toLowerCase().includes(q),
      );
    }
    return out;
  };

  rows = applyCommonFilters(rows);
  leaveRows = applyCommonFilters(leaveRows);
  if (search) {
    const q = String(search).toLowerCase().trim();
    holidayRows = holidayRows.filter((h) => (h.name || '').toLowerCase().includes(q));
  }

  let activeRows = rows;
  const normalizedStatus = String(status || 'all').toLowerCase().trim();
  if (normalizedStatus === 'leave') {
    activeRows = leaveRows;
  } else if (normalizedStatus === 'holiday') {
    activeRows = holidayRows;
  } else if (normalizedStatus !== 'all') {
    activeRows = rows.filter((r) => (r.status || '').toLowerCase() === normalizedStatus);
  }

  // Strip internal lookup helper before serialization
  const sanitizeRow = ({ _userMeta, ...rest }) => rest;
  const cleanRows = activeRows.map(sanitizeRow);
  const cleanLeaves = leaveRows.map(sanitizeRow);
  const cleanHolidays = holidayRows;

  // Build per-employee historical summary from attendance & leave rows
  const empAggMap = new Map();
  for (const r of rows) {
    const key = r.userId || r.staffId;
    if (!empAggMap.has(key)) {
      empAggMap.set(key, {
        userId: r.userId,
        staffId: r.staffId,
        name: r.name,
        department: r.department,
        designation: r.designation,
        joiningDate: r.joiningDate,
        employeeStatus: r.employeeStatus,
        totalShifts: 0,
        presentCount: 0,
        lateCount: 0,
        halfDayCount: 0,
        absentCount: 0,
        leaveDays: 0,
        totalWorkingHours: 0,
        totalOvertimeHours: 0,
        totalLateMinutes: 0,
        totalBreakMinutes: 0,
        totalBreakDelayMinutes: 0,
      });
    }
    const s = empAggMap.get(key);
    s.totalShifts += 1;
    if (r.status === 'present') s.presentCount += 1;
    else if (r.status === 'late') s.lateCount += 1;
    else if (r.status === 'half_day') s.halfDayCount += 1;
    else if (r.status === 'absent') s.absentCount += 1;
    s.totalWorkingHours = round2(s.totalWorkingHours + (r.workingHours || 0));
    s.totalOvertimeHours = round2(s.totalOvertimeHours + (r.overtimeHours || 0));
    s.totalLateMinutes += r.lateMinutes || 0;
    s.totalBreakMinutes += (r.breakMinutes || 0) + (r.casualBreakMinutes || 0);
    s.totalBreakDelayMinutes += r.totalBreakDelayMinutes || 0;
  }
  for (const l of cleanLeaves) {
    if (l.leaveStatus === 'approved') {
      const key = l.userId || l.staffId;
      if (empAggMap.has(key)) {
        empAggMap.get(key).leaveDays += l.workingDays || 1;
      }
    }
  }
  const employeeSummaries = Array.from(empAggMap.values()).sort((a, b) =>
    (a.name || '').localeCompare(b.name || ''),
  );

  // Compute summary metrics across filtered rows
  const totalRecords = cleanRows.length;
  const totalWorkingHours = round2(cleanRows.reduce((sum, r) => sum + (Number(r.workingHours) || 0), 0));
  const averageDailyHours = totalRecords > 0 ? round2(totalWorkingHours / totalRecords) : 0;
  const presentCount = cleanRows.filter((r) => r.status === 'present').length;
  const lateCount = cleanRows.filter((r) => r.status === 'late').length;
  const halfDayCount = cleanRows.filter((r) => r.status === 'half_day').length;
  const absentCount = cleanRows.filter((r) => r.status === 'absent').length;
  const leaveCount = cleanLeaves.length;
  const holidayCount = cleanHolidays.length;
  const totalLateMinutes = cleanRows.reduce((sum, r) => sum + (Number(r.lateMinutes) || 0), 0);
  const totalOvertimeHours = round2(cleanRows.reduce((sum, r) => sum + (Number(r.overtimeHours) || 0), 0));
  const totalBreakMinutes = cleanRows.reduce(
    (sum, r) => sum + (Number(r.breakMinutes) || 0) + (Number(r.casualBreakMinutes) || 0),
    0,
  );
  const totalBreakDelayMinutes = cleanRows.reduce((sum, r) => sum + (Number(r.totalBreakDelayMinutes) || 0), 0);
  const uniqueEmployees = new Set(cleanRows.map((r) => r.userId).filter((id) => id && id !== 'ALL')).size;

  // Build full CSV across ALL matching rows before pagination
  const csvHeaders = [
    'Date', 'Weekday', 'Employee ID', 'Name', 'Department', 'Designation', 'Joining Date',
    'Employee Status', 'Status', 'Check In', 'Check Out', 'Working Hours', 'Late (mins)',
    'Early Out (mins)', 'Overtime (hrs)', 'Lunch Break (mins)', 'Casual Break (mins)',
    'Break Delay (mins)', 'Work Mode', 'Location', 'Location Verified', 'Notes',
  ];
  const csvRows = cleanRows.map((r) => [
    r.date,
    r.weekday || '',
    r.staffId,
    r.name,
    r.department,
    r.designation,
    r.joiningDate || '',
    r.employeeStatus || 'active',
    r.status,
    r.checkInDisplay,
    r.checkOutDisplay,
    r.workingHours,
    r.lateMinutes || 0,
    r.earlyDepartureMinutes || 0,
    r.overtimeHours || 0,
    r.breakMinutes || 0,
    r.casualBreakMinutes || 0,
    r.totalBreakDelayMinutes || 0,
    r.workMode,
    r.location,
    r.locationVerified ? 'Verified' : 'No/Manual',
    r.notes || '',
  ]);

  const csvContent = buildCsvDocument(
    [
      `# ${companyName} - Historical Attendance Report`,
      `# Period: ${window.periodLabel}`,
      `# Generated: ${new Date().toLocaleString()}`,
      `# Summary: Records: ${totalRecords} | Total Hours: ${totalWorkingHours}h | Overtime: ${totalOvertimeHours}h | Late Mins: ${totalLateMinutes} | Unique Staff: ${uniqueEmployees}`,
    ],
    csvHeaders,
    csvRows,
  );

  const paged = paginateItems(cleanRows, queryParams);

  return {
    companyName,
    companyCreatedAt: companyCreatedDate,
    earliestRecordDate,
    period: window.period,
    periodLabel: window.periodLabel,
    startDate: window.startDate,
    endDate: window.endDate,
    totalRecords,
    totalWorkingHours,
    averageDailyHours,
    presentCount,
    lateCount,
    halfDayCount,
    absentCount,
    leaveCount,
    holidayCount,
    totalLateMinutes,
    totalOvertimeHours,
    totalBreakMinutes,
    totalBreakDelayMinutes,
    uniqueEmployees,
    records: paged.items,
    pagination: paged.pagination,
    leaveRecords: cleanLeaves,
    holidayRecords: cleanHolidays,
    employeeSummaries,
    employees: userLookup.employeeOptions,
    departments: userLookup.departments,
    csvContent,
  };
};

/**
 * Controller: Get Attendance Report (JSON + CSV)
 */
export const getAttendanceReport = async (req, res) => {
  try {
    if (!assertCompanyReportAccess(req, res)) return;

    const report = await buildAttendanceReportData(req.companyId, req.query);
    res.status(200).json(report);
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
};

/**
 * Controller: Send Attendance Report via Email
 */
export const sendAttendanceReport = async (req, res) => {
  try {
    if (!assertCompanyReportAccess(req, res)) return;

    const { recipientEmail, notes, ...filterParams } = req.body;
    if (!recipientEmail || !recipientEmail.trim()) {
      return res.status(400).json({ message: 'Recipient email is required' });
    }

    const report = await buildAttendanceReportData(req.companyId, { ...filterParams, limit: 'all' });

    const summaryMetrics = [
      { label: 'Total Working Hours', value: `${report.totalWorkingHours}h` },
      { label: 'Average Daily Hours', value: `${report.averageDailyHours}h` },
      { label: 'Total Attendances', value: `${report.totalRecords}` },
      { label: 'Active Employees', value: `${report.uniqueEmployees}` },
      { label: 'Present / Full-Day', value: `${report.presentCount}` },
      { label: 'Late / Half-Day / Absent', value: `${report.lateCount + report.halfDayCount + report.absentCount}` },
    ];

    const filename = `Attendance_Report_${report.companyName.replace(/[^a-zA-Z0-9]/g, '_')}_${report.periodLabel.replace(/[^a-zA-Z0-9]/g, '_')}.csv`;

    const mailResult = await sendReportEmail({
      to: recipientEmail.trim(),
      subject: `Attendance Report - ${report.companyName} (${report.periodLabel})`,
      companyName: report.companyName,
      reportType: 'Attendance Report',
      periodLabel: report.periodLabel,
      summaryMetrics,
      notes: notes ? String(notes).trim() : '',
      csvContent: report.csvContent,
      filename,
    });

    res.status(200).json({
      message: mailResult.simulated
        ? `Attendance report prepared for ${recipientEmail} (Simulated send: SMTP not configured)`
        : `Attendance report successfully sent to ${recipientEmail}`,
      mailResult,
      summary: {
        totalRecords: report.totalRecords,
        totalWorkingHours: report.totalWorkingHours,
        periodLabel: report.periodLabel,
      }
    });
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
};
