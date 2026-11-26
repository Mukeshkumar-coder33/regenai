/**
 * Production-Quality Payroll Calculator for ReGen
 * Decimal-safe arithmetic with round-to-2 decimal places
 */

export const round2 = (num) => {
  const n = Number(num);
  if (isNaN(n)) return 0;
  return Math.round((n + Number.EPSILON) * 100) / 100;
};

export const parseSalaryAmount = (raw) => {
  if (typeof raw === 'number') return Number.isFinite(raw) ? raw : 0;
  if (raw === null || raw === undefined) return 0;
  const cleaned = String(raw).replace(/[₹,\s]/g, '').trim();
  const parsed = Number(cleaned);
  return Number.isFinite(parsed) ? parsed : 0;
};

const DAY_NAMES = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
const MONTH_NAMES = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

const formatReadableDate = (isoDate) => {
  const parts = String(isoDate || '').split('-');
  if (parts.length !== 3) return isoDate;
  const mIdx = Number(parts[1]) - 1;
  const day = Number(parts[2]);
  if (mIdx >= 0 && mIdx < 12) return `${MONTH_NAMES[mIdx]} ${day}`;
  return isoDate;
};

/**
 * Derives weekly off days from workingDaysPerWeek if not explicitly provided
 */
export const getWeeklyOffDays = (workingDaysPerWeek = 5, configuredWeeklyOffs = null) => {
  if (Array.isArray(configuredWeeklyOffs) && configuredWeeklyOffs.length > 0) {
    return configuredWeeklyOffs;
  }
  const days = Number(workingDaysPerWeek) || 5;
  if (days <= 4) return [0, 5, 6]; // Sun, Fri, Sat off
  if (days === 5) return [0, 6];    // Sun, Sat off
  if (days === 6) return [0];       // Sun off
  return [];                        // 7 days = no weekly off
};

/**
 * Parses time string (e.g. "09:30" or ISO timestamp) to minutes from midnight
 */
export const parseTimeToMinutes = (timeVal) => {
  if (!timeVal) return null;
  const s = String(timeVal).trim();
  if (s.includes('T')) {
    const d = new Date(s);
    if (!isNaN(d.getTime())) {
      return d.getHours() * 60 + d.getMinutes() + (d.getSeconds() / 60);
    }
  }
  const match = s.match(/^(\d{1,2}):(\d{2})(?:\s*(AM|PM))?/i);
  if (match) {
    let hrs = Number(match[1]);
    const mins = Number(match[2]);
    const ampm = match[3] ? match[3].toUpperCase() : null;
    if (ampm === 'PM' && hrs < 12) hrs += 12;
    if (ampm === 'AM' && hrs === 12) hrs = 0;
    return hrs * 60 + mins;
  }
  return null;
};

/**
 * Computes break delay deduction according to company PayrollSetting.
 * Default rule: ₹1 per 10 excess minutes (`per_interval_flat`).
 */
export const computeBreakDelayDeductionAmount = (delayMinutes, monthlySalary = 0, settings = {}) => {
  const mins = Number(delayMinutes) || 0;
  if (mins <= 0) return 0;
  if (settings.breakDelayDeductionEnabled === false) return 0;

  const ruleType = settings.breakDelayRuleType || 'per_interval_flat';
  if (ruleType === 'per_interval_flat') {
    const interval = Math.max(1, Number(settings.breakDelayIntervalMinutes) || 10);
    const amountPerInterval = settings.breakDelayIntervalAmount !== undefined
      ? Math.max(0, Number(settings.breakDelayIntervalAmount) || 0)
      : 1;
    const intervals = Math.floor(mins / interval);
    return round2(intervals * amountPerInterval);
  }

  // Fallback salary percentage per minute
  const sal = Number(monthlySalary) || 0;
  if (sal <= 0) return 0;
  const workingHoursPerDay = Number(settings.workingHoursPerDay) || 8;
  const workingDaysPerWeek = Number(settings.workingDaysPerWeek) || 5;
  const hourlyDeductionPct = Number(settings.hourlyDeductionPct) >= 0 ? Number(settings.hourlyDeductionPct) : 50;
  const scheduledHours = settings.payrollDivisorType === 'fixed_hours'
    ? Math.max(1, Number(settings.fixedPayrollDivisor) || 200)
    : Math.max(1, workingDaysPerWeek * 4.33 * workingHoursPerDay);
  const hourlyDeductionRate = (sal * (hourlyDeductionPct / 100)) / scheduledHours;
  const minuteRate = hourlyDeductionRate / 60;
  return round2(mins * minuteRate);
};

