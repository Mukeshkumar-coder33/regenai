import mongoose from 'mongoose';
import Payroll from '../models/Payroll.js';
import PayrollSetting from '../models/PayrollSetting.js';
import PayrollPolicyHistory from '../models/PayrollPolicyHistory.js';
import PaymentTransaction from '../models/PaymentTransaction.js';
import PayrollAdjustment from '../models/PayrollAdjustment.js';
import User from '../models/User.js';
import Company from '../models/Company.js';
import Attendance from '../models/Attendance.js';
import Leave from '../models/Leave.js';
import Holiday from '../models/Holiday.js';
import {
  calculateEmployeeMonthlyPayroll,
  round2,
  getWeeklyOffDays,
} from '../utils/payrollCalculator.js';
import { generatePayslipPdfBuffer } from '../utils/payslipPdf.js';
import { DEFAULT_LEAVE_POLICY, computeUserLeaveBalance } from './leaveController.js';
import { createAndSendNotification } from './notificationController.js';
import { emitToCompany, emitToUser } from '../socket.js';
import { sendReportEmail } from '../utils/mailer.js';
import {
  resolveReportWindow,
  normalizeDateOnly,
  buildCompanyUserLookup,
  matchesEmployeeFilter,
  paginateItems,
  buildCsvDocument,
} from '../utils/reportHelpers.js';

const DEFAULT_PAYROLL_SETTINGS = {
  checkInTime: '09:30',
  checkOutTime: '18:30',
  workingHoursPerDay: 8,
  workingDaysPerWeek: 5,
  breakTime: 60,
  casualBreakTime: 15,
  weeklyOffDays: [0, 6],
  hourlyDeductionPct: 50,
  hourlyOvertimePct: 75,
  approvedLeaveDeductionPct: 25,
  unapprovedLeaveDeductionPct: 100,
  graceMinutes: 0,
  payrollDivisorType: 'scheduled_hours',
  fixedPayrollDivisor: 200,
  dailyBasisType: 'scheduled_days',
  lateDeductionEnabled: true,
  lateDeductionMode: 'hourly_rate',
  lateDeductionRate: 100,
  shortfallDeductionEnabled: true,
  overtimeEnabled: true,
  overtimeMinMinutes: 0,
  breakDelayDeductionEnabled: true,
  breakDelayRuleType: 'per_interval_flat',
  breakDelayIntervalMinutes: 10,
  breakDelayIntervalAmount: 1,
  policyVersion: 1,
};

const getCurrentMonthStr = () => {
  const now = new Date();
  return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`;
};

const getTodayIsoStr = () => {
  const now = new Date();
  return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-${String(now.getDate()).padStart(2, '0')}`;
};

const getPastMonthEndDate = (ym) => {
  const [y, m] = String(ym || '').split('-').map(Number);
  if (!y || !m) return null;
  return new Date(Date.UTC(y, m, 0, 23, 59, 59, 999));
};

const requireCompanyId = (req, res, allowEmpty = false) => {
  if (!req.companyId) {
    if (allowEmpty) return null;
    res.status(400).json({ message: 'Company context required' });
    return null;
  }
  return req.companyId;
};

const isCompanyAdmin = (user) => {
  if (!user || !user.role) return false;
  const role = typeof user.role === 'object' ? Object.keys(user.role)[0] : String(user.role);
  return ['admin', 'owner', 'param'].includes(role.toLowerCase());
};

const getUserCandidateIds = (u) => {
  const ids = new Set();
  if (!u) return [];
  if (u.userId) ids.add(String(u.userId).trim());
  if (u.StaffId) ids.add(String(u.StaffId).trim());
  if (u.username) ids.add(String(u.username).trim());
  if (u._id) ids.add(String(u._id));
  return Array.from(ids);
};

const getNormalizedPayrollSettings = (rawSettings) => {
  const merged = { ...DEFAULT_PAYROLL_SETTINGS, ...(rawSettings || {}) };
  // Untouched legacy settings docs stored before dynamic late defaults had
  // lateDeductionEnabled=false and lateDeductionRate=0 with no updatedBy/policyVersion>1.
  const isUntouchedLegacyDefault =
    rawSettings &&
    !rawSettings.updatedBy &&
    (Number(rawSettings.policyVersion) || 1) <= 1 &&
    rawSettings.lateDeductionEnabled === false &&
    Number(rawSettings.lateDeductionRate || 0) === 0;
  if (isUntouchedLegacyDefault) {
    merged.lateDeductionEnabled = true;
    merged.lateDeductionMode = 'hourly_rate';
    merged.lateDeductionRate = 100;
  }
  return merged;
};

const findCompanyUser = async (companyId, identifier) => {
  if (!identifier) return null;
  const idStr = String(identifier).trim();
  return User.findOne({
    $or: [
      { userId: idStr },
      { StaffId: idStr },
      { username: idStr },
      ...(mongoose.isValidObjectId(idStr) ? [{ _id: idStr }] : []),
    ],
    companyId,
  }).lean();
};

const mergeLeavePolicy = (rawPolicy) => {
  if (!rawPolicy) return DEFAULT_LEAVE_POLICY;
  return {
    casualLeave: { ...DEFAULT_LEAVE_POLICY.casualLeave, ...(rawPolicy.casualLeave || {}) },
    sickLeave: { ...DEFAULT_LEAVE_POLICY.sickLeave, ...(rawPolicy.sickLeave || {}) },
    earnedLeave: { ...DEFAULT_LEAVE_POLICY.earnedLeave, ...(rawPolicy.earnedLeave || {}) },
    unpaidLeave: { ...DEFAULT_LEAVE_POLICY.unpaidLeave, ...(rawPolicy.unpaidLeave || {}) },
  };
};

const resolvePolicyForMonth = async (companyId, month, companyDoc = null) => {
  const rawSettings = await PayrollSetting.findOne({ companyId }).lean();
  const currentSettings = getNormalizedPayrollSettings(rawSettings);
  const currentLeavePolicy = mergeLeavePolicy(companyDoc?.leavePolicy);
  const currMonth = getCurrentMonthStr();

  if (month && month < currMonth) {
    const hist = await PayrollPolicyHistory.findOne({
      companyId,
      effectiveFrom: { $lte: `${month}-31` },
    }).sort({ effectiveFrom: -1, policyVersion: -1 }).lean();

    if (hist?.settingsSnapshot) {
      return {
        settings: getNormalizedPayrollSettings(hist.settingsSnapshot),
        leavePolicy: hist.leavePolicySnapshot ? mergeLeavePolicy(hist.leavePolicySnapshot) : currentLeavePolicy,
      };
    }
  }

  return {
    settings: currentSettings,
    leavePolicy: currentLeavePolicy,
  };
};

const sumTransactionsForPayroll = (transactions, payrollId, candidateIds) => {
  const seen = new Set();
  let total = 0;
  const candidateSet = new Set(candidateIds.map(String));
  const pidStr = payrollId ? String(payrollId) : null;

  for (const tx of transactions) {
    if (tx.status && tx.status !== 'completed') continue;
    const key = String(tx._id || tx.id);
    if (seen.has(key)) continue;

    const matchByPayroll = pidStr && tx.payrollId && String(tx.payrollId) === pidStr;
    const matchByUser = tx.userId && candidateSet.has(String(tx.userId));
    if (matchByPayroll || (!tx.payrollId && matchByUser) || (pidStr && matchByPayroll) || (!pidStr && matchByUser)) {
      seen.add(key);
      total = round2(total + (Number(tx.amount) || 0));
    }
  }
  return total;
};

const buildFinalizedRecordView = (existing, user, userAdjustments, transactions) => {
  const candidateIds = getUserCandidateIds(user);
  const txBonus = round2(userAdjustments.filter(a => a.type === 'bonus').reduce((sum, a) => sum + Number(a.amount || 0), 0));
  const txManualDed = round2(userAdjustments.filter(a => a.type === 'deduction').reduce((sum, a) => sum + Number(a.amount || 0), 0));

  const bonus = userAdjustments.length > 0 ? txBonus : (existing.bonus || 0);
  const manualDeduction = userAdjustments.length > 0 ? txManualDed : (existing.manualDeduction || 0);

  const hourlyOvertimeAddition = round2(existing.hourlyOvertimeAddition || 0);
  const hourlyShortfallDeduction = round2(existing.hourlyShortfallDeduction || 0);
  const approvedLeaveDeduction = round2(existing.approvedLeaveDeduction || 0);
  const unapprovedLeaveDeduction = round2(existing.unapprovedLeaveDeduction || 0);
  const lateDeduction = round2(existing.lateDeduction || 0);
  const totalBreakDeduction = round2(existing.totalBreakDeduction || 0);
  const baseSalary = round2(existing.baseSalary || Number(user.salary) || 0);

  const totalAdditions = round2(hourlyOvertimeAddition + bonus);
  const totalDeductions = round2(
    hourlyShortfallDeduction +
    approvedLeaveDeduction +
    unapprovedLeaveDeduction +
    lateDeduction +
    totalBreakDeduction +
    manualDeduction
  );
  const earnedSalary = Math.max(
    0,
    round2(baseSalary + hourlyOvertimeAddition - (hourlyShortfallDeduction + approvedLeaveDeduction + unapprovedLeaveDeduction + lateDeduction + totalBreakDeduction))
  );
  const grossPayable = round2(baseSalary + totalAdditions);
  const totalAmount = Math.max(0, round2(grossPayable - totalDeductions));
  const netPayable = totalAmount;

  let amountPaid = sumTransactionsForPayroll(transactions, existing._id, candidateIds);
  if (amountPaid === 0 && existing.paymentStatus === 'paid') {
    amountPaid = existing.amountPaid > 0 ? existing.amountPaid : totalAmount;
  }

  const pendingAmount = Math.max(0, round2(totalAmount - amountPaid));
  const isPaid = pendingAmount <= 0.01 && (amountPaid > 0 || existing.paymentStatus === 'paid');
  const isPartiallyPaid = amountPaid > 0 && pendingAmount > 0.01;
  const paymentStatus = isPaid ? 'paid' : (isPartiallyPaid ? 'partially_paid' : (existing.paymentStatus || 'unpaid'));

  return {
    ...existing,
    name: user.name || user.username || user.userId,
    StaffId: user.StaffId || user.userId,
    designation: user.designation || 'Staff',
    department: user.department || 'General',
    baseSalary,
    earnedSalary,
    bonus,
    manualDeduction,
    hourlyOvertimeAddition,
    totalAdditions,
    hourlyShortfallDeduction,
    approvedLeaveDeduction,
    unapprovedLeaveDeduction,
    lateDeduction,
    totalBreakDeduction,
    totalDeductions,
    grossPayable,
    totalAmount,
    netPayable,
    amountPaid,
    pendingAmount,
    paymentStatus,
    isFinalized: true,
    isClosed: existing.isClosed === true || existing.status === 'finalized',
    isPaid,
    isPartiallyPaid,
    hasPendingBonus: isPartiallyPaid && bonus > 0,
  };
};

const notifyUserAllAliases = async (companyId, user, payload) => {
  const targetUserId = user.userId || user.StaffId || String(user._id);
  return createAndSendNotification({
    ...payload,
    companyId,
    userId: targetUserId,
  });
};

const finalizeEmployeeRecord = async ({ companyId, user, month, actorId, notes = '', closeMonth = true, sendNotifications = true }) => {
  const existing = await Payroll.findOne({ companyId, userId: user.userId, month });
  if (existing && existing.status === 'finalized') {
    return { payroll: existing, alreadyFinalized: true };
  }

  const companyDoc = await Company.findById(companyId).select('leavePolicy name').lean();
  const { settings, leavePolicy } = await resolvePolicyForMonth(companyId, month, companyDoc);
  const candidateIds = getUserCandidateIds(user);

  const [holidays, attendances, leaves, adjustments, leaveBalance, priorTxs] = await Promise.all([
    Holiday.find({ companyId, date: { $regex: `^${month}` }, description: { $not: /\[EVENT\]/i } }).lean(),
    Attendance.find({ companyId, userId: { $in: candidateIds }, date: { $regex: `^${month}` } }).lean(),
    Leave.find({
      companyId,
      userId: { $in: candidateIds },
      startDate: { $lte: `${month}-31` },
      endDate: { $gte: `${month}-01` },
    }).lean(),
    PayrollAdjustment.find({ companyId, userId: { $in: candidateIds }, month }).lean(),
    computeUserLeaveBalance(companyId, user.userId),
    PaymentTransaction.find({ companyId, userId: { $in: candidateIds }, month, status: 'completed' }).lean(),
  ]);

  const currMonth = getCurrentMonthStr();
  const refDate = month < currMonth ? getPastMonthEndDate(month) : null;

  const calculation = calculateEmployeeMonthlyPayroll({
    user,
    month,
    settings,
    leavePolicy,
    leaveBalance,
    attendances,
    leaves,
    holidays,
    adjustments,
    referenceDate: refDate,
  });

  calculation.snapshotSettings = {
    ...calculation.snapshotSettings,
    leavePolicy,
  };

  const amountPaid = round2(priorTxs.reduce((sum, tx) => sum + (Number(tx.amount) || 0), 0));
  const pendingAmount = Math.max(0, round2(calculation.totalAmount - amountPaid));
  const paymentStatus = pendingAmount <= 0.01 && amountPaid > 0
    ? 'paid'
    : (amountPaid > 0 ? 'partially_paid' : 'unpaid');

  const payslipNumber = existing?.payslipNumber || `PS-${month.replace('-', '')}-${String(user.StaffId || user.userId).slice(-6).toUpperCase()}`;

  const payrollData = {
    ...calculation,
    companyId,
    userId: user.userId,
    month,
    status: 'finalized',
    paymentStatus,
    amountPaid,
    pendingAmount,
    finalizedAt: new Date(),
    finalizedBy: actorId,
    isClosed: Boolean(closeMonth),
    closedAt: closeMonth ? new Date() : undefined,
    closedBy: closeMonth ? actorId : undefined,
    payslipNumber,
    payslipGeneratedAt: new Date(),
    notes: notes || existing?.notes || '',
    $push: {
      auditTrail: {
        action: 'FINALIZED',
        performedBy: actorId,
        timestamp: new Date(),
        details: {
          netPayable: calculation.netPayable,
          totalDeductions: calculation.totalDeductions,
          totalBreakDeduction: calculation.totalBreakDeduction,
          lateDeduction: calculation.lateDeduction,
          overtimeAddition: calculation.hourlyOvertimeAddition,
          pendingAmount,
        },
      },
    },
  };

  const payroll = await Payroll.findOneAndUpdate(
    { companyId, userId: user.userId, month },
    payrollData,
    { new: true, upsert: true }
  );

  emitToCompany('payroll:change', companyId, { action: 'finalized', payrollId: payroll._id, month, userId: user.userId });
  emitToUser(user.userId, 'payroll:change', { action: 'finalized', payrollId: payroll._id, month });

  if (sendNotifications) {
    try {
      await notifyUserAllAliases(companyId, user, {
        id: `notif-fin-${payroll._id}-${Date.now()}`,
        title: pendingAmount > 0 ? 'Payroll Finalized — Salary Pending' : 'Payroll Finalized',
        message: pendingAmount > 0
          ? `Your payroll for ${month} is finalized. Net payable: ₹${calculation.netPayable.toLocaleString('en-IN', { minimumFractionDigits: 2 })} (Pending balance: ₹${pendingAmount.toLocaleString('en-IN', { minimumFractionDigits: 2 })}).`
          : `Your payroll for ${month} has been finalized. Net payable: ₹${calculation.netPayable.toLocaleString('en-IN', { minimumFractionDigits: 2 })}.`,
        type: 'payroll',
        metadata: {
          month,
          payrollId: payroll._id,
          netPayable: calculation.netPayable,
          pendingAmount,
          reason: pendingAmount > 0 ? 'Pending salary recorded for month' : 'Payroll finalized',
        },
      });

      const autoDed = round2(
        calculation.hourlyShortfallDeduction +
        calculation.approvedLeaveDeduction +
        calculation.unapprovedLeaveDeduction +
        calculation.lateDeduction +
        calculation.totalBreakDeduction
      );
      if (autoDed > 0) {
        await notifyUserAllAliases(companyId, user, {
          id: `notif-ded-sum-${payroll._id}-${Date.now()}`,
          title: 'Monthly Salary Deductions Summary',
          message: `Total attendance/leave deductions of ₹${autoDed.toLocaleString('en-IN', { minimumFractionDigits: 2 })} were applied for ${month} (Leave: ₹${round2(calculation.approvedLeaveDeduction + calculation.unapprovedLeaveDeduction)}, Shortfall/Late: ₹${round2(calculation.hourlyShortfallDeduction + calculation.lateDeduction)}, Break Delay: ₹${calculation.totalBreakDeduction}).`,
          type: 'deduction',
          metadata: {
            month,
            amount: autoDed,
            reason: 'Monthly attendance, leave, and break-delay deductions',
          },
        });
      }
    } catch (notifErr) {
      console.warn('Finalize notification error:', notifErr.message);
    }
  }

  return { payroll, alreadyFinalized: false };
};

