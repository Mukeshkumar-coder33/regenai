import Leave from '../models/Leave.js';
import Company from '../models/Company.js';
import User from '../models/User.js';
import Notification from '../models/Notification.js';
import Holiday from '../models/Holiday.js';
import mongoose from 'mongoose';
import { resolveCompanyId } from '../utils/resolveCompanyId.js';
import { emitToCompany, emitToUser } from '../socket.js';

export const DEFAULT_LEAVE_POLICY = {
  casualLeave: {
    enabled: true,
    monthlyEntitlement: 1,
    carryForward: true,
    maxCarryForward: 12,
    requiresApproval: true,
    unapprovedDeductionRate: 100
  },
  sickLeave: {
    enabled: true,
    monthlyEntitlement: 1,
    carryForward: false,
    maxCarryForward: 6,
    requiresApproval: true,
    unapprovedDeductionRate: 100
  },
  unpaidLeave: {
    enabled: true,
    approvedDeductionRate: 100,
    unapprovedDeductionRate: 100,
    sameDeductionRate: true
  }
};

/**
 * Calculates working days between start and end date excluding weekends (Sat/Sun) and company holidays.
 */
export const calculateWorkingDaysBetween = async (companyId, startDateStr, endDateStr) => {
  if (!startDateStr || !endDateStr) return 0;
  const start = new Date(startDateStr);
  const end = new Date(endDateStr);
  if (isNaN(start.getTime()) || isNaN(end.getTime()) || start > end) return 0;

  let holidaySet = new Set();
  try {
    const holidays = await Holiday.find(companyId ? { companyId } : {}).lean();
    holidaySet = new Set(holidays.map(h => (h.date || '').split('T')[0]));
  } catch (_) {}

  const weeklyOffs = [0, 6]; // Sunday, Saturday
  let workingDays = 0;
  const curr = new Date(start);
  while (curr <= end) {
    const dayOfWeek = curr.getDay();
    const isoDate = curr.toISOString().split('T')[0];
    if (!weeklyOffs.includes(dayOfWeek) && !holidaySet.has(isoDate)) {
      workingDays++;
    }
    curr.setDate(curr.getDate() + 1);
  }
  return workingDays;
};

/**
 * Derives current leave balance for a given user based on company policy and approved leaves.
 */
export const computeUserLeaveBalance = async (companyId, userId) => {
  let policy = DEFAULT_LEAVE_POLICY;
  if (companyId) {
    try {
      const comp = await Company.findById(companyId).lean();
      if (comp?.leavePolicy) {
        policy = {
          casualLeave: { ...DEFAULT_LEAVE_POLICY.casualLeave, ...(comp.leavePolicy.casualLeave || {}) },
          sickLeave: { ...DEFAULT_LEAVE_POLICY.sickLeave, ...(comp.leavePolicy.sickLeave || {}) },
          unpaidLeave: { ...DEFAULT_LEAVE_POLICY.unpaidLeave, ...(comp.leavePolicy.unpaidLeave || {}) }
        };
      }
    } catch (_) {}
  }

  const now = new Date();
  const currentYear = now.getFullYear();
  const currentMonth = now.getMonth(); // 0 to 11

  const startOfYear = `${currentYear}-01-01`;
  const endOfYear = `${currentYear}-12-31`;

  const approvedLeaves = await Leave.find({
    userId,
    ...(companyId ? { companyId } : {}),
    status: 'approved',
    startDate: { $gte: startOfYear, $lte: endOfYear }
  }).lean();

  // Casual Leave
  const casualEntitlement = Number(policy.casualLeave.monthlyEntitlement) || 1;
  const casualCarryForward = policy.casualLeave.carryForward !== false;
  const casualMaxCarry = Number(policy.casualLeave.maxCarryForward) || 12;

  let casualCarriedForward = 0;
  if (casualCarryForward) {
    casualCarriedForward = Math.min(currentMonth * casualEntitlement, casualMaxCarry);
  }
  const casualTotalAvailable = casualEntitlement + casualCarriedForward;
  const casualUsed = approvedLeaves
    .filter(l => l.type === 'casual')
    .reduce((sum, l) => sum + (Number(l.workingDays) || 1), 0);
  const casualRemaining = Math.max(0, casualTotalAvailable - casualUsed);

  // Sick Leave
  const sickEntitlement = Number(policy.sickLeave.monthlyEntitlement) || 1;
  const sickCarryForward = policy.sickLeave.carryForward === true;
  const sickMaxCarry = Number(policy.sickLeave.maxCarryForward) || 6;

  let sickCarriedForward = 0;
  if (sickCarryForward) {
    sickCarriedForward = Math.min(currentMonth * sickEntitlement, sickMaxCarry);
  }
  const sickTotalAvailable = sickEntitlement + sickCarriedForward;
  const sickUsed = approvedLeaves
    .filter(l => l.type === 'sick')
    .reduce((sum, l) => sum + (Number(l.workingDays) || 1), 0);
  const sickRemaining = Math.max(0, sickTotalAvailable - sickUsed);

  // Unpaid Leave
  const unpaidUsed = approvedLeaves
    .filter(l => l.type === 'unpaid')
    .reduce((sum, l) => sum + (Number(l.workingDays) || 1), 0);

  return {
    casual: {
      enabled: policy.casualLeave.enabled !== false,
      entitlement: casualEntitlement,
      carriedForward: casualCarriedForward,
      used: casualUsed,
      remaining: casualRemaining,
      requiresApproval: policy.casualLeave.requiresApproval !== false,
      unapprovedDeductionRate: Number(policy.casualLeave.unapprovedDeductionRate) || 100
    },
    sick: {
      enabled: policy.sickLeave.enabled !== false,
      entitlement: sickEntitlement,
      carriedForward: sickCarriedForward,
      used: sickUsed,
      remaining: sickRemaining,
      requiresApproval: policy.sickLeave.requiresApproval !== false,
      unapprovedDeductionRate: Number(policy.sickLeave.unapprovedDeductionRate) || 100
    },
    unpaid: {
      enabled: policy.unpaidLeave.enabled !== false,
      used: unpaidUsed,
      approvedDeductionRate: Number(policy.unpaidLeave.approvedDeductionRate) || 100,
      unapprovedDeductionRate: Number(policy.unpaidLeave.unapprovedDeductionRate) || 100,
      sameDeductionRate: policy.unpaidLeave.sameDeductionRate !== false
    }
  };
};