/**
 * Calculates actual hours between check-in and check-out safely.
 * Handles overnight shifts and fractional hours.
 */
export const calculateWorkedHours = (checkInStr, checkOutStr, status = 'present', defaultWorkingHours = 8) => {
  if (!checkInStr && !checkOutStr) {
    if (status === 'half_day') return round2(defaultWorkingHours / 2);
    return 0;
  }

  if (checkInStr && !checkOutStr) {
    if (status === 'half_day') return round2(defaultWorkingHours / 2);
    return 0; // Incomplete attendance or ongoing
  }

  const inDate = new Date(checkInStr);
  const outDate = new Date(checkOutStr);

  if (!isNaN(inDate.getTime()) && !isNaN(outDate.getTime())) {
    let diffMs = outDate.getTime() - inDate.getTime();
    if (diffMs < 0) {
      diffMs += 24 * 60 * 60 * 1000;
    }
    const hours = diffMs / (1000 * 60 * 60);
    return round2(Math.max(0, hours));
  }

  const inMinutes = parseTimeToMinutes(checkInStr);
  const outMinutes = parseTimeToMinutes(checkOutStr);

  if (inMinutes !== null && outMinutes !== null) {
    let diff = outMinutes - inMinutes;
    if (diff < 0) diff += 24 * 60;
    return round2(Math.max(0, diff / 60));
  }

  if (status === 'half_day') return round2(defaultWorkingHours / 2);
  return 0;
};

/**
 * Main Payroll Calculation Engine
 */