/**
 * 1. Get Company Payroll Settings (+ merged Leave Policy)
 */
export const getPayrollSettings = async (req, res) => {
  try {
    const companyId = requireCompanyId(req, res, true);
    if (!companyId) {
      return res.status(200).json({
        ...DEFAULT_PAYROLL_SETTINGS,
        leavePolicy: DEFAULT_LEAVE_POLICY,
      });
    }

    let settings = await PayrollSetting.findOne({ companyId }).lean();
    if (!settings) {
      const created = await PayrollSetting.create({
        companyId,
        ...DEFAULT_PAYROLL_SETTINGS,
      });
      settings = created.toObject();
    }

    const company = await Company.findById(companyId).select('leavePolicy').lean();
    const leavePolicy = mergeLeavePolicy(company?.leavePolicy);

    res.status(200).json({
      ...getNormalizedPayrollSettings(settings),
      leavePolicy,
    });
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
};

/**
 * 2. Update Company Payroll Settings (+ snapshot policy history for non-retroactive periods)
 */
export const updatePayrollSettings = async (req, res) => {
  try {
    const companyId = requireCompanyId(req, res);
    if (!companyId) return;

    if (!isCompanyAdmin(req.user)) {
      return res.status(403).json({ message: 'Only company admins or owners can update payroll settings' });
    }

    const {
      checkInTime,
      checkOutTime,
      workingHoursPerDay,
      workingDaysPerWeek,
      breakTime,
      casualBreakTime,
      weeklyOffDays,
      hourlyDeductionPct,
      hourlyOvertimePct,
      approvedLeaveDeductionPct,
      unapprovedLeaveDeductionPct,
      graceMinutes,
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
      leavePolicy,
    } = req.body;

    const updates = {};

    if (checkInTime) updates.checkInTime = String(checkInTime).trim();
    if (checkOutTime) updates.checkOutTime = String(checkOutTime).trim();

    if (workingHoursPerDay !== undefined) {
      const wh = Number(workingHoursPerDay);
      if (isNaN(wh) || wh < 1 || wh > 24) {
        return res.status(400).json({ message: 'Working hours per day must be between 1 and 24' });
      }
      updates.workingHoursPerDay = wh;
    }

    if (workingDaysPerWeek !== undefined) {
      const wd = Number(workingDaysPerWeek);
      if (isNaN(wd) || wd < 1 || wd > 7) {
        return res.status(400).json({ message: 'Working days per week must be between 1 and 7' });
      }
      updates.workingDaysPerWeek = wd;
      if (!weeklyOffDays) {
        updates.weeklyOffDays = getWeeklyOffDays(wd);
      }
    }

    if (breakTime !== undefined) {
      const bt = Number(breakTime);
      if (isNaN(bt) || bt < 0 || bt > 300) {
        return res.status(400).json({ message: 'Lunch break minutes must be between 0 and 300' });
      }
      updates.breakTime = bt;
    }

    if (casualBreakTime !== undefined) {
      const cbt = Number(casualBreakTime);
      if (isNaN(cbt) || cbt < 0 || cbt > 180) {
        return res.status(400).json({ message: 'Casual break minutes must be between 0 and 180' });
      }
      updates.casualBreakTime = cbt;
    }

    if (Array.isArray(weeklyOffDays)) {
      updates.weeklyOffDays = weeklyOffDays.map(Number).filter(n => n >= 0 && n <= 6);
    }

    if (hourlyDeductionPct !== undefined) {
      const hd = Number(hourlyDeductionPct);
      if (isNaN(hd) || hd < 0 || hd > 500) {
        return res.status(400).json({ message: 'Hourly deduction percentage must be between 0% and 500%' });
      }
      updates.hourlyDeductionPct = hd;
    }

    if (hourlyOvertimePct !== undefined) {
      const ho = Number(hourlyOvertimePct);
      if (isNaN(ho) || ho < 0 || ho > 500) {
        return res.status(400).json({ message: 'Hourly overtime percentage must be between 0% and 500%' });
      }
      updates.hourlyOvertimePct = ho;
    }

    if (approvedLeaveDeductionPct !== undefined) {
      const al = Number(approvedLeaveDeductionPct);
      if (isNaN(al) || al < 0 || al > 100) {
        return res.status(400).json({ message: 'Approved leave deduction percentage must be between 0% and 100%' });
      }
      updates.approvedLeaveDeductionPct = al;
    }

    if (unapprovedLeaveDeductionPct !== undefined) {
      const ul = Number(unapprovedLeaveDeductionPct);
      if (isNaN(ul) || ul < 0 || ul > 200) {
        return res.status(400).json({ message: 'Unapproved leave deduction percentage must be between 0% and 200%' });
      }
      updates.unapprovedLeaveDeductionPct = ul;
    }

    if (graceMinutes !== undefined) {
      const gm = Number(graceMinutes);
      if (isNaN(gm) || gm < 0 || gm > 120) {
        return res.status(400).json({ message: 'Grace buffer minutes must be between 0 and 120' });
      }
      updates.graceMinutes = gm;
    }

    if (payrollDivisorType) {
      if (!['scheduled_hours', 'fixed_hours'].includes(payrollDivisorType)) {
        return res.status(400).json({ message: 'Invalid payroll divisor type' });
      }
      updates.payrollDivisorType = payrollDivisorType;
    }

    if (fixedPayrollDivisor !== undefined) {
      const fpd = Number(fixedPayrollDivisor);
      if (isNaN(fpd) || fpd <= 0) {
        return res.status(400).json({ message: 'Fixed payroll divisor must be greater than 0' });
      }
      updates.fixedPayrollDivisor = fpd;
    }

    if (dailyBasisType) {
      if (!['scheduled_days', 'calendar_days'].includes(dailyBasisType)) {
        return res.status(400).json({ message: 'Invalid daily basis type' });
      }
      updates.dailyBasisType = dailyBasisType;
    }

    if (lateDeductionEnabled !== undefined) updates.lateDeductionEnabled = Boolean(lateDeductionEnabled);
    if (lateDeductionMode !== undefined) {
      if (!['fixed_per_late', 'per_minute', 'hourly_rate'].includes(lateDeductionMode)) {
        return res.status(400).json({ message: 'Invalid late deduction mode' });
      }
      updates.lateDeductionMode = lateDeductionMode;
    }
    if (lateDeductionRate !== undefined) {
      const lr = Number(lateDeductionRate);
      if (isNaN(lr) || lr < 0) return res.status(400).json({ message: 'Late deduction rate cannot be negative' });
      updates.lateDeductionRate = lr;
    }
    if (shortfallDeductionEnabled !== undefined) updates.shortfallDeductionEnabled = Boolean(shortfallDeductionEnabled);
    if (overtimeEnabled !== undefined) updates.overtimeEnabled = Boolean(overtimeEnabled);
    if (overtimeMinMinutes !== undefined) {
      const om = Number(overtimeMinMinutes);
      if (isNaN(om) || om < 0 || om > 480) return res.status(400).json({ message: 'Invalid minimum overtime minutes' });
      updates.overtimeMinMinutes = om;
    }
    if (breakDelayDeductionEnabled !== undefined) updates.breakDelayDeductionEnabled = Boolean(breakDelayDeductionEnabled);
    if (breakDelayRuleType !== undefined) {
      if (!['per_interval_flat', 'salary_minute_rate'].includes(breakDelayRuleType)) {
        return res.status(400).json({ message: 'Invalid break delay rule type' });
      }
      updates.breakDelayRuleType = breakDelayRuleType;
    }
    if (breakDelayIntervalMinutes !== undefined) {
      const bm = Number(breakDelayIntervalMinutes);
      if (isNaN(bm) || bm < 1 || bm > 120) return res.status(400).json({ message: 'Break delay interval must be between 1 and 120 minutes' });
      updates.breakDelayIntervalMinutes = bm;
    }
    if (breakDelayIntervalAmount !== undefined) {
      const ba = Number(breakDelayIntervalAmount);
      if (isNaN(ba) || ba < 0) return res.status(400).json({ message: 'Break delay deduction amount cannot be negative' });
      updates.breakDelayIntervalAmount = ba;
    }

    updates.updatedBy = req.user.userId;

    const existingSetting = await PayrollSetting.findOne({ companyId }).lean();
    updates.policyVersion = (Number(existingSetting?.policyVersion) || 1) + (existingSetting ? 1 : 0);

    const settings = await PayrollSetting.findOneAndUpdate(
      { companyId },
      { $set: updates },
      { new: true, upsert: true }
    ).lean();

    let updatedCompanyLeavePolicy = null;
    if (leavePolicy && typeof leavePolicy === 'object') {
      const compUpdate = {};
      if (leavePolicy.casualLeave) compUpdate['leavePolicy.casualLeave'] = leavePolicy.casualLeave;
      if (leavePolicy.sickLeave) compUpdate['leavePolicy.sickLeave'] = leavePolicy.sickLeave;
      if (leavePolicy.earnedLeave) compUpdate['leavePolicy.earnedLeave'] = leavePolicy.earnedLeave;
      if (leavePolicy.unpaidLeave) compUpdate['leavePolicy.unpaidLeave'] = leavePolicy.unpaidLeave;
      const comp = await Company.findByIdAndUpdate(companyId, { $set: compUpdate }, { new: true }).lean();
      updatedCompanyLeavePolicy = mergeLeavePolicy(comp?.leavePolicy);
    } else {
      const comp = await Company.findById(companyId).select('leavePolicy').lean();
      updatedCompanyLeavePolicy = mergeLeavePolicy(comp?.leavePolicy);
    }

    await PayrollPolicyHistory.create({
      companyId,
      policyVersion: settings.policyVersion || 1,
      effectiveFrom: getTodayIsoStr(),
      settingsSnapshot: settings,
      leavePolicySnapshot: updatedCompanyLeavePolicy,
      updatedBy: req.user.userId,
    });

    const fullPayload = { ...DEFAULT_PAYROLL_SETTINGS, ...settings, leavePolicy: updatedCompanyLeavePolicy };
    emitToCompany('payroll:settings_updated', companyId, fullPayload);
    emitToCompany('payroll:change', companyId, { action: 'settings_updated' });

    res.status(200).json({ message: 'Payroll settings updated successfully', settings: fullPayload });
  } catch (error) {
    res.status(400).json({ message: error.message });
  }
};

/**
 * 3. Get Monthly Payroll Summary for All Company Employees
 */
export const getPayrollSummary = async (req, res) => {
  try {
    const companyId = requireCompanyId(req, res, true);
    const month = (req.query.month || getCurrentMonthStr()).trim();

    if (!companyId) {
      return res.status(200).json({
        month,
        summary: {
          totalEmployees: 0,
          totalAmountSent: 0,
          totalAmountToPay: 0,
          totalPreviousPending: 0,
          totalBaseSalary: 0,
          totalDeductions: 0,
          totalOvertimeAdditions: 0,
          totalBonuses: 0,
          totalManualDeductions: 0,
          totalNetPayable: 0,
          pendingFinalizationCount: 0,
          pendingPaymentCount: 0,
          paymentsCompletedCount: 0,
        },
        items: [],
      });
    }

    if (!isCompanyAdmin(req.user)) {
      return res.status(403).json({ message: 'Access denied' });
    }

    const search = String(req.query.search || '').trim().toLowerCase();
    const department = String(req.query.department || 'all').trim();
    const statusTab = String(req.query.statusTab || 'all').trim();
    const includeInactive = String(req.query.includeInactive || '').toLowerCase() === 'true';

    const companyDoc = await Company.findById(companyId).select('leavePolicy').lean();
    const { settings, leavePolicy } = await resolvePolicyForMonth(companyId, month, companyDoc);

    const userFilter = {
      companyId,
      role: { $in: ['staff', 'intern', 'freelancer', 'admin'] },
      ...(includeInactive ? {} : { status: { $ne: 'inactive' } }),
    };

    const users = await User.find(userFilter)
      .select('userId StaffId username name role department designation salary status')
      .lean();

    const [existingPayrolls, priorPendingPayrolls, holidays, attendances, leaves, adjustments, completedTransactions] = await Promise.all([
      Payroll.find({ companyId, month }).lean(),
      Payroll.find({
        companyId,
        month: { $lt: month },
        pendingAmount: { $gt: 0.01 },
      }).select('userId month pendingAmount netPayable amountPaid paymentStatus').lean(),
      Holiday.find({ companyId, date: { $regex: `^${month}` }, description: { $not: /\[EVENT\]/i } }).lean(),
      Attendance.find({ companyId, date: { $regex: `^${month}` } }).lean(),
      Leave.find({
        companyId,
        startDate: { $lte: `${month}-31` },
        endDate: { $gte: `${month}-01` },
      }).lean(),
      PayrollAdjustment.find({ companyId, month }).lean(),
      PaymentTransaction.find({ companyId, month, status: 'completed' }).lean(),
    ]);

    const payrollMap = new Map();
    existingPayrolls.forEach(p => payrollMap.set(String(p.userId), p));

    const previousPendingMap = new Map();
    priorPendingPayrolls.forEach(p => {
      const uid = String(p.userId);
      if (!previousPendingMap.has(uid)) previousPendingMap.set(uid, []);
      previousPendingMap.get(uid).push(p);
    });

    const attendanceByUser = new Map();
    attendances.forEach(a => {
      const uid = String(a.userId || '').trim();
      if (!uid) return;
      for (const k of [uid, uid.toLowerCase()]) {
        if (!attendanceByUser.has(k)) attendanceByUser.set(k, []);
        attendanceByUser.get(k).push(a);
      }
    });

    const leavesByUser = new Map();
    leaves.forEach(l => {
      const uid = String(l.userId || '').trim();
      if (!uid) return;
      for (const k of [uid, uid.toLowerCase()]) {
        if (!leavesByUser.has(k)) leavesByUser.set(k, []);
        leavesByUser.get(k).push(l);
      }
    });

    const currMonth = getCurrentMonthStr();
    const refDate = month < currMonth ? getPastMonthEndDate(month) : null;

    const items = [];
    let totalBaseSalary = 0;
    let totalDeductions = 0;
    let totalOvertimeAdditions = 0;
    let totalBonuses = 0;
    let totalManualDeductions = 0;
    let totalNetPayable = 0;
    let totalAmountSent = 0;
    let totalAmountToPay = 0;
    let totalPreviousPending = 0;
    let pendingFinalizationCount = 0;
    let pendingPaymentCount = 0;
    let paymentsCompletedCount = 0;

    for (const u of users) {
      const uid = u.userId || u.StaffId || String(u._id);
      const candidateIds = getUserCandidateIds(u);
      const existing = candidateIds.map(id => payrollMap.get(id)).find(Boolean) || null;

      const userAdjustments = adjustments.filter(a => candidateIds.includes(String(a.userId)));
      const userBonus = round2(userAdjustments.filter(a => a.type === 'bonus').reduce((sum, a) => sum + Number(a.amount || 0), 0));
      const userManualDeduction = round2(userAdjustments.filter(a => a.type === 'deduction').reduce((sum, a) => sum + Number(a.amount || 0), 0));

      const prevPendingList = [];
      const seenPrevMonths = new Set();
      candidateIds.forEach(id => {
        (previousPendingMap.get(id) || []).forEach(p => {
          if (!seenPrevMonths.has(p.month)) {
            seenPrevMonths.add(p.month);
            prevPendingList.push(p);
          }
        });
      });
      const previousPendingTotal = round2(prevPendingList.reduce((s, p) => s + (Number(p.pendingAmount) || 0), 0));

      let record;
      if (existing && existing.status === 'finalized') {
        record = buildFinalizedRecordView(existing, u, userAdjustments, completedTransactions);
      } else {
        const userAttendances = [];
        const userLeaves = [];
        const seenAtt = new Set();
        const seenLeave = new Set();
        candidateIds.forEach(rawId => {
          for (const key of [rawId, rawId.toLowerCase()]) {
            (attendanceByUser.get(key) || []).forEach(a => {
              const ak = String(a._id || a.id);
              if (!seenAtt.has(ak)) {
                seenAtt.add(ak);
                userAttendances.push(a);
              }
            });
            (leavesByUser.get(key) || []).forEach(l => {
              const lk = String(l._id || l.id);
              if (!seenLeave.has(lk)) {
                seenLeave.add(lk);
                userLeaves.push(l);
              }
            });
          }
        });

        const leaveBalance = await computeUserLeaveBalance(companyId, u.userId || uid);
        const calculated = calculateEmployeeMonthlyPayroll({
          user: u,
          month,
          settings,
          leavePolicy,
          leaveBalance,
          attendances: userAttendances,
          leaves: userLeaves,
          holidays,
          adjustments: userAdjustments,
          referenceDate: refDate,
        });

        const amountPaid = sumTransactionsForPayroll(completedTransactions, existing?._id, candidateIds);
        const pendingAmount = Math.max(0, round2(calculated.totalAmount - amountPaid));
        const isPaid = pendingAmount <= 0.01 && amountPaid > 0;
        const isPartiallyPaid = amountPaid > 0 && pendingAmount > 0.01;

        record = {
          ...calculated,
          _id: existing?._id,
          id: existing?.id,
          companyId,
          userId: uid,
          StaffId: u.StaffId || uid,
          name: u.name || u.username || uid,
          designation: u.designation || 'Staff',
          department: u.department || 'General',
          bonus: userBonus,
          manualDeduction: userManualDeduction,
          totalAmount: calculated.totalAmount,
          amountPaid,
          pendingAmount,
          status: 'draft',
          paymentStatus: isPaid ? 'paid' : (isPartiallyPaid ? 'partially_paid' : 'unpaid'),
          isFinalized: false,
          isClosed: false,
          isPaid,
          isPartiallyPaid,
          hasPendingBonus: isPartiallyPaid && userBonus > 0,
        };
      }

      record.previousPendingTotal = previousPendingTotal;
      record.previousPendingMonthsCount = prevPendingList.length;
      record.previousPendingMonths = prevPendingList;

      totalBaseSalary = round2(totalBaseSalary + record.baseSalary);
      totalDeductions = round2(totalDeductions + record.totalDeductions);
      totalOvertimeAdditions = round2(totalOvertimeAdditions + (record.hourlyOvertimeAddition || 0));
      totalBonuses = round2(totalBonuses + (record.bonus || 0));
      totalManualDeductions = round2(totalManualDeductions + (record.manualDeduction || 0));
      totalNetPayable = round2(totalNetPayable + record.netPayable);
      totalAmountSent = round2(totalAmountSent + (record.amountPaid || 0));
      totalAmountToPay = round2(totalAmountToPay + (record.pendingAmount !== undefined ? record.pendingAmount : (record.isPaid ? 0 : record.totalAmount)));
      totalPreviousPending = round2(totalPreviousPending + previousPendingTotal);

      if (record.isPaid) {
        paymentsCompletedCount++;
      } else if (record.isPartiallyPaid) {
        pendingPaymentCount++;
      } else if (record.status === 'draft') {
        pendingFinalizationCount++;
      } else {
        pendingPaymentCount++;
      }

      items.push(record);
    }

    let filtered = items;
    if (statusTab === 'pending') {
      filtered = filtered.filter(i => !i.isPaid || i.isPartiallyPaid || (i.previousPendingTotal || 0) > 0);
    } else if (statusTab === 'processed') {
      filtered = filtered.filter(i => i.isPaid || i.isPartiallyPaid);
    }

    if (department !== 'all') {
      filtered = filtered.filter(i => (i.department || '').toLowerCase() === department.toLowerCase());
    }

    if (search) {
      filtered = filtered.filter(i =>
        (i.name || '').toLowerCase().includes(search) ||
        (i.userId || '').toLowerCase().includes(search) ||
        (i.StaffId || '').toLowerCase().includes(search)
      );
    }

    res.status(200).json({
      month,
      summary: {
        totalEmployees: users.length,
        totalAmountSent,
        totalAmountToPay,
        totalPreviousPending,
        totalBaseSalary,
        totalDeductions,
        totalOvertimeAdditions,
        totalBonuses,
        totalManualDeductions,
        totalNetPayable,
        pendingFinalizationCount,
        pendingPaymentCount,
        paymentsCompletedCount,
      },
      settings: { ...settings, leavePolicy },
      items: filtered,
    });
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
};

/**
 * 4. Get Detailed Employee Payroll Preview (Breakdown + Transactions + Prior Pending)
 */
export const getEmployeePayrollPreview = async (req, res) => {
  try {
    const companyId = requireCompanyId(req, res, true);
    if (!companyId) return res.status(200).json({});

    const { userId, month } = req.query;
    if (!userId || !month) {
      return res.status(400).json({ message: 'userId and month are required' });
    }

    if (!isCompanyAdmin(req.user) && req.user.userId !== userId) {
      return res.status(403).json({ message: 'Access denied' });
    }

    const user = await findCompanyUser(companyId, userId);
    if (!user) {
      return res.status(404).json({ message: 'Employee not found in this company' });
    }

    const candidateIds = getUserCandidateIds(user);
    const [existing, adjustments, transactions, priorPending] = await Promise.all([
      Payroll.findOne({ companyId, userId: { $in: candidateIds }, month }).lean(),
      PayrollAdjustment.find({ companyId, userId: { $in: candidateIds }, month }).sort({ createdAt: -1 }).lean(),
      PaymentTransaction.find({ companyId, userId: { $in: candidateIds }, month, status: 'completed' }).sort({ paidAt: -1 }).lean(),
      Payroll.find({
        companyId,
        userId: { $in: candidateIds },
        month: { $ne: month },
        pendingAmount: { $gt: 0.01 },
      }).select('id _id month netPayable amountPaid pendingAmount paymentStatus').sort({ month: -1 }).lean(),
    ]);

    if (existing && existing.status === 'finalized') {
      const view = buildFinalizedRecordView(existing, user, adjustments, transactions);
      return res.status(200).json({
        ...view,
        adjustments,
        transactions,
        previousPendingMonths: priorPending,
        totalPreviousPending: round2(priorPending.reduce((s, p) => s + (Number(p.pendingAmount) || 0), 0)),
      });
    }

    const companyDoc = await Company.findById(companyId).select('leavePolicy').lean();
    const { settings, leavePolicy } = await resolvePolicyForMonth(companyId, month, companyDoc);

    const [holidays, attendances, leaves, leaveBalance] = await Promise.all([
      Holiday.find({ companyId, date: { $regex: `^${month}` }, description: { $not: /\[EVENT\]/i } }).lean(),
      Attendance.find({ companyId, userId: { $in: candidateIds }, date: { $regex: `^${month}` } }).lean(),
      Leave.find({
        companyId,
        userId: { $in: candidateIds },
        startDate: { $lte: `${month}-31` },
        endDate: { $gte: `${month}-01` },
      }).lean(),
      computeUserLeaveBalance(companyId, user.userId),
    ]);

    const currMonth = getCurrentMonthStr();
    const refDate = month < currMonth ? getPastMonthEndDate(month) : null;

    const result = calculateEmployeeMonthlyPayroll({
      user,
      month,
      settings,
      leavePolicy,
      leaveBalance,
      attendances,
      leaves,
      holidays,
      adjustments,
      referenceDate: refDate,
    });

    const amountPaid = sumTransactionsForPayroll(transactions, existing?._id, candidateIds);
    const pendingAmount = Math.max(0, round2(result.totalAmount - amountPaid));
    const isPaid = pendingAmount <= 0.01 && (amountPaid > 0 || existing?.paymentStatus === 'paid');
    const isPartiallyPaid = amountPaid > 0 && pendingAmount > 0.01;

    res.status(200).json({
      ...result,
      _id: existing?._id,
      id: existing?.id,
      amountPaid,
      pendingAmount,
      status: existing?.status || 'draft',
      paymentStatus: isPaid ? 'paid' : (isPartiallyPaid ? 'partially_paid' : (existing?.paymentStatus || 'unpaid')),
      isFinalized: false,
      isClosed: false,
      isPaid,
      isPartiallyPaid,
      hasPendingBonus: isPartiallyPaid && result.bonus > 0,
      adjustments,
      transactions,
      previousPendingMonths: priorPending,
      totalPreviousPending: round2(priorPending.reduce((s, p) => s + (Number(p.pendingAmount) || 0), 0)),
    });
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
};

/**
 * 5. Finalize Single Employee Payroll
 */
export const finalizePayroll = async (req, res) => {
  try {
    const companyId = requireCompanyId(req, res);
    if (!companyId) return;

    if (!isCompanyAdmin(req.user)) {
      return res.status(403).json({ message: 'Only company admins or owners can finalize payroll' });
    }

    const { userId, month, notes } = req.body;
    if (!userId || !month) {
      return res.status(400).json({ message: 'userId and month are required' });
    }

    const user = await findCompanyUser(companyId, userId);
    if (!user) {
      return res.status(404).json({ message: 'Employee not found in this company' });
    }

    const { payroll, alreadyFinalized } = await finalizeEmployeeRecord({
      companyId,
      user,
      month: String(month).trim(),
      actorId: req.user.userId,
      notes: notes || '',
      closeMonth: true,
      sendNotifications: true,
    });

    if (alreadyFinalized) {
      return res.status(400).json({ message: 'Payroll for this employee and month has already been finalized' });
    }

    res.status(200).json({
      message: 'Payroll finalized successfully with immutable snapshot',
      payroll,
    });
  } catch (error) {
    res.status(400).json({ message: error.message });
  }
};

/**
 * 5b. Finalize & Close Whole Company Month
 */
export const finalizeMonthPayroll = async (req, res) => {
  try {
    const companyId = requireCompanyId(req, res);
    if (!companyId) return;

    if (!isCompanyAdmin(req.user)) {
      return res.status(403).json({ message: 'Only company admins or owners can close payroll month' });
    }

    const month = String(req.body?.month || getCurrentMonthStr()).trim();
    const users = await User.find({
      companyId,
      role: { $in: ['staff', 'intern', 'freelancer', 'admin'] },
      status: { $ne: 'inactive' },
    }).lean();

    let finalizedCount = 0;
    let skippedCount = 0;
    const finalizedIds = [];

    for (const u of users) {
      const { payroll, alreadyFinalized } = await finalizeEmployeeRecord({
        companyId,
        user: u,
        month,
        actorId: req.user.userId,
        notes: req.body?.notes || 'Monthly payroll cycle closed',
        closeMonth: true,
        sendNotifications: true,
      });
      if (alreadyFinalized) {
        skippedCount++;
      } else {
        finalizedCount++;
        finalizedIds.push(payroll._id);
      }
    }

    emitToCompany('payroll:change', companyId, { action: 'month_finalized', month, finalizedCount });

    res.status(200).json({
      message: `Closed payroll for ${month}: ${finalizedCount} finalized, ${skippedCount} already finalized.`,
      month,
      finalizedCount,
      skippedCount,
      finalizedIds,
    });
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
};

/**
 * Internal helper to settle one payroll document with partial/full payment
 */
const settleSinglePayrollPayment = async ({
  companyId,
  payroll,
  user,
  amount,
  paymentMethod = 'bank_transfer',
  referenceId,
  batchId = undefined,
  idempotencyKey = undefined,
  notes = '',
  payoutType = 'salary',
  isBonusPayment = false,
  actor,
}) => {
  const existingRefTx = await PaymentTransaction.findOne({
    companyId,
    referenceId: String(referenceId).trim(),
  }).lean();
  if (existingRefTx) {
    const err = new Error('A payment transaction with this reference ID already exists for this company');
    err.statusCode = 409;
    throw err;
  }

  if (idempotencyKey) {
    const existingIdem = await PaymentTransaction.findOne({
      companyId,
      idempotencyKey: String(idempotencyKey).trim(),
    }).lean();
    if (existingIdem) {
      return { payroll, transaction: existingIdem, idempotentHit: true };
    }
  }

  const existingTxs = await PaymentTransaction.find({
    payrollId: payroll._id,
    status: 'completed',
  }).lean();

  let priorPaid = round2(existingTxs.reduce((sum, t) => sum + (Number(t.amount) || 0), 0));
  if (priorPaid === 0 && payroll.paymentStatus === 'paid') {
    priorPaid = payroll.amountPaid > 0 ? payroll.amountPaid : (payroll.totalAmount || payroll.netPayable || 0);
  }

  const currentTotal = payroll.totalAmount !== undefined && payroll.totalAmount !== null
    ? Number(payroll.totalAmount)
    : Number(payroll.netPayable || 0);
  const remainingToPay = Math.max(0, round2(currentTotal - priorPaid));

  if (remainingToPay <= 0.01) {
    const err = new Error(`Salary for ${payroll.month} has already been fully paid`);
    err.statusCode = 400;
    throw err;
  }

  let payoutAmount = amount !== undefined && amount !== null && amount !== '' ? Number(amount) : remainingToPay;
  if (isNaN(payoutAmount) || payoutAmount <= 0) {
    const err = new Error('Payment amount must be greater than zero');
    err.statusCode = 400;
    throw err;
  }
  payoutAmount = round2(payoutAmount);

  if (payoutAmount > remainingToPay + 0.01) {
    const err = new Error(`Payment amount (₹${payoutAmount}) exceeds remaining payable balance (₹${remainingToPay}) for ${payroll.month}`);
    err.statusCode = 400;
    throw err;
  }

  const isBonus = Boolean(isBonusPayment === true || payoutType === 'bonus');
  const newTotalPaid = round2(priorPaid + payoutAmount);
  const pendingAmount = Math.max(0, round2(currentTotal - newTotalPaid));
  const isNowFullyPaid = pendingAmount <= 0.01;
  const newPaymentStatus = isNowFullyPaid ? 'paid' : 'partially_paid';

  const transaction = await PaymentTransaction.create({
    payrollId: payroll._id,
    companyId,
    userId: payroll.userId,
    month: payroll.month,
    amount: payoutAmount,
    type: isBonus ? 'bonus' : 'salary',
    paymentMethod: paymentMethod || 'bank_transfer',
    referenceId: String(referenceId).trim(),
    batchId,
    idempotencyKey: idempotencyKey ? String(idempotencyKey).trim() : undefined,
    status: 'completed',
    paidAt: new Date(),
    processedBy: actor.userId,
    processedByName: actor.name || actor.username || actor.userId,
    notes: notes || (isBonus ? 'Bonus payout' : (isNowFullyPaid ? 'Full salary settlement' : 'Partial salary payout')),
  });

  payroll.paymentStatus = newPaymentStatus;
  payroll.paidAt = new Date();
  payroll.amountPaid = newTotalPaid;
  payroll.pendingAmount = pendingAmount;
  payroll.paymentId = transaction.id;
  if (notes) payroll.notes = notes;

  payroll.auditTrail.push({
    action: isBonus ? 'BONUS_PAYMENT_PROCESSED' : (isNowFullyPaid ? 'PAYMENT_PROCESSED' : 'PARTIAL_PAYMENT_PROCESSED'),
    performedBy: actor.userId,
    timestamp: new Date(),
    details: {
      referenceId,
      batchId,
      paymentMethod: paymentMethod || 'bank_transfer',
      amount: payoutAmount,
      priorPaid,
      newTotalPaid,
      pendingAmount,
      type: isBonus ? 'bonus' : 'salary',
    },
  });

  await payroll.save();

  try {
    const title = isBonus
      ? 'Payment Received — Bonus'
      : (isNowFullyPaid ? 'Salary Paid in Full' : 'Partial Salary Payment Received');
    const message = isBonus
      ? `Your bonus payment of ₹${payoutAmount.toLocaleString('en-IN', { minimumFractionDigits: 2 })} for ${payroll.month} has been processed (Ref: ${referenceId}).`
      : (isNowFullyPaid
        ? `Your salary payment of ₹${payoutAmount.toLocaleString('en-IN', { minimumFractionDigits: 2 })} for ${payroll.month} has been paid in full via ${(paymentMethod || 'bank transfer').replace('_', ' ')} (Ref: ${referenceId}). Remaining balance: ₹0.00.`
        : `A partial salary payment of ₹${payoutAmount.toLocaleString('en-IN', { minimumFractionDigits: 2 })} for ${payroll.month} has been processed via ${(paymentMethod || 'bank transfer').replace('_', ' ')} (Ref: ${referenceId}). Remaining pending balance: ₹${pendingAmount.toLocaleString('en-IN', { minimumFractionDigits: 2 })}.`);

    await notifyUserAllAliases(companyId, user || { userId: payroll.userId }, {
      id: `notif-payment-${transaction.id}`,
      title,
      message,
      type: 'payment',
      metadata: {
        month: payroll.month,
        amount: payoutAmount,
        remainingPending: pendingAmount,
        transactionId: transaction.id,
        referenceId,
        paymentStatus: newPaymentStatus,
        type: isBonus ? 'bonus' : 'salary',
      },
    });
  } catch (notifErr) {
    console.warn('Failed to send payment notification:', notifErr.message);
  }

  emitToCompany('payroll:change', companyId, {
    action: 'paid',
    payrollId: payroll._id,
    month: payroll.month,
    transactionId: transaction.id,
    isBonus,
    newPaymentStatus,
    pendingAmount,
  });
  emitToUser(payroll.userId, 'payroll:change', {
    action: 'paid',
    payrollId: payroll._id,
    month: payroll.month,
    transactionId: transaction.id,
    isBonus,
    newPaymentStatus,
    pendingAmount,
  });

  return { payroll, transaction, isBonus, isNowFullyPaid, idempotentHit: false };
};

/**
 * 6. Process Payment (supports partial/full payout at any time, auto-finalizing draft if needed)
 */
export const processPayment = async (req, res) => {
  try {
    const companyId = requireCompanyId(req, res);
    if (!companyId) return;

    if (!isCompanyAdmin(req.user)) {
      return res.status(403).json({ message: 'Only company admins or owners can process payments' });
    }

    const {
      payrollId,
      userId,
      month,
      paymentMethod,
      referenceId,
      idempotencyKey,
      notes,
      amount,
      isBonusPayment,
      payoutType,
      autoFinalize = true,
    } = req.body;

    if (!referenceId) {
      return res.status(400).json({ message: 'Payment reference or transaction ID is required' });
    }

    let payroll = null;
    let empUser = null;

    if (payrollId && mongoose.isValidObjectId(payrollId)) {
      payroll = await Payroll.findOne({ _id: payrollId, companyId });
      if (payroll) empUser = await findCompanyUser(companyId, payroll.userId);
    } else if (userId && month) {
      empUser = await findCompanyUser(companyId, userId);
      const candidateIds = empUser ? getUserCandidateIds(empUser) : [userId];
      payroll = await Payroll.findOne({ companyId, userId: { $in: candidateIds }, month });
    } else {
      return res.status(400).json({ message: 'payrollId or (userId and month) required' });
    }

    if ((!payroll || payroll.status !== 'finalized') && autoFinalize && empUser && (month || payroll?.month)) {
      const targetMonth = String(month || payroll.month).trim();
      const finRes = await finalizeEmployeeRecord({
        companyId,
        user: empUser,
        month: targetMonth,
        actorId: req.user.userId,
        notes: 'Auto-finalized on salary disbursement',
        closeMonth: true,
        sendNotifications: false,
      });
      payroll = finRes.payroll;
    }

    if (!payroll) {
      return res.status(404).json({ message: 'Payroll record not found. Please finalize payroll first.' });
    }

    if (payroll.status !== 'finalized') {
      return res.status(400).json({ message: 'Payroll must be finalized before processing payment' });
    }

    const result = await settleSinglePayrollPayment({
      companyId,
      payroll,
      user: empUser,
      amount,
      paymentMethod,
      referenceId,
      idempotencyKey,
      notes,
      payoutType,
      isBonusPayment,
      actor: req.user,
    });

    res.status(200).json({
      message: result.idempotentHit
        ? 'Payment already recorded'
        : `${result.isBonus ? 'Bonus' : (result.isNowFullyPaid ? 'Full salary' : 'Partial salary')} payment of ₹${result.transaction.amount.toLocaleString('en-IN')} processed successfully`,
      payroll: result.payroll,
      transaction: result.transaction,
    });
  } catch (error) {
    res.status(error.statusCode || 400).json({ message: error.message });
  }
};

/**
 * 6b. Pay Multiple Pending Months Together (Independent per-month ledger & transactions linked by batchId)
 */
export const processBulkPayment = async (req, res) => {
  try {
    const companyId = requireCompanyId(req, res);
    if (!companyId) return;

    if (!isCompanyAdmin(req.user)) {
      return res.status(403).json({ message: 'Only company admins or owners can process bulk payments' });
    }

    const { userId, items, paymentMethod = 'bank_transfer', referenceId, notes } = req.body;
    if (!referenceId || !Array.isArray(items) || items.length === 0) {
      return res.status(400).json({ message: 'referenceId and non-empty items array are required' });
    }

    const empUser = userId ? await findCompanyUser(companyId, userId) : null;
    const batchId = `BATCH-${Date.now()}-${Math.random().toString(36).slice(2, 7).toUpperCase()}`;
    const results = [];
    const errors = [];

    for (let i = 0; i < items.length; i++) {
      const entry = items[i];
      try {
        let payroll = null;
        let targetUser = empUser;
        if (entry.payrollId && mongoose.isValidObjectId(entry.payrollId)) {
          payroll = await Payroll.findOne({ _id: entry.payrollId, companyId });
          if (payroll && !targetUser) targetUser = await findCompanyUser(companyId, payroll.userId);
        } else if ((entry.userId || userId) && entry.month) {
          targetUser = targetUser || await findCompanyUser(companyId, entry.userId || userId);
          const candidateIds = targetUser ? getUserCandidateIds(targetUser) : [entry.userId || userId];
          payroll = await Payroll.findOne({ companyId, userId: { $in: candidateIds }, month: entry.month });
        }

        if ((!payroll || payroll.status !== 'finalized') && targetUser && (entry.month || payroll?.month)) {
          const finRes = await finalizeEmployeeRecord({
            companyId,
            user: targetUser,
            month: String(entry.month || payroll.month).trim(),
            actorId: req.user.userId,
            notes: 'Auto-finalized on bulk salary payment',
            closeMonth: true,
            sendNotifications: false,
          });
          payroll = finRes.payroll;
        }

        if (!payroll) {
          errors.push({ item: entry, message: 'Payroll record not found' });
          continue;
        }

        const itemRef = items.length === 1 ? String(referenceId).trim() : `${String(referenceId).trim()}-${payroll.month}-${i + 1}`;
        const settled = await settleSinglePayrollPayment({
          companyId,
          payroll,
          user: targetUser,
          amount: entry.amount,
          paymentMethod,
          referenceId: itemRef,
          batchId,
          notes: notes || `Batch settlement (${payroll.month})`,
          payoutType: entry.payoutType || 'salary',
          actor: req.user,
        });
        results.push({ month: payroll.month, transaction: settled.transaction, pendingAmount: settled.payroll.pendingAmount });
      } catch (itemErr) {
        errors.push({ item: entry, message: itemErr.message });
      }
    }

    if (results.length === 0) {
      return res.status(400).json({ message: errors[0]?.message || 'No payments processed', errors });
    }

    const totalDisbursed = round2(results.reduce((s, r) => s + (Number(r.transaction.amount) || 0), 0));
    res.status(200).json({
      message: `Processed ${results.length} monthly payment(s) totaling ₹${totalDisbursed.toLocaleString('en-IN')}`,
      batchId,
      totalDisbursed,
      results,
      errors,
    });
  } catch (error) {
    res.status(400).json({ message: error.message });
  }
};

/**
 * 6c. Get All Pending Salaries Across Months (Company-wide for admin, self-only for employee)
 */
export const getPendingPayrolls = async (req, res) => {
  try {
    const companyId = requireCompanyId(req, res, true);
    if (!companyId) return res.status(200).json({ pending: [], totalPending: 0 });

    const filter = {
      companyId,
      pendingAmount: { $gt: 0.01 },
    };

    if (!isCompanyAdmin(req.user)) {
      const caller = await findCompanyUser(companyId, req.user.userId);
      const ids = caller ? getUserCandidateIds(caller) : [req.user.userId];
      filter.userId = { $in: ids };
    } else if (req.query.userId) {
      const target = await findCompanyUser(companyId, req.query.userId);
      const ids = target ? getUserCandidateIds(target) : [String(req.query.userId)];
      filter.userId = { $in: ids };
    }

    if (req.query.beforeMonth) {
      filter.month = { $lt: String(req.query.beforeMonth).trim() };
    }

    const records = await Payroll.find(filter)
      .select('id _id userId month baseSalary earnedSalary netPayable totalAmount amountPaid pendingAmount paymentStatus status finalizedAt')
      .sort({ month: -1 })
      .lean();

    const includeInactive = String(req.query.includeInactive || '').toLowerCase() === 'true';
    const users = await User.find({
      companyId,
      role: { $in: ['staff', 'intern', 'freelancer', 'admin'] },
      ...(includeInactive ? {} : { status: { $ne: 'inactive' } }),
    })
      .select('userId StaffId name username department designation status')
      .lean();
    const userMap = new Map();
    users.forEach(u => {
      for (const id of getUserCandidateIds(u)) {
        userMap.set(id, u);
      }
    });

    const visibleRecords = includeInactive
      ? records
      : records.filter(r => userMap.has(String(r.userId)));

    const enriched = visibleRecords.map(r => {
      const u = userMap.get(String(r.userId));
      return {
        ...r,
        employeeName: u?.name || u?.username || r.userId,
        staffId: u?.StaffId || r.userId,
        department: u?.department || 'General',
        designation: u?.designation || 'Staff',
      };
    });

    const totalPending = round2(enriched.reduce((s, r) => s + (Number(r.pendingAmount) || 0), 0));
    res.status(200).json({ pending: enriched, totalPending });
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
};

/**
 * 7. Get Recent Transactions
 */
export const getRecentTransactions = async (req, res) => {
  try {
    const companyId = requireCompanyId(req, res, true);
    if (!companyId) {
      return res.status(200).json({ transactions: [], total: 0, page: 1, totalPages: 1 });
    }

    const filter = { companyId };

    if (!isCompanyAdmin(req.user)) {
      const u = await findCompanyUser(companyId, req.user.userId);
      const possibleIds = new Set([req.user.userId]);
      if (req.user.StaffId) possibleIds.add(req.user.StaffId);
      if (req.user.id) possibleIds.add(String(req.user.id));
      if (u) getUserCandidateIds(u).forEach(id => possibleIds.add(id));
      filter.userId = { $in: Array.from(possibleIds) };
    } else if (req.query.userId) {
      const target = await findCompanyUser(companyId, req.query.userId);
      const ids = target ? getUserCandidateIds(target) : [String(req.query.userId)];
      filter.userId = { $in: ids };
    }

    const { month, year, search, page = 1, limit = 20 } = req.query;

    if (month && month !== 'all') {
      filter.month = month;
    } else if (year && year !== 'all') {
      filter.month = new RegExp(`^${year}-`);
    }

    const skip = (Math.max(1, Number(page)) - 1) * Number(limit);
    const transactions = await PaymentTransaction.find(filter)
      .sort({ paidAt: -1 })
      .skip(skip)
      .limit(Number(limit))
      .lean();

    const totalCount = await PaymentTransaction.countDocuments(filter);

    const userIds = [...new Set(transactions.map(t => t.userId))];
    const users = await User.find({ companyId, userId: { $in: userIds } }).select('userId StaffId name username department').lean();
    const userMap = new Map();
    users.forEach(u => userMap.set(u.userId, u));

    const enriched = transactions.map(t => {
      const u = userMap.get(t.userId);
      return {
        ...t,
        employeeName: u?.name || u?.username || t.userId,
        staffId: u?.StaffId || t.userId,
        department: u?.department || 'General',
      };
    });

    let result = enriched;
    if (search) {
      const q = String(search).toLowerCase();
      result = result.filter(t =>
        (t.employeeName || '').toLowerCase().includes(q) ||
        (t.staffId || '').toLowerCase().includes(q) ||
        (t.referenceId || '').toLowerCase().includes(q)
      );
    }

    res.status(200).json({
      transactions: result,
      totalCount,
      page: Number(page),
      totalPages: Math.ceil(totalCount / Number(limit)) || 1,
    });
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
};

/**
 * 8. Employee-Side Payment & Payroll Records (Read-only, strictly self-scoped)
 */
export const getEmployeeMyPayroll = async (req, res) => {
  try {
    const companyId = requireCompanyId(req, res, true);
    if (!companyId) {
      return res.status(200).json({ payroll: null, transactions: [], adjustments: [], pendingMonths: [], totalPendingBalance: 0, history: [] });
    }

    const callerUserId = req.user.userId;
    const month = (req.query.month || getCurrentMonthStr()).trim();

    const user = await findCompanyUser(companyId, callerUserId);
    if (!user) {
      return res.status(404).json({ message: 'User not found in company' });
    }

    const candidateIds = getUserCandidateIds(user);
    const [existing, adjustments, monthTransactions, historyPayrolls, pendingPayrolls] = await Promise.all([
      Payroll.findOne({ companyId, userId: { $in: candidateIds }, month }).lean(),
      PayrollAdjustment.find({ companyId, userId: { $in: candidateIds }, month }).sort({ createdAt: -1 }).lean(),
      PaymentTransaction.find({ companyId, userId: { $in: candidateIds }, month, status: 'completed' }).sort({ paidAt: -1 }).lean(),
      Payroll.find({ companyId, userId: { $in: candidateIds } })
        .select('id _id month status paymentStatus baseSalary earnedSalary netPayable totalAmount amountPaid pendingAmount paidAt')
        .sort({ month: -1 })
        .lean(),
      Payroll.find({ companyId, userId: { $in: candidateIds }, month: { $ne: month }, pendingAmount: { $gt: 0.01 } })
        .select('id _id month netPayable totalAmount amountPaid pendingAmount paymentStatus status')
        .sort({ month: -1 })
        .lean(),
    ]);

    let payrollRecord;
    if (existing && existing.status === 'finalized') {
      payrollRecord = buildFinalizedRecordView(existing, user, adjustments, monthTransactions);
    } else {
      const companyDoc = await Company.findById(companyId).select('leavePolicy').lean();
      const { settings, leavePolicy } = await resolvePolicyForMonth(companyId, month, companyDoc);

      const [holidays, attendances, leaves, leaveBalance] = await Promise.all([
        Holiday.find({ companyId, date: { $regex: `^${month}` }, description: { $not: /\[EVENT\]/i } }).lean(),
        Attendance.find({ companyId, userId: { $in: candidateIds }, date: { $regex: `^${month}` } }).lean(),
        Leave.find({
          companyId,
          userId: { $in: candidateIds },
          startDate: { $lte: `${month}-31` },
          endDate: { $gte: `${month}-01` },
        }).lean(),
        computeUserLeaveBalance(companyId, user.userId),
      ]);

      const currMonth = getCurrentMonthStr();
      const refDate = month < currMonth ? getPastMonthEndDate(month) : null;

      const calculated = calculateEmployeeMonthlyPayroll({
        user,
        month,
        settings,
        leavePolicy,
        leaveBalance,
        attendances,
        leaves,
        holidays,
        adjustments,
        referenceDate: refDate,
      });

      const amountPaid = sumTransactionsForPayroll(monthTransactions, existing?._id, candidateIds);
      const pendingAmount = Math.max(0, round2(calculated.totalAmount - amountPaid));
      const isPaid = pendingAmount <= 0.01 && amountPaid > 0;
      const isPartiallyPaid = amountPaid > 0 && pendingAmount > 0.01;

      payrollRecord = {
        ...calculated,
        _id: existing?._id,
        id: existing?.id,
        companyId,
        userId: user.userId,
        StaffId: user.StaffId || user.userId,
        name: user.name || user.username || user.userId,
        department: user.department || 'General',
        status: 'draft',
        paymentStatus: isPaid ? 'paid' : (isPartiallyPaid ? 'partially_paid' : 'unpaid'),
        amountPaid,
        pendingAmount,
        isFinalized: false,
        isClosed: false,
        isPaid,
        isPartiallyPaid,
      };
    }

    const totalPendingBalance = round2(
      (Number(payrollRecord.pendingAmount) || 0) +
      pendingPayrolls.reduce((s, p) => s + (Number(p.pendingAmount) || 0), 0)
    );

    res.status(200).json({
      payroll: payrollRecord,
      transaction: monthTransactions[0] || null,
      transactions: monthTransactions,
      adjustments,
      pendingMonths: pendingPayrolls,
      totalPendingBalance,
      history: historyPayrolls,
    });
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
};

/**
 * 8b. Generate & Download Monthly Payslip (JSON or PDF)
 */
export const getEmployeePayslip = async (req, res) => {
  try {
    const companyId = requireCompanyId(req, res);
    if (!companyId) return;

    const paramId = req.params.id;
    const requestedUserId = req.query.userId || req.user.userId;
    const requestedMonth = String(req.query.month || getCurrentMonthStr()).trim();
    const format = String(req.query.format || 'json').toLowerCase();

    let payroll = null;
    let targetUser = null;

    if (paramId) {
      const idFilter = mongoose.isValidObjectId(paramId)
        ? { $or: [{ _id: paramId }, { id: paramId }], companyId }
        : { id: paramId, companyId };
      payroll = await Payroll.findOne(idFilter).lean();
      if (!payroll) return res.status(404).json({ message: 'Payroll record not found' });
      targetUser = await findCompanyUser(companyId, payroll.userId);
    } else {
      targetUser = await findCompanyUser(companyId, requestedUserId);
      if (!targetUser) return res.status(404).json({ message: 'Employee not found in company' });
      const ids = getUserCandidateIds(targetUser);
      payroll = await Payroll.findOne({ companyId, userId: { $in: ids }, month: requestedMonth }).lean();
    }

    const caller = await findCompanyUser(companyId, req.user.userId);
    const callerIds = new Set(caller ? getUserCandidateIds(caller) : [req.user.userId]);
    const targetIds = new Set(targetUser ? getUserCandidateIds(targetUser) : [payroll?.userId || requestedUserId]);
    const isSelf = Array.from(targetIds).some(id => callerIds.has(id));

    if (!isCompanyAdmin(req.user) && !isSelf) {
      return res.status(403).json({ message: 'Access denied to another employee payslip' });
    }

    const month = payroll?.month || requestedMonth;
    const candidateIds = Array.from(targetIds);
    const [companyDoc, adjustments, transactions] = await Promise.all([
      Company.findById(companyId).select('name address city state phoneNumber email leavePolicy').lean(),
      PayrollAdjustment.find({ companyId, userId: { $in: candidateIds }, month }).sort({ createdAt: -1 }).lean(),
      PaymentTransaction.find({ companyId, userId: { $in: candidateIds }, month, status: 'completed' }).sort({ paidAt: -1 }).lean(),
    ]);

    let view;
    if (payroll && payroll.status === 'finalized') {
      view = buildFinalizedRecordView(payroll, targetUser || { userId: payroll.userId }, adjustments, transactions);
    } else {
      const { settings, leavePolicy } = await resolvePolicyForMonth(companyId, month, companyDoc);
      const [holidays, attendances, leaves, leaveBalance] = await Promise.all([
        Holiday.find({ companyId, date: { $regex: `^${month}` }, description: { $not: /\[EVENT\]/i } }).lean(),
        Attendance.find({ companyId, userId: { $in: candidateIds }, date: { $regex: `^${month}` } }).lean(),
        Leave.find({
          companyId,
          userId: { $in: candidateIds },
          startDate: { $lte: `${month}-31` },
          endDate: { $gte: `${month}-01` },
        }).lean(),
        computeUserLeaveBalance(companyId, targetUser.userId),
      ]);
      const currMonth = getCurrentMonthStr();
      const refDate = month < currMonth ? getPastMonthEndDate(month) : null;
      view = calculateEmployeeMonthlyPayroll({
        user: targetUser,
        month,
        settings,
        leavePolicy,
        leaveBalance,
        attendances,
        leaves,
        holidays,
        adjustments,
        referenceDate: refDate,
      });
      view.amountPaid = sumTransactionsForPayroll(transactions, payroll?._id, candidateIds);
      view.pendingAmount = Math.max(0, round2(view.totalAmount - view.amountPaid));
      view.paymentStatus = view.pendingAmount <= 0.01 && view.amountPaid > 0
        ? 'paid'
        : (view.amountPaid > 0 ? 'partially_paid' : 'unpaid');
    }

    const payslipNumber = payroll?.payslipNumber || `PS-${month.replace('-', '')}-${String(targetUser?.StaffId || targetUser?.userId || view.userId).slice(-6).toUpperCase()}`;

    const payslip = {
      payslipNumber,
      generatedAt: payroll?.payslipGeneratedAt || new Date().toISOString(),
      companyName: companyDoc?.name || 'Company',
      companyAddress: [companyDoc?.address, companyDoc?.city, companyDoc?.state].filter(Boolean).join(', '),
      month,
      status: payroll?.status || 'draft',
      paymentStatus: view.paymentStatus || 'unpaid',
      employee: {
        userId: targetUser?.userId || view.userId,
        staffId: targetUser?.StaffId || view.userId,
        name: targetUser?.name || targetUser?.username || view.name,
        department: targetUser?.department || view.department || 'General',
        designation: targetUser?.designation || view.designation || 'Staff',
      },
      attendanceSummary: {
        scheduledWorkingDays: view.scheduledWorkingDays || 0,
        presentDays: view.presentDays || 0,
        approvedLeaveDays: view.approvedLeaveDays || 0,
        unapprovedLeaveDays: view.unapprovedLeaveDays || 0,
        holidayDays: view.holidayDays || 0,
        weeklyOffDays: view.weeklyOffDays || 0,
        scheduledWorkingHours: view.scheduledWorkingHours || 0,
        actualWorkingHours: view.actualWorkingHours || 0,
        shortfallHours: view.shortfallHours || 0,
        overtimeHours: view.overtimeHours || 0,
        lateMinutes: view.lateMinutes || 0,
        totalBreakDelayMinutes: view.totalBreakDelayMinutes || 0,
      },
      earnings: {
        baseSalary: view.baseSalary || 0,
        earnedSalary: view.earnedSalary ?? view.baseSalary ?? 0,
        overtimeAddition: view.hourlyOvertimeAddition || 0,
        bonus: view.bonus || 0,
        grossPayable: view.grossPayable || 0,
      },
      deductions: {
        shortfallDeduction: view.hourlyShortfallDeduction || 0,
        lateDeduction: view.lateDeduction || 0,
        breakDeduction: view.totalBreakDeduction || 0,
        approvedLeaveDeduction: view.approvedLeaveDeduction || 0,
        unapprovedLeaveDeduction: view.unapprovedLeaveDeduction || 0,
        manualDeduction: view.manualDeduction || 0,
        totalDeductions: view.totalDeductions || 0,
      },
      paymentSummary: {
        netPayable: view.netPayable ?? view.totalAmount ?? 0,
        amountPaid: view.amountPaid || 0,
        pendingAmount: view.pendingAmount ?? view.netPayable ?? 0,
      },
      adjustments,
      transactions,
      dailyBreakdown: view.dailyBreakdown || [],
      snapshotSettings: view.snapshotSettings || null,
    };

    if (format === 'pdf') {
      const buffer = generatePayslipPdfBuffer(payslip);
      const safeStaff = String(payslip.employee.staffId || 'employee').replace(/[^a-zA-Z0-9_-]/g, '_');
      res.setHeader('Content-Type', 'application/pdf');
      res.setHeader('Content-Disposition', `attachment; filename="Payslip_${safeStaff}_${month}.pdf"`);
      return res.status(200).send(buffer);
    }

    res.status(200).json(payslip);
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
};

/**
 * Helper: Recalculates and updates an existing open Payroll record when adjustments change.
 */
export const syncPayrollWithAdjustments = async (companyId, userId, month, actor = null) => {
  try {
    const user = await findCompanyUser(companyId, userId);
    if (!user) return null;

    const candidateIds = getUserCandidateIds(user);
    const [allAdjustments, transactions, payroll] = await Promise.all([
      PayrollAdjustment.find({ companyId, userId: { $in: candidateIds }, month }).lean(),
      PaymentTransaction.find({ companyId, userId: { $in: candidateIds }, month, status: 'completed' }).lean(),
      Payroll.findOne({ companyId, userId: { $in: candidateIds }, month }),
    ]);

    const totalBonus = round2(
      allAdjustments.filter(a => a.type === 'bonus').reduce((sum, a) => sum + (Number(a.amount) || 0), 0)
    );
    const totalManualDeduction = round2(
      allAdjustments.filter(a => a.type === 'deduction').reduce((sum, a) => sum + (Number(a.amount) || 0), 0)
    );

    if (payroll) {
      let priorPaid = round2(transactions.reduce((sum, tx) => sum + (Number(tx.amount) || 0), 0));
      if (priorPaid === 0 && payroll.paymentStatus === 'paid') {
        priorPaid = (payroll.amountPaid && payroll.amountPaid > 0)
          ? payroll.amountPaid
          : (payroll.totalAmount || payroll.netPayable || 0);
      }

      payroll.bonus = totalBonus;
      payroll.manualDeduction = totalManualDeduction;
      payroll.totalAdditions = round2((payroll.hourlyOvertimeAddition || 0) + totalBonus);
      payroll.totalDeductions = round2(
        (payroll.hourlyShortfallDeduction || 0) +
        (payroll.approvedLeaveDeduction || 0) +
        (payroll.unapprovedLeaveDeduction || 0) +
        (payroll.lateDeduction || 0) +
        (payroll.totalBreakDeduction || 0) +
        totalManualDeduction
      );
      payroll.grossPayable = round2((payroll.baseSalary || 0) + payroll.totalAdditions);
      payroll.totalAmount = Math.max(0, round2(payroll.grossPayable - payroll.totalDeductions));
      payroll.netPayable = payroll.totalAmount;

      payroll.amountPaid = priorPaid;
      payroll.pendingAmount = Math.max(0, round2(payroll.totalAmount - priorPaid));

      if (payroll.pendingAmount <= 0.01 && (priorPaid > 0 || payroll.paymentStatus === 'paid')) {
        payroll.paymentStatus = 'paid';
      } else if (priorPaid > 0 && payroll.pendingAmount > 0.01) {
        payroll.paymentStatus = 'partially_paid';
      }

      if (actor) {
        payroll.auditTrail.push({
          action: 'ADJUSTMENTS_SYNCED',
          performedBy: actor.userId || actor.username || 'admin',
          timestamp: new Date(),
          details: { totalBonus, totalManualDeduction, netPayable: payroll.netPayable, amountPaid: payroll.amountPaid, pendingAmount: payroll.pendingAmount },
        });
      }

      await payroll.save();

      emitToCompany('payroll:change', companyId, { action: 'updated', payrollId: payroll._id, month });
      emitToUser(user.userId, 'payroll:change', { action: 'updated', payrollId: payroll._id, month });
      return payroll;
    }
    return null;
  } catch (err) {
    console.error('Error syncing payroll with adjustments:', err);
    return null;
  }
};

/**
 * 9. Add Bonus or Deduction Adjustment for Employee
 */
export const addPayrollAdjustment = async (req, res) => {
  try {
    const companyId = requireCompanyId(req, res);
    if (!companyId) return;

    if (!isCompanyAdmin(req.user)) {
      return res.status(403).json({ message: 'Only company admins or owners can add adjustments' });
    }

    const { userId, month, type, amount, reason } = req.body;
    if (!userId) {
      return res.status(400).json({ message: 'Employee userId is required' });
    }
    if (!type || !['bonus', 'deduction'].includes(type)) {
      return res.status(400).json({ message: 'Valid type is required (bonus or deduction)' });
    }
    const numericAmount = Number(amount);
    if (isNaN(numericAmount) || numericAmount <= 0) {
      return res.status(400).json({ message: 'Amount must be a positive number' });
    }

    const adjMonth = (month || getCurrentMonthStr()).trim();
    const user = await findCompanyUser(companyId, userId);
    if (!user) {
      return res.status(404).json({ message: 'Employee not found in this company' });
    }

    const candidateIds = getUserCandidateIds(user);
    const existingPayroll = await Payroll.findOne({ companyId, userId: { $in: candidateIds }, month: adjMonth }).lean();
    if (existingPayroll && (existingPayroll.paymentStatus === 'paid' || (existingPayroll.isClosed && type === 'deduction'))) {
      return res.status(400).json({
        message: `Payroll for ${adjMonth} is already ${existingPayroll.paymentStatus === 'paid' ? 'fully paid' : 'closed'}. Please add this adjustment to the next open payroll month instead.`,
      });
    }

    const adjustment = await PayrollAdjustment.create({
      companyId,
      userId: user.userId,
      month: adjMonth,
      type,
      amount: round2(numericAmount),
      reason: reason ? String(reason).trim() : '',
      addedBy: req.user.userId,
      addedByName: req.user.name || req.user.username || req.user.userId,
    });

    const updatedPayroll = await syncPayrollWithAdjustments(companyId, user.userId, adjMonth, req.user);

    try {
      const notifTitle = type === 'bonus' ? 'Bonus Added to Salary' : 'Salary Deduction Applied';
      const notifMsg = type === 'bonus'
        ? `A bonus of ₹${numericAmount.toLocaleString('en-IN')} has been added to your salary for ${adjMonth}${reason ? ` (${reason})` : ''}.`
        : `A manual deduction of ₹${numericAmount.toLocaleString('en-IN')} has been applied to your salary for ${adjMonth}${reason ? ` (${reason})` : ''}.`;

      await notifyUserAllAliases(companyId, user, {
        id: `notif-adj-${adjustment._id}`,
        title: notifTitle,
        message: notifMsg,
        type: type === 'bonus' ? 'bonus' : 'deduction',
        metadata: {
          month: adjMonth,
          type,
          amount: round2(numericAmount),
          reason: reason || '',
          adjustmentId: adjustment._id,
        },
      });
    } catch (notifErr) {
      console.warn('Failed to send adjustment notification:', notifErr.message);
    }

    res.status(201).json({
      message: `${type === 'bonus' ? 'Bonus' : 'Deduction'} of ₹${numericAmount.toLocaleString()} added successfully for ${user.name || user.username || user.userId}`,
      adjustment,
      payroll: updatedPayroll,
    });
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
};

/**
 * 10. Get Payroll Adjustments (Scoped strictly to self for non-admins)
 */
export const getPayrollAdjustments = async (req, res) => {
  try {
    const companyId = requireCompanyId(req, res, true);
    if (!companyId) return res.status(200).json([]);

    const { month, userId } = req.query;
    const filter = { companyId };
    if (month) filter.month = String(month).trim();

    if (!isCompanyAdmin(req.user)) {
      const caller = await findCompanyUser(companyId, req.user.userId);
      const ids = caller ? getUserCandidateIds(caller) : [req.user.userId];
      filter.userId = { $in: ids };
    } else if (userId) {
      const target = await findCompanyUser(companyId, userId);
      const ids = target ? getUserCandidateIds(target) : [String(userId).trim()];
      filter.userId = { $in: ids };
    }

    const adjustments = await PayrollAdjustment.find(filter).sort({ createdAt: -1 }).lean();
    res.status(200).json(adjustments);
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
};

/**
 * 11. Delete Payroll Adjustment
 */
export const deletePayrollAdjustment = async (req, res) => {
  try {
    const companyId = requireCompanyId(req, res);
    if (!companyId) return;

    if (!isCompanyAdmin(req.user)) {
      return res.status(403).json({ message: 'Only company admins or owners can delete adjustments' });
    }

    const { id } = req.params;
    const existingAdj = await PayrollAdjustment.findOne({ _id: id, companyId }).lean();
    if (!existingAdj) {
      return res.status(404).json({ message: 'Adjustment not found' });
    }

    const existingPayroll = await Payroll.findOne({
      companyId,
      userId: existingAdj.userId,
      month: existingAdj.month,
    }).lean();
    if (existingPayroll && (existingPayroll.paymentStatus === 'paid' || existingPayroll.isClosed)) {
      return res.status(400).json({ message: `Cannot remove adjustments from a closed or fully paid payroll (${existingAdj.month}).` });
    }

    await PayrollAdjustment.findOneAndDelete({ _id: id, companyId });
    await syncPayrollWithAdjustments(companyId, existingAdj.userId, existingAdj.month, req.user);

    res.status(200).json({ message: 'Adjustment removed successfully' });
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
};

const isPfAdjustment = (adj) => {
  const txt = `${adj?.reason || ''} ${adj?.type || ''}`.toLowerCase();
  return txt.includes('provident') || /\bpf\b/.test(txt);
};

const summarizePayrollComponents = ({
  payrollDoc = null,
  adjustments = [],
  transactions = [],
}) => {
  const bonuses = round2(
    adjustments
      .filter((a) => a.type === 'bonus')
      .reduce((sum, a) => sum + Number(a.amount || 0), 0),
  );
  const manualDeductionsFromAdj = round2(
    adjustments
      .filter((a) => a.type === 'deduction')
      .reduce((sum, a) => sum + Number(a.amount || 0), 0),
  );
  const pfDeduction = round2(
    adjustments
      .filter((a) => a.type === 'deduction' && isPfAdjustment(a))
      .reduce((sum, a) => sum + Number(a.amount || 0), 0),
  );

  const overtimePay = round2(Number(payrollDoc?.hourlyOvertimeAddition) || 0);
  const overtimeHours = round2(Number(payrollDoc?.overtimeHours) || 0);
  const approvedLeaveDeduction = round2(Number(payrollDoc?.approvedLeaveDeduction) || 0);
  const unapprovedLeaveDeduction = round2(Number(payrollDoc?.unapprovedLeaveDeduction) || 0);
  const unpaidLeaveDeductions = round2(approvedLeaveDeduction + unapprovedLeaveDeduction);
  const lateDeduction = round2(Number(payrollDoc?.lateDeduction) || 0);
  const shortfallDeduction = round2(Number(payrollDoc?.hourlyShortfallDeduction) || 0);
  const breakDeduction = round2(Number(payrollDoc?.totalBreakDeduction) || 0);
  const manualDeduction = round2(Number(payrollDoc?.manualDeduction ?? manualDeductionsFromAdj) || 0);
  const earnedSalary = round2(Number(payrollDoc?.earnedSalary) || 0);
  const grossPayable = round2(Number(payrollDoc?.grossPayable) || 0);

  const paymentHistory = transactions
    .map((t) => ({
      id: t.id || String(t._id),
      type: t.type || 'salary',
      amount: round2(Number(t.amount) || 0),
      paymentMethod: t.paymentMethod || 'bank_transfer',
      referenceId: t.referenceId || '',
      status: t.status || 'completed',
      paidAt: t.paidAt ? new Date(t.paidAt).toISOString() : (t.createdAt ? new Date(t.createdAt).toISOString() : ''),
      processedByName: t.processedByName || t.processedBy || '',
      notes: t.notes || '',
      month: t.month || '',
    }))
    .sort((a, b) => String(b.paidAt || '').localeCompare(String(a.paidAt || '')));

  const adjustmentHistory = adjustments.map((a) => ({
    id: a.id || String(a._id),
    type: a.type,
    amount: round2(Number(a.amount) || 0),
    reason: a.reason || '',
    month: a.month || '',
    addedByName: a.addedByName || a.addedBy || '',
    createdAt: a.createdAt ? new Date(a.createdAt).toISOString() : '',
  }));

  return {
    earnedSalary,
    grossPayable,
    allowances: 0,
    bonuses,
    overtimeHours,
    overtimePay,
    unpaidLeaveDeductions,
    approvedLeaveDeduction,
    unapprovedLeaveDeduction,
    leaveDeductionBreakdown: payrollDoc?.leaveDeductionBreakdown || null,
    lateDeduction,
    shortfallDeduction,
    breakDeduction,
    manualDeduction,
    pfDeduction,
    otherAdjustments: round2(Number(payrollDoc?.otherAdjustments) || 0),
    lastPaidAt: paymentHistory.length > 0
      ? paymentHistory[0].paidAt
      : (payrollDoc?.paidAt ? new Date(payrollDoc.paidAt).toISOString() : ''),
    paymentHistory,
    adjustments: adjustmentHistory,
    auditTrail: Array.isArray(payrollDoc?.auditTrail) ? payrollDoc.auditTrail : [],
  };
};

/**
 * 12. Helper to build detailed Historical Payroll / Payment report data
 * Supports all | range | day | week | month | year without altering payroll rules.
 */
export const buildPayrollReportData = async (companyId, queryParams = {}) => {
  const {
    userId: queryUserId,
    employeeId: queryEmployeeId,
    department,
    status,
    search,
  } = queryParams;

  const targetEmployeeFilter = queryUserId || queryEmployeeId || 'all';

  const [company, earliestPayroll, earliestTx, userLookup] = await Promise.all([
    Company.findById(companyId).select('name code email createdAt').lean(),
    Payroll.findOne({ companyId }).sort({ month: 1 }).select('month').lean(),
    PaymentTransaction.findOne({ companyId }).sort({ paidAt: 1 }).select('paidAt month').lean(),
    buildCompanyUserLookup(companyId),
  ]);

  const companyName = company?.name || 'Company';
  const earliestPayrollDate = earliestPayroll?.month ? `${earliestPayroll.month}-01` : '';
  const earliestTxDate = normalizeDateOnly(earliestTx?.paidAt);
  const companyCreatedDate = normalizeDateOnly(company?.createdAt);
  const earliestRecordDate = [earliestPayrollDate, earliestTxDate, companyCreatedDate]
    .filter(Boolean)
    .sort()[0] || '';

  const window = resolveReportWindow(queryParams, earliestRecordDate);
  const period = window.period;
  const periodLabel = window.periodLabel;

  let reportItems = [];
  let transactionRows = [];

  // Map company staff + discover any historical userIds in Payroll/PaymentTransaction not in User
  const ensureHistoricalEmployees = async (payrollDocs = [], txDocs = []) => {
    const knownIds = new Set();
    for (const u of userLookup.staffUsers) {
      getUserCandidateIds(u).forEach((id) => knownIds.add(String(id)));
    }
    const extraUsers = [];
    const seenExtra = new Set();
    for (const doc of [...payrollDocs, ...txDocs]) {
      const uid = String(doc.userId || '').trim();
      if (!uid || knownIds.has(uid) || seenExtra.has(uid)) continue;
      seenExtra.add(uid);
      const resolved = userLookup.resolveUser(uid);
      extraUsers.push({
        userId: resolved.userId,
        StaffId: resolved.staffId,
        name: resolved.name,
        department: resolved.department,
        designation: resolved.designation,
        joiningDate: resolved.joiningDate,
        status: resolved.employeeStatus,
        salary: resolved.salary,
      });
    }
    return [...userLookup.staffUsers, ...extraUsers];
  };

  if (period === 'all' || period === 'range' || period === 'year') {
    const startMonth = window.startDate ? window.startDate.slice(0, 7) : null;
    const endMonth = window.endDate ? window.endDate.slice(0, 7) : null;
    const monthFilter = {};
    if (startMonth) monthFilter.$gte = startMonth;
    if (endMonth) monthFilter.$lte = endMonth;

    const payrollQuery = { companyId };
    const adjQuery = { companyId };
    const txQuery = { companyId, status: 'completed' };
    if (Object.keys(monthFilter).length > 0) {
      payrollQuery.month = monthFilter;
      adjQuery.month = monthFilter;
      txQuery.month = monthFilter;
    }

    const currMonth = getCurrentMonthStr();
    const isCurrMonthInWindow = (!startMonth || currMonth >= startMonth) && (!endMonth || currMonth <= endMonth);

    const [histPayrolls, histAdjustments, histTransactions, currMonthAttCount, currMonthLeaveCount] = await Promise.all([
      Payroll.find(payrollQuery).sort({ month: -1 }).lean(),
      PayrollAdjustment.find(adjQuery).sort({ createdAt: -1 }).lean(),
      PaymentTransaction.find(txQuery).sort({ paidAt: -1 }).lean(),
      isCurrMonthInWindow ? Attendance.countDocuments({ companyId, date: { $regex: `^${currMonth}` } }) : Promise.resolve(0),
      isCurrMonthInWindow
        ? Leave.countDocuments({ companyId, startDate: { $lte: `${currMonth}-31` }, endDate: { $gte: `${currMonth}-01` } })
        : Promise.resolve(0),
    ]);

    const employeesForReport = await ensureHistoricalEmployees(histPayrolls, histTransactions);

    // Precompute live dynamic summary for any month in histPayrolls that has draft records
    // or for the current active month if attendance/leaves/adjustments exist without finalized docs.
    const liveMonthCache = new Map();
    const getLiveMonthMap = async (targetM) => {
      if (liveMonthCache.has(targetM)) return liveMonthCache.get(targetM);
      const reqMock = { companyId, user: { role: 'admin' }, query: { month: targetM, limit: 1000, includeInactive: 'true' } };
      let summaryData = null;
      const resMock = { status: () => ({ json: (data) => { summaryData = data; } }) };
      await getPayrollSummary(reqMock, resMock);
      const map = new Map();
      (summaryData?.items || []).forEach((item) => {
        map.set(String(item.userId), item);
        if (item.StaffId) map.set(String(item.StaffId), item);
      });
      liveMonthCache.set(targetM, map);
      return map;
    };

    // Emit one historical record per stored employee-month payroll (and transaction/live current month)
    const shouldIncludeCurrMonth = isCurrMonthInWindow && (currMonthAttCount > 0 || currMonthLeaveCount > 0);
    for (const u of employeesForReport) {
      const uid = u.userId || u.StaffId || String(u._id);
      const candidateIds = getUserCandidateIds(u);
      if (candidateIds.length === 0) candidateIds.push(uid);

      const empPayrolls = histPayrolls.filter((p) => candidateIds.includes(String(p.userId)));
      const empAdjustments = histAdjustments.filter((a) => candidateIds.includes(String(a.userId)));
      const empTransactions = histTransactions.filter((t) => candidateIds.includes(String(t.userId)));

      const monthKeys = new Set([
        ...empPayrolls.map((p) => p.month),
        ...empAdjustments.map((a) => a.month),
        ...empTransactions.map((t) => t.month),
      ].filter(Boolean));
      if (shouldIncludeCurrMonth && u.status !== 'inactive') {
        monthKeys.add(currMonth);
      }

      const sortedMonths = Array.from(monthKeys).sort((a, b) => b.localeCompare(a));
      for (const m of sortedMonths) {
        const storedDoc = empPayrolls.find((doc) => doc.month === m) || null;
        const mAdjs = empAdjustments.filter((a) => a.month === m);
        const mTxs = empTransactions.filter((t) => t.month === m);

        let effectiveDoc = storedDoc;
        if (!storedDoc || storedDoc.status !== 'finalized') {
          const liveMap = await getLiveMonthMap(m);
          const liveItem = candidateIds.map((id) => liveMap.get(String(id))).find(Boolean) || null;
          if (liveItem) {
            effectiveDoc = liveItem;
          }
        }

        const comp = summarizePayrollComponents({
          payrollDoc: effectiveDoc,
          adjustments: mAdjs,
          transactions: mTxs,
        });

        const baseSalary = round2(Number(effectiveDoc?.baseSalary ?? u.salary) || 0);
        const netPayable = round2(Number(effectiveDoc?.totalAmount ?? effectiveDoc?.netPayable) || 0);
        const txPaid = round2(mTxs.reduce((s, t) => s + (Number(t.amount) || 0), 0));
        const amountPaid = txPaid > 0 ? txPaid : round2(Number(effectiveDoc?.amountPaid) || 0);
        const pendingAmount = Math.max(0, round2(netPayable - amountPaid));
        const totalDeductions = round2(Number(effectiveDoc?.totalDeductions) || comp.manualDeduction);
        const bonusVal = round2(Number(effectiveDoc?.bonus ?? comp.bonuses) || 0);

        let empPaymentStatus = effectiveDoc?.paymentStatus || 'unpaid';
        if (pendingAmount <= 0.01 && (amountPaid > 0 || effectiveDoc?.paymentStatus === 'paid')) {
          empPaymentStatus = 'paid';
        } else if (amountPaid > 0 && pendingAmount > 0.01) {
          empPaymentStatus = 'partially_paid';
        }

        reportItems.push({
          id: storedDoc?.id || effectiveDoc?.id || `${uid}_${m}`,
          period: m,
          salaryPeriod: m,
          year: m.slice(0, 4),
          month: m,
          userId: uid,
          staffId: u.StaffId || uid,
          name: u.name || u.username || uid,
          department: u.department || 'General',
          designation: u.designation || 'Staff',
          joiningDate: normalizeDateOnly(u.joiningDate || u.createdAt),
          employeeStatus: u.status || 'active',
          baseSalary,
          earnedSalary: comp.earnedSalary,
          grossPayable: comp.grossPayable,
          allowances: comp.allowances,
          bonus: bonusVal,
          overtimeHours: comp.overtimeHours,
          overtimePay: comp.overtimePay,
          unpaidLeaveDeductions: comp.unpaidLeaveDeductions,
          approvedLeaveDeduction: comp.approvedLeaveDeduction,
          unapprovedLeaveDeduction: comp.unapprovedLeaveDeduction,
          lateDeduction: comp.lateDeduction,
          shortfallDeduction: comp.shortfallDeduction,
          breakDeduction: comp.breakDeduction,
          manualDeduction: comp.manualDeduction,
          pfDeduction: comp.pfDeduction,
          totalDeductions,
          totalAmount: netPayable,
          netSalary: netPayable,
          amountPaid,
          pendingAmount,
          paymentStatus: empPaymentStatus,
          payrollStatus: storedDoc?.status || effectiveDoc?.status || 'draft',
          payslipNumber: storedDoc?.payslipNumber || '',
          lastPaidAt: comp.lastPaidAt,
          paymentHistory: comp.paymentHistory,
          adjustments: comp.adjustments,
          auditTrail: comp.auditTrail,
          _rawUser: u,
        });
      }
    }

    transactionRows = histTransactions.map((t) => {
      const emp = userLookup.resolveUser(t.userId);
      return {
        id: t.id || String(t._id),
        userId: emp.userId,
        staffId: emp.staffId,
        name: emp.name,
        department: emp.department,
        designation: emp.designation,
        month: t.month,
        type: t.type || 'salary',
        amount: round2(Number(t.amount) || 0),
        paymentMethod: t.paymentMethod || 'bank_transfer',
        referenceId: t.referenceId || '',
        status: t.status || 'completed',
        paidAt: t.paidAt ? new Date(t.paidAt).toISOString() : '',
        processedByName: t.processedByName || t.processedBy || '',
        notes: t.notes || '',
      };
    });
  } else if (period === 'day' || period === 'week') {
    const start = window.startDate;
    const end = window.endDate;
    const startIso = new Date(`${start}T00:00:00.000Z`);
    const endIso = new Date(`${end}T23:59:59.999Z`);
    const currentMonth = start.slice(0, 7);

    const [txs, monthPayrolls, monthAdjustments] = await Promise.all([
      PaymentTransaction.find({ companyId, paidAt: { $gte: startIso, $lte: endIso }, status: 'completed' }).sort({ paidAt: -1 }).lean(),
      Payroll.find({ companyId, month: currentMonth }).lean(),
      PayrollAdjustment.find({ companyId, month: currentMonth }).lean(),
    ]);

    const reqMockDay = { companyId, user: { role: 'admin' }, query: { month: currentMonth, limit: 1000, includeInactive: 'true' } };
    let liveSummaryDay = null;
    const resMockDay = { status: () => ({ json: (data) => { liveSummaryDay = data; } }) };
    await getPayrollSummary(reqMockDay, resMockDay);
    const liveDayMap = new Map();
    (liveSummaryDay?.items || []).forEach((item) => {
      liveDayMap.set(String(item.userId), item);
      if (item.StaffId) liveDayMap.set(String(item.StaffId), item);
    });

    const employeesForReport = await ensureHistoricalEmployees(monthPayrolls, txs);
    const monthPayrollsMap = new Map();
    monthPayrolls.forEach((p) => monthPayrollsMap.set(String(p.userId), p));

    for (const u of employeesForReport) {
      const uid = u.userId || u.StaffId || String(u._id);
      const candidateIds = getUserCandidateIds(u);
      if (candidateIds.length === 0) candidateIds.push(uid);

      const empTxs = txs.filter((t) => candidateIds.includes(String(t.userId)));
      const empAdjs = monthAdjustments.filter((a) => candidateIds.includes(String(a.userId)));
      const storedP = candidateIds.map((id) => monthPayrollsMap.get(id)).find(Boolean) || null;
      const liveP = candidateIds.map((id) => liveDayMap.get(id)).find(Boolean) || null;
      const p = (storedP && storedP.status === 'finalized') ? storedP : (liveP || storedP);
      const comp = summarizePayrollComponents({ payrollDoc: p, adjustments: empAdjs, transactions: empTxs });

      const paidInWindow = round2(empTxs.reduce((s, t) => s + Number(t.amount || 0), 0));
      const bonusInWindow = round2(
        empTxs.filter((t) => t.type === 'bonus').reduce((s, t) => s + Number(t.amount || 0), 0),
      );
      const totalAmountRef = round2(Number(p?.totalAmount ?? p?.netPayable) || 0);
      const pendingAmount = p ? Math.max(0, round2(totalAmountRef - Number(p.amountPaid || paidInWindow || 0))) : 0;
      const baseSalary = round2(Number(p?.baseSalary ?? u.salary) || 0);

      let pStatus = 'unpaid';
      if (paidInWindow > 0 && pendingAmount <= 0.01) pStatus = 'paid';
      else if (paidInWindow > 0) pStatus = 'partially_paid';
      else if (p?.paymentStatus === 'paid') pStatus = 'paid';

      reportItems.push({
        id: p?.id || `${uid}_${start}`,
        period: period === 'day' ? start : `${start} to ${end}`,
        salaryPeriod: currentMonth,
        year: currentMonth.slice(0, 4),
        month: currentMonth,
        userId: uid,
        staffId: u.StaffId || uid,
        name: u.name || u.username || uid,
        department: u.department || 'General',
        designation: u.designation || 'Staff',
        joiningDate: normalizeDateOnly(u.joiningDate || u.createdAt),
        employeeStatus: u.status || 'active',
        baseSalary,
        earnedSalary: comp.earnedSalary,
        grossPayable: comp.grossPayable,
        allowances: comp.allowances,
        amountPaid: paidInWindow,
        pendingAmount,
        bonus: bonusInWindow || comp.bonuses,
        overtimeHours: comp.overtimeHours,
        overtimePay: comp.overtimePay,
        unpaidLeaveDeductions: comp.unpaidLeaveDeductions,
        approvedLeaveDeduction: comp.approvedLeaveDeduction,
        unapprovedLeaveDeduction: comp.unapprovedLeaveDeduction,
        lateDeduction: comp.lateDeduction,
        shortfallDeduction: comp.shortfallDeduction,
        breakDeduction: comp.breakDeduction,
        manualDeduction: comp.manualDeduction,
        pfDeduction: comp.pfDeduction,
        totalDeductions: p ? (p.totalDeductions || 0) : 0,
        totalAmount: round2(paidInWindow + pendingAmount),
        netSalary: p ? round2(p.totalAmount || p.netPayable || 0) : round2(paidInWindow + pendingAmount),
        paymentStatus: pStatus,
        payrollStatus: p?.status || 'draft',
        lastPaidAt: comp.lastPaidAt,
        paymentHistory: comp.paymentHistory,
        adjustments: comp.adjustments,
        auditTrail: comp.auditTrail,
        _rawUser: u,
      });
    }

    transactionRows = txs.map((t) => {
      const emp = userLookup.resolveUser(t.userId);
      return {
        id: t.id || String(t._id),
        userId: emp.userId,
        staffId: emp.staffId,
        name: emp.name,
        department: emp.department,
        designation: emp.designation,
        month: t.month,
        type: t.type || 'salary',
        amount: round2(Number(t.amount) || 0),
        paymentMethod: t.paymentMethod || 'bank_transfer',
        referenceId: t.referenceId || '',
        status: t.status || 'completed',
        paidAt: t.paidAt ? new Date(t.paidAt).toISOString() : '',
        processedByName: t.processedByName || t.processedBy || '',
        notes: t.notes || '',
      };
    });
  } else {
    // 'month' — preserves exact existing calculation engine via getPayrollSummary, plus component & tx enrichment
    const targetMonth = window.monthPrefix || getCurrentMonthStr();

    const reqMock = { companyId, user: { role: 'admin' }, query: { month: targetMonth, limit: 1000, includeInactive: 'true' } };
    let summaryData = null;
    const resMock = {
      status: () => ({ json: (data) => { summaryData = data; } }),
    };
    await getPayrollSummary(reqMock, resMock);

    const [monthPayrolls, monthAdjustments, monthTransactions] = await Promise.all([
      Payroll.find({ companyId, month: targetMonth }).lean(),
      PayrollAdjustment.find({ companyId, month: targetMonth }).sort({ createdAt: -1 }).lean(),
      PaymentTransaction.find({ companyId, month: targetMonth, status: 'completed' }).sort({ paidAt: -1 }).lean(),
    ]);

    if (summaryData && Array.isArray(summaryData.items)) {
      reportItems = summaryData.items.map((p) => {
        const empMeta = userLookup.resolveUser(p.userId, p.name);
        const candidates = [p.userId, p.StaffId, empMeta.user?._id ? String(empMeta.user._id) : null].filter(Boolean).map(String);
        const storedDoc = monthPayrolls.find((doc) => candidates.includes(String(doc.userId)));
        // Use live dynamic calculation p for draft/open months so stale draft snapshots never mask live deductions
        const payrollDoc = (storedDoc && storedDoc.status === 'finalized') ? storedDoc : p;
        const empAdjs = monthAdjustments.filter((a) => candidates.includes(String(a.userId)));
        const empTxs = monthTransactions.filter((t) => candidates.includes(String(t.userId)));
        const comp = summarizePayrollComponents({
          payrollDoc,
          adjustments: empAdjs,
          transactions: empTxs,
        });

        const netSal = p.totalAmount !== undefined ? p.totalAmount : p.netPayable;
        return {
          id: payrollDoc?.id || `${p.userId}_${targetMonth}`,
          period: targetMonth,
          salaryPeriod: targetMonth,
          year: targetMonth.slice(0, 4),
          month: targetMonth,
          userId: p.userId,
          staffId: p.StaffId || p.userId,
          name: p.name,
          department: p.department || 'General',
          designation: p.designation || 'Staff',
          joiningDate: empMeta.joiningDate,
          employeeStatus: empMeta.employeeStatus,
          baseSalary: p.baseSalary || 0,
          earnedSalary: comp.earnedSalary,
          grossPayable: comp.grossPayable,
          allowances: comp.allowances,
          amountPaid: p.amountPaid || 0,
          pendingAmount: p.pendingAmount !== undefined ? p.pendingAmount : (p.isPaid ? 0 : p.totalAmount),
          bonus: p.bonus || 0,
          overtimeHours: comp.overtimeHours,
          overtimePay: comp.overtimePay,
          unpaidLeaveDeductions: comp.unpaidLeaveDeductions,
          approvedLeaveDeduction: comp.approvedLeaveDeduction,
          unapprovedLeaveDeduction: comp.unapprovedLeaveDeduction,
          lateDeduction: comp.lateDeduction,
          shortfallDeduction: comp.shortfallDeduction,
          breakDeduction: comp.breakDeduction,
          manualDeduction: comp.manualDeduction,
          pfDeduction: comp.pfDeduction,
          totalDeductions: p.totalDeductions || 0,
          totalAmount: netSal,
          netSalary: netSal,
          paymentStatus: p.paymentStatus || (p.isPaid ? 'paid' : 'unpaid'),
          payrollStatus: payrollDoc?.status || 'draft',
          payslipNumber: payrollDoc?.payslipNumber || '',
          lastPaidAt: comp.lastPaidAt,
          paymentHistory: comp.paymentHistory,
          adjustments: comp.adjustments,
          auditTrail: comp.auditTrail,
          _rawUser: empMeta.user || { userId: p.userId, StaffId: p.StaffId },
        };
      });
    }

    transactionRows = monthTransactions.map((t) => {
      const emp = userLookup.resolveUser(t.userId);
      return {
        id: t.id || String(t._id),
        userId: emp.userId,
        staffId: emp.staffId,
        name: emp.name,
        department: emp.department,
        designation: emp.designation,
        month: t.month,
        type: t.type || 'salary',
        amount: round2(Number(t.amount) || 0),
        paymentMethod: t.paymentMethod || 'bank_transfer',
        referenceId: t.referenceId || '',
        status: t.status || 'completed',
        paidAt: t.paidAt ? new Date(t.paidAt).toISOString() : '',
        processedByName: t.processedByName || t.processedBy || '',
        notes: t.notes || '',
      };
    });
  }

  // Filter by employee, department, payment status, or search
  if (targetEmployeeFilter && targetEmployeeFilter !== 'all') {
    const targetLower = String(targetEmployeeFilter).trim().toLowerCase();
    reportItems = reportItems.filter((r) => {
      const meta = r._rawUser
        ? { user: r._rawUser, userId: r.userId, staffId: r.staffId }
        : userLookup.resolveUser(r.userId);
      return matchesEmployeeFilter(meta, targetLower);
    });
    transactionRows = transactionRows.filter((t) =>
      String(t.userId || '').toLowerCase() === targetLower ||
      String(t.staffId || '').toLowerCase() === targetLower,
    );
  }
  if (department && department !== 'all') {
    reportItems = reportItems.filter((r) => (r.department || '').toLowerCase() === String(department).toLowerCase());
    transactionRows = transactionRows.filter((t) => (t.department || '').toLowerCase() === String(department).toLowerCase());
  }
  if (status && status !== 'all') {
    if (status === 'paid') reportItems = reportItems.filter((r) => r.paymentStatus === 'paid');
    else if (status === 'pending') reportItems = reportItems.filter((r) => r.paymentStatus === 'partially_paid' || r.paymentStatus === 'unpaid');
    else reportItems = reportItems.filter((r) => r.paymentStatus === status);
  }
  if (search) {
    const q = String(search).toLowerCase().trim();
    reportItems = reportItems.filter((r) =>
      (r.name || '').toLowerCase().includes(q) ||
      (r.staffId || '').toLowerCase().includes(q) ||
      (r.userId || '').toLowerCase().includes(q) ||
      (r.department || '').toLowerCase().includes(q) ||
      (r.salaryPeriod || '').toLowerCase().includes(q),
    );
    transactionRows = transactionRows.filter((t) =>
      (t.name || '').toLowerCase().includes(q) ||
      (t.staffId || '').toLowerCase().includes(q) ||
      (t.referenceId || '').toLowerCase().includes(q),
    );
  }

  const cleanReportItems = reportItems.map(({ _rawUser, ...rest }) => rest);

  const totalEmployees = cleanReportItems.length;
  const companyOverallAmountPaid = round2(cleanReportItems.reduce((sum, r) => sum + (Number(r.amountPaid) || 0), 0));
  const companyOverallPendingAmount = round2(cleanReportItems.reduce((sum, r) => sum + (Number(r.pendingAmount) || 0), 0));
  const companyOverallBonuses = round2(cleanReportItems.reduce((sum, r) => sum + (Number(r.bonus) || 0), 0));
  const companyOverallDeductions = round2(cleanReportItems.reduce((sum, r) => sum + (Number(r.totalDeductions) || 0), 0));
  const companyOverallBaseSalary = round2(cleanReportItems.reduce((sum, r) => sum + (Number(r.baseSalary) || 0), 0));
  const companyTotalNetPayable = round2(cleanReportItems.reduce((sum, r) => sum + (Number(r.totalAmount) || 0), 0));
  const companyOverallOvertimePay = round2(cleanReportItems.reduce((sum, r) => sum + (Number(r.overtimePay) || 0), 0));
  const companyOverallLeaveDeductions = round2(cleanReportItems.reduce((sum, r) => sum + (Number(r.unpaidLeaveDeductions) || 0), 0));
  const companyOverallPfDeductions = round2(cleanReportItems.reduce((sum, r) => sum + (Number(r.pfDeduction) || 0), 0));

  const fullyPaidEmployees = cleanReportItems.filter((r) => r.paymentStatus === 'paid').length;
  const pendingEmployees = cleanReportItems.filter((r) => r.paymentStatus !== 'paid').length;
  const pfSupported = companyOverallPfDeductions > 0;

  const csvHeaders = [
    'Period', 'Employee ID', 'Name', 'Department', 'Designation', 'Joining Date',
    'Base Salary (INR)', 'Overtime Pay (INR)', 'Bonus (INR)', 'Leave Deductions (INR)',
    'Late/Break/Manual Deductions (INR)', 'PF Deduction (INR)', 'Total Deductions (INR)',
    'Net Payable (INR)', 'Amount Paid (INR)', 'Pending Payment (INR)',
    'Payment Status', 'Last Payment Date',
  ];
  const csvRows = cleanReportItems.map((r) => [
    r.period,
    r.staffId,
    r.name,
    r.department,
    r.designation,
    r.joiningDate || '',
    r.baseSalary,
    r.overtimePay || 0,
    r.bonus,
    r.unpaidLeaveDeductions || 0,
    round2((r.lateDeduction || 0) + (r.breakDeduction || 0) + (r.shortfallDeduction || 0) + (r.manualDeduction || 0)),
    r.pfDeduction || 0,
    r.totalDeductions,
    r.totalAmount,
    r.amountPaid,
    r.pendingAmount,
    r.paymentStatus,
    r.lastPaidAt ? normalizeDateOnly(r.lastPaidAt) : '',
  ]);
  const summaryRow = [
    'TOTAL / COMPANY SUMMARY', '--', 'ALL RECORDS', '--', '--', '--',
    companyOverallBaseSalary, companyOverallOvertimePay, companyOverallBonuses,
    companyOverallLeaveDeductions,
    round2(companyOverallDeductions - companyOverallLeaveDeductions - companyOverallPfDeductions),
    companyOverallPfDeductions, companyOverallDeductions, companyTotalNetPayable,
    companyOverallAmountPaid, companyOverallPendingAmount,
    `Paid: ${fullyPaidEmployees} | Due: ${pendingEmployees}`, '',
  ];

  const csvContent = buildCsvDocument(
    [
      `# ${companyName} - Official Company Payment & Payroll Report`,
      `# Period: ${periodLabel}`,
      `# Generated on: ${new Date().toLocaleString()}`,
      `# COMPANY GRAND TOTALS: Paid: INR ${companyOverallAmountPaid.toLocaleString()} | Pending: INR ${companyOverallPendingAmount.toLocaleString()} | Bonuses: INR ${companyOverallBonuses.toLocaleString()} | Deductions: INR ${companyOverallDeductions.toLocaleString()}`,
    ],
    csvHeaders,
    [...csvRows, summaryRow],
  );

  const paged = paginateItems(cleanReportItems, queryParams);

  return {
    companyName,
    companyCreatedAt: companyCreatedDate,
    earliestRecordDate,
    period,
    periodLabel,
    startDate: window.startDate,
    endDate: window.endDate,
    totalEmployees,
    fullyPaidEmployees,
    pendingEmployees,
    companyOverallAmountPaid,
    companyOverallPendingAmount,
    companyOverallBonuses,
    companyOverallDeductions,
    companyOverallBaseSalary,
    companyTotalNetPayable,
    companyOverallOvertimePay,
    companyOverallLeaveDeductions,
    companyOverallPfDeductions,
    pfSupported,
    records: paged.items,
    pagination: paged.pagination,
    transactions: transactionRows,
    employees: userLookup.employeeOptions,
    departments: userLookup.departments,
    csvContent,
  };
};

/**
 * 13. Controller: Get Payment / Payroll Report
 */
export const getPayrollReport = async (req, res) => {
  try {
    const companyId = requireCompanyId(req, res, true);
    if (!companyId) return res.status(200).json({ rows: [], totals: {} });
    if (!isCompanyAdmin(req.user)) return res.status(403).json({ message: 'Access denied' });

    const report = await buildPayrollReportData(companyId, req.query);
    res.status(200).json(report);
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
};

/**
 * 14. Controller: Send Payment / Payroll Report via Email
 */
export const sendPayrollReport = async (req, res) => {
  try {
    const companyId = requireCompanyId(req, res);
    if (!companyId) return;
    if (!isCompanyAdmin(req.user)) return res.status(403).json({ message: 'Access denied' });

    const { recipientEmail, notes, ...filterParams } = req.body;
    if (!recipientEmail || !recipientEmail.trim()) {
      return res.status(400).json({ message: 'Recipient email is required' });
    }

    const report = await buildPayrollReportData(companyId, { ...filterParams, limit: 'all' });

    const summaryMetrics = [
      { label: 'Company Total Paid', value: `₹${report.companyOverallAmountPaid.toLocaleString()}` },
      { label: 'Company Total Pending', value: `₹${report.companyOverallPendingAmount.toLocaleString()}` },
      { label: 'Total Bonuses Disbursed', value: `+₹${report.companyOverallBonuses.toLocaleString()}` },
      { label: 'Total Deductions', value: `-₹${report.companyOverallDeductions.toLocaleString()}` },
      { label: 'Eligible Staff Count', value: `${report.totalEmployees}` },
      { label: 'Fully Settled Staff', value: `${report.fullyPaidEmployees} / ${report.totalEmployees}` },
    ];

    const filename = `Payment_Report_${report.companyName.replace(/[^a-zA-Z0-9]/g, '_')}_${report.periodLabel.replace(/[^a-zA-Z0-9]/g, '_')}.csv`;

    const mailResult = await sendReportEmail({
      to: recipientEmail.trim(),
      subject: `Payment & Payroll Report - ${report.companyName} (${report.periodLabel})`,
      companyName: report.companyName,
      reportType: 'Payment & Payroll Report',
      periodLabel: report.periodLabel,
      summaryMetrics,
      notes: notes ? String(notes).trim() : '',
      csvContent: report.csvContent,
      filename,
    });

    res.status(200).json({
      message: mailResult.simulated
        ? `Payment report prepared for ${recipientEmail} (Simulated send: SMTP not configured)`
        : `Payment report successfully sent to ${recipientEmail}`,
      mailResult,
      summary: {
        companyOverallAmountPaid: report.companyOverallAmountPaid,
        companyOverallPendingAmount: report.companyOverallPendingAmount,
        companyOverallBonuses: report.companyOverallBonuses,
        periodLabel: report.periodLabel,
      },
    });
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
};