export const getLeavePolicy = async (req, res) => {
  try {
    const companyId = await resolveCompanyId(req);
    if (!companyId) {
      return res.status(200).json(DEFAULT_LEAVE_POLICY);
    }
    const comp = await Company.findById(companyId).lean();
    const policy = comp?.leavePolicy ? {
      casualLeave: { ...DEFAULT_LEAVE_POLICY.casualLeave, ...(comp.leavePolicy.casualLeave || {}) },
      sickLeave: { ...DEFAULT_LEAVE_POLICY.sickLeave, ...(comp.leavePolicy.sickLeave || {}) },
      unpaidLeave: { ...DEFAULT_LEAVE_POLICY.unpaidLeave, ...(comp.leavePolicy.unpaidLeave || {}) }
    } : DEFAULT_LEAVE_POLICY;
    res.status(200).json(policy);
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
};

export const updateLeavePolicy = async (req, res) => {
  try {
    const companyId = await resolveCompanyId(req);
    if (!companyId) {
      return res.status(400).json({ message: 'Company ID is required to configure leave policy' });
    }
    const { casualLeave, sickLeave, unpaidLeave } = req.body;
    const updateObj = {};
    if (casualLeave) updateObj['leavePolicy.casualLeave'] = casualLeave;
    if (sickLeave) updateObj['leavePolicy.sickLeave'] = sickLeave;
    if (unpaidLeave) updateObj['leavePolicy.unpaidLeave'] = unpaidLeave;

    const comp = await Company.findByIdAndUpdate(companyId, { $set: updateObj }, { new: true, upsert: true });
    emitToCompany('payroll:change', companyId, { action: 'leave_policy_updated' });
    res.status(200).json(comp.leavePolicy);
  } catch (error) {
    res.status(400).json({ message: error.message });
  }
};

export const getLeaveBalance = async (req, res) => {
  try {
    const targetUserId = req.params.userId || req.query.userId || req.user?.userId || req.user?.id;
    if (!targetUserId) {
      return res.status(400).json({ message: 'User ID required' });
    }
    const companyId = await resolveCompanyId(req);
    const balance = await computeUserLeaveBalance(companyId, targetUserId);
    res.status(200).json(balance);
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
};

export const createLeave = async (req, res) => {
  try {
    const body = { ...req.body };
    if (!body.id) body.id = new mongoose.Types.ObjectId().toString();
    if (!body.createdAt) body.createdAt = new Date().toISOString();
    if (!body.appliedAt) body.appliedAt = new Date().toISOString();
    if (!body.status) body.status = 'pending';
    body.companyId = await resolveCompanyId(req, body);

    const leaveType = (body.type || 'casual').toLowerCase();
    body.type = leaveType;

    // Resolve User Details
    if (body.userId) {
      const user = await User.findOne({
        $or: [
          { userId: body.userId },
          { id: body.userId },
          { _id: mongoose.isValidObjectId(body.userId) ? body.userId : null }
        ]
      }).lean();
      if (user) {
        body.employeeName = body.employeeName || user.name || user.username;
        body.department = body.department || user.department || user.designation || 'Staff';
        body.displayId = body.displayId || user.userId || user.id;
      }
    }

    // 1. Policy validation: Is category enabled?
    let policy = DEFAULT_LEAVE_POLICY;
    if (body.companyId) {
      const comp = await Company.findById(body.companyId).lean();
      if (comp?.leavePolicy) {
        policy = {
          casualLeave: { ...DEFAULT_LEAVE_POLICY.casualLeave, ...(comp.leavePolicy.casualLeave || {}) },
          sickLeave: { ...DEFAULT_LEAVE_POLICY.sickLeave, ...(comp.leavePolicy.sickLeave || {}) },
          unpaidLeave: { ...DEFAULT_LEAVE_POLICY.unpaidLeave, ...(comp.leavePolicy.unpaidLeave || {}) }
        };
      }
    }

    if (leaveType === 'casual' && policy.casualLeave.enabled === false) {
      return res.status(400).json({ message: 'Casual Leave is currently disabled by your company policy.' });
    }
    if (leaveType === 'sick' && policy.sickLeave.enabled === false) {
      return res.status(400).json({ message: 'Sick Leave is currently disabled by your company policy.' });
    }
    if (leaveType === 'unpaid' && policy.unpaidLeave.enabled === false) {
      return res.status(400).json({ message: 'Unpaid Leave is currently disabled by your company policy.' });
    }

    // 2. Date validation & working days calculation
    if (body.startDate > body.endDate) {
      return res.status(400).json({ message: 'End date must be greater than or equal to start date.' });
    }

    const workingDays = await calculateWorkingDaysBetween(body.companyId, body.startDate, body.endDate);
    if (workingDays === 0) {
      return res.status(400).json({ message: 'The selected date range contains no scheduled working days (weekends or public holidays).' });
    }
    body.workingDays = workingDays;

    // 3. Prevent overlapping active/pending requests
    const overlapping = await Leave.findOne({
      userId: body.userId,
      ...(body.companyId ? { companyId: body.companyId } : {}),
      status: { $in: ['pending', 'approved'] },
      startDate: { $lte: body.endDate },
      endDate: { $gte: body.startDate }
    });
    if (overlapping) {
      return res.status(400).json({
        message: `You already have an existing ${overlapping.status} leave request from ${overlapping.startDate} to ${overlapping.endDate}.`
      });
    }

    // 4. Balance check for paid leaves
    if (leaveType === 'casual' || leaveType === 'sick') {
      const balance = await computeUserLeaveBalance(body.companyId, body.userId);
      const remaining = leaveType === 'casual' ? balance.casual.remaining : balance.sick.remaining;
      if (workingDays > remaining) {
        return res.status(400).json({
          message: `Insufficient leave balance. You requested ${workingDays} working day(s), but only have ${remaining} day(s) remaining.`
        });
      }
      body.balanceAtRequest = remaining;
    }

    const leave = new Leave(body);
    await leave.save();
    emitToCompany('payroll:change', leave.companyId, { action: 'leave_created', userId: leave.userId });

    // Send real-time notification to Company Owner
    try {
      if (leave.companyId) {
        const comp = await Company.findById(leave.companyId).lean();
        if (comp && comp.ownerId) {
          const ownerUser = await User.findOne({
            $or: [
              { userId: comp.ownerId },
              { username: comp.ownerId },
              { _id: mongoose.isValidObjectId(comp.ownerId) ? comp.ownerId : null }
            ]
          }).select('userId username').lean();

          const targetOwnerId = ownerUser?.userId || comp.ownerId;
          const notif = new Notification({
            id: `leave-apply-${leave.id}`,
            companyId: leave.companyId,
            userId: targetOwnerId,
            title: 'Leave Application',
            message: `${leave.employeeName || 'An employee'} applied for ${leave.workingDays} working day(s) ${leave.type} leave (${leave.startDate} to ${leave.endDate}).`,
            type: 'leave',
            createdAt: new Date().toISOString(),
            read: false,
            metadata: {
              leaveId: leave.id,
              userId: leave.userId,
              type: leave.type,
              workingDays: leave.workingDays,
              startDate: leave.startDate,
              endDate: leave.endDate
            }
          });
          await notif.save();
          emitToUser(targetOwnerId, 'notification:new', notif);
        }
      }
    } catch (e) {
      console.error('Leave creation notification error:', e.message);
    }

    res.status(201).json(leave);
  } catch (error) {
    res.status(400).json({ message: error.message });
  }
};

export const getAllLeaves = async (req, res) => {
  try {
    const isSuperAdminView = req.headers['x-portal-view'] === 'superadmin' || req.query.portalView === 'superadmin';
    const isEmsView = req.headers['x-portal-view'] === 'ems' || req.query.portalView === 'ems';
    const isSuperAdmin = req.user?.role === 'param' || req.user?.role === 'admin' || isSuperAdminView;
    const filter = (isSuperAdmin && !isEmsView) ? {} : (req.companyId ? { companyId: req.companyId } : {});

    if (req.query.status) {
      filter.status = req.query.status;
    }
    if (req.query.type) {
      filter.type = req.query.type;
    }
    if (req.query.userId) {
      filter.userId = req.query.userId;
    }

    // Optional pagination
    const page = parseInt(req.query.page, 10);
    const limit = parseInt(req.query.limit, 10);

    if (page && limit) {
      const skip = (page - 1) * limit;
      const [leaves, total] = await Promise.all([
        Leave.find(filter).sort({ createdAt: -1 }).skip(skip).limit(limit),
        Leave.countDocuments(filter)
      ]);
      return res.status(200).json({
        leaves,
        total,
        page,
        totalPages: Math.ceil(total / limit)
      });
    }

    const leaves = await Leave.find(filter).sort({ createdAt: -1 });
    res.status(200).json(leaves);
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
};

export const getUserLeaves = async (req, res) => {
  try {
    const filter = { userId: req.params.userId };
    if (req.companyId) filter.companyId = req.companyId;

    const page = parseInt(req.query.page, 10);
    const limit = parseInt(req.query.limit, 10);

    if (page && limit) {
      const skip = (page - 1) * limit;
      const [leaves, total] = await Promise.all([
        Leave.find(filter).sort({ createdAt: -1 }).skip(skip).limit(limit),
        Leave.countDocuments(filter)
      ]);
      return res.status(200).json({
        leaves,
        total,
        page,
        totalPages: Math.ceil(total / limit)
      });
    }

    const leaves = await Leave.find(filter).sort({ createdAt: -1 });
    res.status(200).json(leaves);
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
};

export const updateLeaveStatus = async (req, res) => {
  try {
    const id = req.params.id;
    const filter = mongoose.isValidObjectId(id) ? { $or: [{ id }, { _id: id }] } : { id };
    if (req.companyId) filter.companyId = req.companyId;

    const updateFields = {
      status: req.body.status,
      approvalDate: new Date().toISOString(),
      approvedBy: req.user?.userId || req.user?.id || 'admin',
      approvedByName: req.user?.name || req.user?.username || 'Company Owner'
    };
    if (req.body.remarks || req.body.rejectionReason) {
      updateFields.remarks = req.body.remarks || req.body.rejectionReason;
      updateFields.rejectionReason = updateFields.remarks;
    }

    const leave = await Leave.findOneAndUpdate(filter, updateFields, { new: true });
    if (!leave) return res.status(404).json({ message: 'Leave not found' });
    emitToCompany('payroll:change', leave.companyId, { action: 'leave_updated', userId: leave.userId });

    // Send notification to employee
    try {
      if (leave.userId) {
        const isApproved = req.body.status === 'approved';
        const notif = new Notification({
          id: `leave-status-${leave.id}-${Date.now()}`,
          companyId: leave.companyId,
          userId: leave.userId,
          title: `Leave Application ${isApproved ? 'Approved' : 'Declined'}`,
          message: `Your leave request for ${leave.startDate} to ${leave.endDate} (${leave.workingDays || 1} day(s)) has been ${isApproved ? 'approved' : 'declined'}.${updateFields.remarks ? ' Remarks: ' + updateFields.remarks : ''}`,
          type: 'leave',
          createdAt: new Date().toISOString(),
          read: false,
          metadata: {
            leaveId: leave.id,
            status: leave.status,
            workingDays: leave.workingDays,
            remarks: updateFields.remarks
          }
        });
        await notif.save();
        emitToUser(leave.userId, 'notification:new', notif);
      }
    } catch (e) {
      console.error('Leave update notification error:', e.message);
    }

    res.status(200).json(leave);
  } catch (error) {
    res.status(400).json({ message: error.message });
  }
};

export const deleteLeave = async (req, res) => {
  try {
    const id = req.params.id;
    const filter = mongoose.isValidObjectId(id) ? { $or: [{ id }, { _id: id }] } : { id };
    if (req.companyId) filter.companyId = req.companyId;
    const leave = await Leave.findOneAndDelete(filter);
    if (!leave) return res.status(404).json({ message: 'Leave not found' });
    emitToCompany('payroll:change', leave.companyId, { action: 'leave_deleted', userId: leave.userId });
    res.status(200).json({ success: true, message: 'Leave removed successfully' });
  } catch (error) {
    res.status(400).json({ message: error.message });
  }
};