export const calculateEmployeeMonthlyPayroll = ({
  user,
  month,
  settings = {},
  leavePolicy = null,
  leaveBalance = null,
  attendances = [],
  leaves = [],
  holidays = [],
  adjustments = [],
  referenceDate = null,
}) => {
  const now = new Date();
  const [yearStr, monthStr] = (month || '').split('-');
  const year = Number(yearStr) || now.getFullYear();
  const monthNum = Number(monthStr) || (now.getMonth() + 1);
  const pad2 = (n) => String(n).padStart(2, '0');

  // Reference date YYYY-MM-DD (preserve explicit ISO date for deterministic tests; default to local today)
  const refIso = referenceDate
    ? new Date(referenceDate).toISOString().slice(0, 10)
    : `${now.getFullYear()}-${pad2(now.getMonth() + 1)}-${pad2(now.getDate())}`;

  const daysInMonth = new Date(year, monthNum, 0).getDate();

  // Company Settings & Rules
  const checkInTime = String(settings.checkInTime || '09:30').trim();
  const checkOutTime = String(settings.checkOutTime || '18:30').trim();
  const graceMinutes = Number(settings.graceMinutes) >= 0 ? Number(settings.graceMinutes) : 0;
  const workingHoursPerDay = Number(settings.workingHoursPerDay) || 8;
  const workingDaysPerWeek = Number(settings.workingDaysPerWeek) || 5;
  const weeklyOffDays = getWeeklyOffDays(workingDaysPerWeek, settings.weeklyOffDays);
  const hourlyDeductionPct = Number(settings.hourlyDeductionPct) >= 0 ? Number(settings.hourlyDeductionPct) : 50;
  const hourlyOvertimePct = Number(settings.hourlyOvertimePct) >= 0 ? Number(settings.hourlyOvertimePct) : 75;
  const approvedLeaveDeductionPct = Number(settings.approvedLeaveDeductionPct) >= 0 ? Number(settings.approvedLeaveDeductionPct) : 25;
  const unapprovedLeaveDeductionPct = Number(settings.unapprovedLeaveDeductionPct) >= 0 ? Number(settings.unapprovedLeaveDeductionPct) : 100;
  const payrollDivisorType = settings.payrollDivisorType || 'scheduled_hours';
  const fixedPayrollDivisor = Number(settings.fixedPayrollDivisor) || 200;
  const dailyBasisType = settings.dailyBasisType || 'scheduled_days';
  const breakTime = Number(settings.breakTime) >= 0 ? Number(settings.breakTime) : 60;
  const casualBreakTime = Number(settings.casualBreakTime) >= 0 ? Number(settings.casualBreakTime) : 15;

  const lateDeductionEnabled = settings.lateDeductionEnabled === true;
  const lateDeductionMode = settings.lateDeductionMode || 'hourly_rate';
  const rawLateRate = Number(settings.lateDeductionRate);
  const lateDeductionRate = (Number.isFinite(rawLateRate) && rawLateRate > 0)
    ? rawLateRate
    : (lateDeductionEnabled && lateDeductionMode === 'hourly_rate' ? 100 : 0);
  const shortfallDeductionEnabled = settings.shortfallDeductionEnabled !== false;
  const overtimeEnabled = settings.overtimeEnabled !== false;
  const overtimeMinMinutes = Number(settings.overtimeMinMinutes) >= 0 ? Number(settings.overtimeMinMinutes) : 0;
  const breakDelayDeductionEnabled = settings.breakDelayDeductionEnabled !== false;
  const breakDelayRuleType = settings.breakDelayRuleType || 'per_interval_flat';
  const breakDelayIntervalMinutes = Math.max(1, Number(settings.breakDelayIntervalMinutes) || 10);
  const breakDelayIntervalAmount = settings.breakDelayIntervalAmount !== undefined
    ? Math.max(0, Number(settings.breakDelayIntervalAmount) || 0)
    : 1;

  const monthlySalary = parseSalaryAmount(user?.salary);

  // Build lookups
  const holidayMap = new Map();
  holidays.forEach(h => {
    if (h.date) {
      const iso = String(h.date).split('T')[0];
      holidayMap.set(iso, h.name || 'Holiday');
    }
  });

  const attendanceMap = new Map();
  attendances.forEach(a => {
    if (a.date) {
      const iso = String(a.date).split('T')[0];
      if (!attendanceMap.has(iso) || (!attendanceMap.get(iso).checkOut && a.checkOut)) {
        attendanceMap.set(iso, a);
      }
    }
  });

  const isDateInLeave = (dateIso) => {
    let fallback = null;
    for (const l of leaves) {
      if (l.startDate && l.endDate && dateIso >= l.startDate && dateIso <= l.endDate) {
        if (l.status === 'approved') return l;
        if (!fallback) fallback = l;
      }
    }
    return fallback;
  };

  // Map adjustments created during this month to dates if available
  const adjustmentsByDate = new Map();
  adjustments.forEach(adj => {
    const rawDate = adj.date || (adj.createdAt ? new Date(adj.createdAt).toISOString().slice(0, 10) : null);
    if (rawDate && String(rawDate).startsWith(`${year}-${pad2(monthNum)}`)) {
      if (!adjustmentsByDate.has(rawDate)) adjustmentsByDate.set(rawDate, []);
      adjustmentsByDate.get(rawDate).push({
        type: adj.type,
        amount: Number(adj.amount) || 0,
        reason: adj.reason || (adj.type === 'bonus' ? 'Bonus' : 'Manual Deduction'),
      });
    }
  });

  // Track paid-leave balance consumption across enabled policy categories if leaveBalance provided
  const availablePaidPool = leaveBalance ? {
    casual: (!leavePolicy || leavePolicy.casualLeave?.enabled !== false) ? (Number(leaveBalance.casual?.remaining) || 0) : 0,
    sick: (!leavePolicy || leavePolicy.sickLeave?.enabled !== false) ? (Number(leaveBalance.sick?.remaining) || 0) : 0,
    earned: (!leavePolicy || leavePolicy.earnedLeave?.enabled !== false) ? (Number(leaveBalance.earned?.remaining) || 0) : 0,
  } : null;

  const unpaidPolicy = leavePolicy?.unpaidLeave || {};
  const unpaidUnapprovedRate = leavePolicy
    ? Number(
        unpaidPolicy.sameDeductionRate
          ? (unpaidPolicy.approvedDeductionRate ?? unapprovedLeaveDeductionPct)
          : (unpaidPolicy.unapprovedDeductionRate ?? unapprovedLeaveDeductionPct)
      )
    : unapprovedLeaveDeductionPct;

  // First pass: scheduled working days and hours
  let scheduledWorkingDaysCount = 0;
  for (let day = 1; day <= daysInMonth; day++) {
    const isoDate = `${year}-${pad2(monthNum)}-${pad2(day)}`;
    const d = new Date(year, monthNum - 1, day);
    const dayOfWeek = d.getDay();
    if (!holidayMap.has(isoDate) && !weeklyOffDays.includes(dayOfWeek)) {
      scheduledWorkingDaysCount++;
    }
  }

  const scheduledWorkingHours = round2(scheduledWorkingDaysCount * workingHoursPerDay);
  const payrollDivisor = payrollDivisorType === 'fixed_hours'
    ? fixedPayrollDivisor
    : (scheduledWorkingHours > 0 ? scheduledWorkingHours : 1);

  const hourlyDeductionRate = round2((monthlySalary * (hourlyDeductionPct / 100)) / (payrollDivisor || 1));
  const hourlyOvertimeRate = round2((monthlySalary * (hourlyOvertimePct / 100)) / (payrollDivisor || 1));

  const dailySalaryBasis = dailyBasisType === 'calendar_days'
    ? round2(monthlySalary / (daysInMonth || 1))
    : round2(monthlySalary / (scheduledWorkingDaysCount || 1));

  const targetCheckInMinutes = parseTimeToMinutes(checkInTime);

  const resolvedSettings = {
    checkInTime,
    checkOutTime,
    graceMinutes,
    workingHoursPerDay,
    workingDaysPerWeek,
    weeklyOffDays,
    breakTime,
    casualBreakTime,
    hourlyDeductionPct,
    hourlyOvertimePct,
    approvedLeaveDeductionPct,
    unapprovedLeaveDeductionPct,
    payrollDivisorType,
    fixedPayrollDivisor,
    dailyBasisType,
    lateDeductionEnabled,
    lateDeductionMode,
    lateDeductionRate,
    shortfallDeductionEnabled,
    overtimeEnabled,
    overtimeMinMinutes,
    breakDelayDeductionEnabled,
    breakDelayRuleType,
    breakDelayIntervalMinutes,
    breakDelayIntervalAmount,
  };

  // Second pass: calculate daily breakdown
  const dailyBreakdown = [];
  let totalActualHours = 0;
  let totalShortfallHours = 0;
  let totalOvertimeHours = 0;
  let totalApprovedLeaveDays = 0;
  let totalUnapprovedLeaveDays = 0;
  let totalPresentDays = 0;
  let totalHolidayDays = 0;
  let totalWeeklyOffDays = 0;
  let totalLateMinutes = 0;
  let totalLateDeduction = 0;
  let totalBreakDelayMinutes = 0;
  let totalBreakDeduction = 0;
  let approvedLeaveDeductionSum = 0;
  let unapprovedLeaveDeductionSum = 0;
  let paidUnapprovedLeaveDeduction = 0;
  let unpaidApprovedLeaveDeduction = 0;
  let unpaidUnapprovedLeaveDeduction = 0;

  for (let day = 1; day <= daysInMonth; day++) {
    const isoDate = `${year}-${pad2(monthNum)}-${pad2(day)}`;
    const readableDate = formatReadableDate(isoDate);
    const d = new Date(year, monthNum - 1, day);
    const dayOfWeek = d.getDay();
    const dayName = DAY_NAMES[dayOfWeek];
    const isFuture = isoDate > refIso;
    const isHoliday = holidayMap.has(isoDate);
    const holidayName = isHoliday ? holidayMap.get(isoDate) : null;
    const isWeeklyOff = weeklyOffDays.includes(dayOfWeek);
    const dayAdjs = adjustmentsByDate.get(isoDate) || [];

    const item = {
      date: isoDate,
      dayOfWeek,
      dayName,
      isHoliday,
      holidayName,
      isWeeklyOff,
      isApprovedLeave: false,
      isUnapprovedLeave: false,
      isPresent: false,
      isFuture,
      attendanceStatus: isHoliday ? 'holiday' : (isWeeklyOff ? 'weekly_off' : 'absent'),
      leaveType: null,
      leaveApprovalStatus: 'none',
      checkIn: null,
      checkOut: null,
      requiredHours: 0,
      actualHours: 0,
      shortfallHours: 0,
      overtimeHours: 0,
      shortfallDeduction: 0,
      overtimeAddition: 0,
      leaveDeduction: 0,
      lateMinutes: 0,
      lateDeduction: 0,
      breakMinutes: 0,
      casualBreakMinutes: 0,
      breakDelayMinutes: 0,
      casualBreakDelayMinutes: 0,
      totalBreakDelayMinutes: 0,
      breakDeduction: 0,
      dailyAdjustments: dayAdjs,
      notes: '',
      explanation: '',
    };

    const appendAdjText = (baseExp) => {
      if (!dayAdjs.length) return baseExp;
      const adjNotes = dayAdjs.map(a =>
        `${a.type === 'bonus' ? 'Bonus' : 'Manual deduction'} (${a.reason}) — ₹${round2(a.amount)} ${a.type === 'bonus' ? 'added' : 'deducted'}`
      ).join('; ');
      return `${baseExp} | ${adjNotes}`;
    };

    if (isHoliday) {
      totalHolidayDays++;
      item.notes = `Holiday: ${holidayName}`;
      item.explanation = appendAdjText(`${readableDate} — Holiday (${holidayName}) — ₹0 deduction`);
      dailyBreakdown.push(item);
      continue;
    }

    if (isWeeklyOff) {
      totalWeeklyOffDays++;
      item.notes = 'Weekly Off';
      item.explanation = appendAdjText(`${readableDate} — Weekly Off — ₹0 deduction`);
      dailyBreakdown.push(item);
      continue;
    }

    item.requiredHours = workingHoursPerDay;

    const att = attendanceMap.get(isoDate);
    const leave = isDateInLeave(isoDate);

    if (att) {
      item.checkIn = att.checkIn || null;
      item.checkOut = att.checkOut || null;
      item.isPresent = true;
      item.attendanceStatus = att.status || 'present';
      totalPresentDays++;

      item.breakMinutes = Number(att.breakMinutes) || 0;
      item.casualBreakMinutes = Number(att.casualBreakMinutes) || 0;
      item.breakDelayMinutes = Number(att.breakDelayMinutes) || 0;
      item.casualBreakDelayMinutes = Number(att.casualBreakDelayMinutes) || 0;
      const delayMins = Math.max(
        Number(att.totalBreakDelayMinutes) || 0,
        item.breakDelayMinutes + item.casualBreakDelayMinutes
      );
      item.totalBreakDelayMinutes = delayMins;

      const dayBreakDed = computeBreakDelayDeductionAmount(delayMins, monthlySalary, resolvedSettings);
      item.breakDeduction = dayBreakDed;
      totalBreakDelayMinutes += delayMins;
      totalBreakDeduction = round2(totalBreakDeduction + dayBreakDed);

      // Late evaluation honoring graceMinutes and recorded late status
      if (att.checkIn && att.status !== 'half_day' && targetCheckInMinutes !== null) {
        const actualInMins = parseTimeToMinutes(att.checkIn);
        if (actualInMins !== null && actualInMins > (targetCheckInMinutes + graceMinutes)) {
          item.lateMinutes = Math.round(actualInMins - (targetCheckInMinutes + graceMinutes));
          item.attendanceStatus = 'late';
        }
      }
      if (item.lateMinutes === 0 && Number(att.lateMinutes) > 0) {
        item.lateMinutes = Math.round(Number(att.lateMinutes));
        item.attendanceStatus = 'late';
      }
      if (item.lateMinutes > 0 || (att.status === 'late' && lateDeductionMode === 'fixed_per_late')) {
        totalLateMinutes += item.lateMinutes;
        if (lateDeductionEnabled && lateDeductionRate > 0) {
          let lDed = 0;
          if (lateDeductionMode === 'fixed_per_late') {
            lDed = round2(lateDeductionRate);
          } else if (lateDeductionMode === 'per_minute') {
            lDed = round2(item.lateMinutes * lateDeductionRate);
          } else {
            const lateHrRate = round2((monthlySalary * (lateDeductionRate / 100)) / (payrollDivisor || 1));
            lDed = round2((item.lateMinutes / 60) * lateHrRate);
          }
          item.lateDeduction = lDed;
          totalLateDeduction = round2(totalLateDeduction + lDed);
        }
      }

      // Worked hours & preventing double-deduction of excess break minutes
      const grossHours = calculateWorkedHours(att.checkIn, att.checkOut, att.status, workingHoursPerDay);
      const hasRecordedNetHours = Number(att.totalWorkingHours) > 0;
      const netHours = hasRecordedNetHours ? round2(att.totalWorkingHours) : grossHours;
      item.actualHours = netHours;
      totalActualHours = round2(totalActualHours + netHours);

      // If break delay is already penalized via breakDeduction, credit back excess break hours
      // against shortfallHours so excess break minutes are NOT deducted twice.
      const effectiveHoursForShortfall = (hasRecordedNetHours && dayBreakDed > 0 && delayMins > 0)
        ? Math.min(grossHours, round2(netHours + (delayMins / 60)))
        : netHours;

      if (effectiveHoursForShortfall >= workingHoursPerDay) {
        const rawOt = round2(effectiveHoursForShortfall - workingHoursPerDay);
        const otValid = overtimeEnabled && (rawOt * 60 >= overtimeMinMinutes) && rawOt > 0;
        item.overtimeHours = otValid ? rawOt : 0;
        item.shortfallHours = 0;
        item.overtimeAddition = otValid ? round2(rawOt * hourlyOvertimeRate) : 0;
        item.shortfallDeduction = 0;
        totalOvertimeHours = round2(totalOvertimeHours + item.overtimeHours);
        item.notes = item.overtimeHours > 0 ? `Overtime +${item.overtimeHours}h` : 'On Time / Full Day';
      } else {
        if (!att.checkOut && !isFuture && att.status !== 'half_day') {
          item.notes = 'Missing check-out (incomplete)';
        } else if (att.status === 'half_day') {
          item.notes = 'Half Day attendance';
        }
        const sf = round2(workingHoursPerDay - effectiveHoursForShortfall);
        item.shortfallHours = shortfallDeductionEnabled ? sf : 0;
        item.overtimeHours = 0;
        item.shortfallDeduction = shortfallDeductionEnabled ? round2(sf * hourlyDeductionRate) : 0;
        item.overtimeAddition = 0;
        totalShortfallHours = round2(totalShortfallHours + item.shortfallHours);
        if (!item.notes) item.notes = `Shortfall -${sf}h`;
      }

      const dayTotalDed = round2(item.shortfallDeduction + item.lateDeduction + item.breakDeduction);
      const reasons = [];
      if (item.lateDeduction > 0) reasons.push(`Late (${item.lateMinutes}m: -₹${item.lateDeduction})`);
      if (item.breakDeduction > 0) reasons.push(`Break delay (${delayMins}m: -₹${item.breakDeduction})`);
      if (item.shortfallDeduction > 0) reasons.push(`Shortfall (-${item.shortfallHours}h: -₹${item.shortfallDeduction})`);

      let daySummary;
      if (item.overtimeAddition > 0 && dayTotalDed === 0) {
        daySummary = `${readableDate} — Overtime (+${item.overtimeHours}h) — ₹${item.overtimeAddition} added`;
      } else if (dayTotalDed > 0) {
        daySummary = `${readableDate} — Present (${reasons.join(', ')}) — ₹${dayTotalDed} deduction${item.overtimeAddition > 0 ? `, +₹${item.overtimeAddition} OT` : ''}`;
      } else {
        daySummary = `${readableDate} — Present — ₹0 deduction`;
      }
      item.explanation = appendAdjText(daySummary);
    } else if (leave && leave.status === 'approved') {
      item.isApprovedLeave = true;
      item.attendanceStatus = 'leave';
      item.leaveType = (leave.type || 'casual').toLowerCase();
      item.leaveApprovalStatus = 'approved';
      totalApprovedLeaveDays++;

      let dedPct = approvedLeaveDeductionPct;
      if (leavePolicy) {
        if (['casual', 'sick', 'earned'].includes(item.leaveType)) {
          const policyKey = item.leaveType === 'casual' ? 'casualLeave' : (item.leaveType === 'sick' ? 'sickLeave' : 'earnedLeave');
          const catEnabled = leavePolicy[policyKey]?.enabled !== false;
          if (catEnabled && (!availablePaidPool || availablePaidPool[item.leaveType] > 0)) {
            dedPct = 0; // Paid leave approved within available balance -> 0% deduction
            if (availablePaidPool) {
              availablePaidPool[item.leaveType] = Math.max(0, availablePaidPool[item.leaveType] - 1);
            }
          } else {
            dedPct = approvedLeaveDeductionPct;
          }
        } else {
          dedPct = Number(leavePolicy.unpaidLeave?.approvedDeductionRate ?? approvedLeaveDeductionPct) || 0;
        }
      }

      item.leaveDeduction = round2(dailySalaryBasis * (dedPct / 100));
      approvedLeaveDeductionSum = round2(approvedLeaveDeductionSum + item.leaveDeduction);
      if (item.leaveType === 'unpaid') {
        unpaidApprovedLeaveDeduction = round2(unpaidApprovedLeaveDeduction + item.leaveDeduction);
      }

      const paidTag = dedPct === 0 ? 'Paid' : 'Unpaid';
      item.notes = `Approved Leave (${item.leaveType} - ${paidTag})`;
      item.explanation = appendAdjText(
        `${readableDate} — Approved ${item.leaveType} leave (${paidTag}) — ₹${item.leaveDeduction} deduction`
      );
    } else if (!isFuture) {
      item.isUnapprovedLeave = true;
      item.attendanceStatus = 'absent';
      totalUnapprovedLeaveDays++;

      let dedPct = unpaidUnapprovedRate;
      let label = 'Unapproved unpaid leave';

      if (leavePolicy) {
        const lType = leave ? (leave.type || 'unpaid').toLowerCase() : null;
        item.leaveType = lType || 'unpaid';
        item.leaveApprovalStatus = leave ? (leave.status || 'pending') : 'none';

        if (leave && lType && ['casual', 'sick', 'earned'].includes(lType)) {
          const policyKey = lType === 'casual' ? 'casualLeave' : (lType === 'sick' ? 'sickLeave' : 'earnedLeave');
          const catPolicy = leavePolicy[policyKey] || {};
          const catEnabled = catPolicy.enabled !== false;

          if (catEnabled && catPolicy.requiresApproval === false && (!availablePaidPool || availablePaidPool[lType] > 0)) {
            dedPct = 0;
            if (availablePaidPool) availablePaidPool[lType] = Math.max(0, availablePaidPool[lType] - 1);
            label = `Auto-approved ${lType} leave`;
          } else if (catEnabled && (!availablePaidPool || availablePaidPool[lType] > 0)) {
            if (availablePaidPool) availablePaidPool[lType] = Math.max(0, availablePaidPool[lType] - 1);
            dedPct = Number(catPolicy.unapprovedDeductionRate ?? unapprovedLeaveDeductionPct);
            label = `Unapproved ${lType} (paid) leave`;
            paidUnapprovedLeaveDeduction = round2(paidUnapprovedLeaveDeduction + round2(dailySalaryBasis * (dedPct / 100)));
          } else {
            item.leaveType = 'unpaid';
            dedPct = unpaidUnapprovedRate;
            label = catEnabled ? 'Unapproved unpaid leave (paid balance exhausted)' : 'Unapproved unpaid leave';
          }
        } else if (!leave && availablePaidPool) {
          // Only auto-cover an unapplied absence when an enabled paid category explicitly disables approval
          const autoKey = (leavePolicy.casualLeave?.enabled !== false && leavePolicy.casualLeave?.requiresApproval === false && availablePaidPool.casual > 0)
            ? 'casual'
            : ((leavePolicy.earnedLeave?.enabled !== false && leavePolicy.earnedLeave?.requiresApproval === false && availablePaidPool.earned > 0)
              ? 'earned'
              : null);
          if (autoKey) {
            item.leaveType = autoKey;
            dedPct = 0;
            availablePaidPool[autoKey] = Math.max(0, availablePaidPool[autoKey] - 1);
            label = `Auto-approved ${autoKey} leave`;
          } else {
            item.leaveType = 'unpaid';
            dedPct = unpaidUnapprovedRate;
            label = 'Unapproved unpaid absence';
          }
        } else {
          item.leaveType = 'unpaid';
          dedPct = unpaidUnapprovedRate;
          label = leave ? 'Unapproved unpaid leave' : 'Unapproved unpaid absence';
        }
      } else {
        item.leaveType = leave ? (leave.type || 'unpaid') : 'unpaid';
        item.leaveApprovalStatus = leave ? (leave.status || 'pending') : 'none';
      }

      item.leaveDeduction = round2(dailySalaryBasis * (dedPct / 100));
      unapprovedLeaveDeductionSum = round2(unapprovedLeaveDeductionSum + item.leaveDeduction);
      if (item.leaveType === 'unpaid' || !label.includes('(paid)')) {
        unpaidUnapprovedLeaveDeduction = round2(unpaidUnapprovedLeaveDeduction + item.leaveDeduction);
      }

      item.notes = leave ? `${label} (${leave.status})` : label;
      item.explanation = appendAdjText(`${readableDate} — ${label} — ₹${item.leaveDeduction} deduction`);
    } else {
      item.isFuture = true;
      item.attendanceStatus = 'scheduled';
      item.notes = 'Scheduled working day';
      item.explanation = appendAdjText(`${readableDate} — Scheduled working day — ₹0 deduction`);
    }

    dailyBreakdown.push(item);
  }

  // Monthly totals summed directly from dailyBreakdown + adjustments
  const bonus = round2(
    adjustments.filter(a => a.type === 'bonus').reduce((sum, a) => sum + (Number(a.amount) || 0), 0)
  );
  const manualDeduction = round2(
    adjustments.filter(a => a.type === 'deduction').reduce((sum, a) => sum + (Number(a.amount) || 0), 0)
  );

  const hourlyShortfallDeduction = round2(
    dailyBreakdown.reduce((sum, item) => sum + (Number(item.shortfallDeduction) || 0), 0)
  );
  const hourlyOvertimeAddition = round2(
    dailyBreakdown.reduce((sum, item) => sum + (Number(item.overtimeAddition) || 0), 0)
  );
  const approvedLeaveDeduction = round2(approvedLeaveDeductionSum);
  const unapprovedLeaveDeduction = round2(unapprovedLeaveDeductionSum);
  const otherAdjustments = 0;

  const autoAttendanceAndLeaveDeductions = round2(
    hourlyShortfallDeduction + approvedLeaveDeduction + unapprovedLeaveDeduction + totalLateDeduction + totalBreakDeduction
  );
  const earnedSalary = Math.max(0, round2(monthlySalary + hourlyOvertimeAddition - autoAttendanceAndLeaveDeductions));

  const totalDeductions = round2(autoAttendanceAndLeaveDeductions + manualDeduction);
  const totalAdditions = round2(hourlyOvertimeAddition + bonus + otherAdjustments);
  const grossPayable = round2(monthlySalary + totalAdditions);
  const totalAmount = Math.max(0, round2(grossPayable - totalDeductions));
  const netPayable = totalAmount;
  const excessDeduction = totalDeductions > grossPayable ? round2(totalDeductions - grossPayable) : 0;

  return {
    month,
    userId: user.userId || user.StaffId || String(user._id),
    name: user.name || user.username || user.userId,
    designation: user.designation || 'Staff',
    department: user.department || 'General',
    baseSalary: monthlySalary,
    earnedSalary,
    scheduledWorkingDays: scheduledWorkingDaysCount,
    scheduledWorkingHours,
    actualWorkingHours: totalActualHours,
    shortfallHours: totalShortfallHours,
    overtimeHours: totalOvertimeHours,
    approvedLeaveDays: totalApprovedLeaveDays,
    unapprovedLeaveDays: totalUnapprovedLeaveDays,
    holidayDays: totalHolidayDays,
    weeklyOffDays: totalWeeklyOffDays,
    presentDays: totalPresentDays,
    payrollDivisor,
    hourlyDeductionRate,
    hourlyOvertimeRate,
    dailySalaryBasis,
    hourlyShortfallDeduction,
    hourlyOvertimeAddition,
    approvedLeaveDeduction,
    unapprovedLeaveDeduction,
    lateMinutes: totalLateMinutes,
    lateDeduction: totalLateDeduction,
    leaveDeductionBreakdown: {
      paidUnapproved: round2(paidUnapprovedLeaveDeduction),
      unpaidApproved: round2(unpaidApprovedLeaveDeduction),
      unpaidUnapproved: round2(unpaidUnapprovedLeaveDeduction),
    },
    bonus,
    manualDeduction,
    totalBreakDelayMinutes,
    totalBreakDeduction,
    otherAdjustments,
    grossPayable,
    totalDeductions,
    totalAdditions,
    totalAmount,
    netPayable,
    excessDeduction,
    snapshotSettings: resolvedSettings,
    dailyBreakdown,
  };
};

export default {
  round2,
  getWeeklyOffDays,
  parseTimeToMinutes,
  computeBreakDelayDeductionAmount,
  calculateWorkedHours,
  calculateEmployeeMonthlyPayroll,
};
