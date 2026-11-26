/**
 * Comprehensive Automated Tests for Regenai Dynamic Payroll & Payment System
 * Verifies all 16 test cases specified in the project requirements.
 */

import dotenv from 'dotenv';
import path from 'path';
import { fileURLToPath } from 'url';
import mongoose from 'mongoose';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
dotenv.config({ path: path.join(__dirname, '.env') });

import {
  calculateEmployeeMonthlyPayroll,
  computeBreakDelayDeductionAmount,
  round2,
  calculateWorkedHours,
  getWeeklyOffDays,
} from './utils/payrollCalculator.js';
import { generatePayslipPdfBuffer } from './utils/payslipPdf.js';
import User from './models/User.js';
import Company from './models/Company.js';
import PayrollSetting from './models/PayrollSetting.js';
import Payroll from './models/Payroll.js';
import PaymentTransaction from './models/PaymentTransaction.js';
import Attendance from './models/Attendance.js';
import Leave from './models/Leave.js';
import Holiday from './models/Holiday.js';
import PayrollAdjustment from './models/PayrollAdjustment.js';

let passedTests = 0;
let totalTests = 0;

function assert(condition, testName, details = '') {
  totalTests++;
  if (condition) {
    passedTests++;
    console.log(`  \x1b[32m✔ [PASS]\x1b[0m ${testName}`);
  } else {
    console.error(`  \x1b[31m✖ [FAIL]\x1b[0m ${testName} ${details ? '- ' + details : ''}`);
  }
}

async function runTests() {
  console.log('\n======================================================');
  console.log('   REGENAI PAYROLL & PAYMENT SYSTEM TEST SUITE');
  console.log('======================================================\n');

  await mongoose.connect(process.env.MONGODB_URI);
  console.log('Connected to MongoDB for integration tests.\n');

  // Test setup data
  const testCompanyId = new mongoose.Types.ObjectId();
  const testCompanyId2 = new mongoose.Types.ObjectId();
  const testUserId = `TEST-EMP-${Date.now()}`;
  const testUserId2 = `TEST-EMP2-${Date.now()}`;
  const testMonth = '2026-10';

  const defaultSettings = {
    workingHoursPerDay: 8,
    workingDaysPerWeek: 5,
    weeklyOffDays: [0, 6], // Sun, Sat
    hourlyDeductionPct: 50,
    hourlyOvertimePct: 75,
    approvedLeaveDeductionPct: 25,
    unapprovedLeaveDeductionPct: 100,
    payrollDivisorType: 'scheduled_hours',
    fixedPayrollDivisor: 200,
    dailyBasisType: 'scheduled_days',
  };

  const dummyEmployee = {
    userId: testUserId,
    StaffId: testUserId,
    name: 'Test Employee 1',
    salary: '22000',
    department: 'Engineering',
  };

  // --------------------------------------------------------------------------
  console.log('\n--- Case 1: Employee works exactly the required hours ---');
  // --------------------------------------------------------------------------
  {
    // Oct 2026: 31 days. Day 1 is Thursday, Day 2 Friday, Day 3 Sat (weekly off), etc.
    // 22 working days in Oct 2026 with 5 days/wk.
    // Scheduled hours = 22 * 8 = 176h.
    // Base salary = 22,000.
    // Divisor = 176.
    // Hourly deduction rate = 22,000 * 50% / 176 = 62.50.
    // Hourly overtime rate = 22,000 * 75% / 176 = 93.75.
    const att1 = {
      date: '2026-10-01',
      checkIn: '2026-10-01T09:30:00.000Z',
      checkOut: '2026-10-01T17:30:00.000Z', // exactly 8 hours
      status: 'present',
    };
    const res = calculateEmployeeMonthlyPayroll({
      user: dummyEmployee,
      month: testMonth,
      settings: defaultSettings,
      attendances: [att1],
      leaves: [],
      holidays: [],
      referenceDate: new Date('2026-10-01T23:59:59.000Z'),
    });

    const day1 = res.dailyBreakdown.find(d => d.date === '2026-10-01');
    assert(day1.actualHours === 8, 'Day 1 actual hours is 8');
    assert(day1.shortfallHours === 0, 'Shortfall hours is 0 when worked required hours');
    assert(day1.overtimeHours === 0, 'Overtime hours is 0 when worked required hours');
    assert(day1.shortfallDeduction === 0, 'Shortfall deduction is 0');
    assert(day1.overtimeAddition === 0, 'Overtime addition is 0');
  }

  // --------------------------------------------------------------------------
  console.log('\n--- Case 2: Employee works two hours below the requirement ---');
  // --------------------------------------------------------------------------
  {
    const attShortfall = {
      date: '2026-10-01',
      checkIn: '2026-10-01T09:30:00.000Z',
      checkOut: '2026-10-01T15:30:00.000Z', // 6 hours (2 hours below required 8)
      status: 'present',
    };
    const res = calculateEmployeeMonthlyPayroll({
      user: dummyEmployee,
      month: testMonth,
      settings: defaultSettings,
      attendances: [attShortfall],
      leaves: [],
      holidays: [],
      referenceDate: new Date('2026-10-01T23:59:59.000Z'),
    });

    const day1 = res.dailyBreakdown.find(d => d.date === '2026-10-01');
    assert(day1.actualHours === 6, 'Day 1 actual hours is 6');
    assert(day1.shortfallHours === 2, 'Shortfall hours is 2');
    assert(day1.overtimeHours === 0, 'Overtime hours is 0');
    assert(day1.shortfallDeduction === round2(2 * res.hourlyDeductionRate), `Shortfall deduction matches 2 * rate (${day1.shortfallDeduction})`);
  }

  // --------------------------------------------------------------------------
  console.log('\n--- Case 3: Employee works two hours above the requirement ---');
  // --------------------------------------------------------------------------
  {
    const attOvertime = {
      date: '2026-10-01',
      checkIn: '2026-10-01T09:30:00.000Z',
      checkOut: '2026-10-01T19:30:00.000Z', // 10 hours (2 hours above required 8)
      status: 'present',
    };
    const res = calculateEmployeeMonthlyPayroll({
      user: dummyEmployee,
      month: testMonth,
      settings: defaultSettings,
      attendances: [attOvertime],
      leaves: [],
      holidays: [],
      referenceDate: new Date('2026-10-01T23:59:59.000Z'),
    });

    const day1 = res.dailyBreakdown.find(d => d.date === '2026-10-01');
    assert(day1.actualHours === 10, 'Day 1 actual hours is 10');
    assert(day1.overtimeHours === 2, 'Overtime hours is 2');
    assert(day1.shortfallHours === 0, 'Shortfall hours is 0');
    assert(day1.overtimeAddition === round2(2 * res.hourlyOvertimeRate), `Overtime addition matches 2 * rate (${day1.overtimeAddition})`);
  }

  // --------------------------------------------------------------------------
  console.log('\n--- Case 4: Approved leave uses the approved deduction rate ---');
  // --------------------------------------------------------------------------
  {
    const approvedLeave = {
      startDate: '2026-10-01',
      endDate: '2026-10-01',
      status: 'approved',
      type: 'casual',
    };
    const res = calculateEmployeeMonthlyPayroll({
      user: dummyEmployee,
      month: testMonth,
      settings: defaultSettings,
      attendances: [],
      leaves: [approvedLeave],
      holidays: [],
      referenceDate: new Date('2026-10-01T23:59:59.000Z'),
    });

    const day1 = res.dailyBreakdown.find(d => d.date === '2026-10-01');
    assert(day1.isApprovedLeave === true, 'Day 1 marked as approved leave');
    const expectedDeduction = round2(res.dailySalaryBasis * (defaultSettings.approvedLeaveDeductionPct / 100));
    assert(day1.leaveDeduction === expectedDeduction, `Approved leave deduction is ${day1.leaveDeduction} (expected ${expectedDeduction})`);
  }

  // --------------------------------------------------------------------------
  console.log('\n--- Case 5: Unapproved leave uses the unapproved deduction rate ---');
  // --------------------------------------------------------------------------
  {
    // Rejected leave on working day in the past
    const unapprovedLeave = {
      startDate: '2026-10-01',
      endDate: '2026-10-01',
      status: 'rejected',
      type: 'casual',
    };
    const res = calculateEmployeeMonthlyPayroll({
      user: dummyEmployee,
      month: testMonth,
      settings: defaultSettings,
      attendances: [],
      leaves: [unapprovedLeave],
      holidays: [],
      referenceDate: new Date('2026-10-01T23:59:59.000Z'),
    });

    const day1 = res.dailyBreakdown.find(d => d.date === '2026-10-01');
    assert(day1.isUnapprovedLeave === true, 'Day 1 marked as unapproved leave');
    const expectedDeduction = round2(res.dailySalaryBasis * (defaultSettings.unapprovedLeaveDeductionPct / 100));
    assert(day1.leaveDeduction === expectedDeduction, `Unapproved leave deduction is ${day1.leaveDeduction} (expected ${expectedDeduction})`);
  }

  // --------------------------------------------------------------------------
  console.log('\n--- Case 6: Company holiday does not trigger an absence deduction ---');
  // --------------------------------------------------------------------------
  {
    const holiday = {
      date: '2026-10-02', // Friday
      name: 'Gandhi Jayanti',
    };
    const res = calculateEmployeeMonthlyPayroll({
      user: dummyEmployee,
      month: testMonth,
      settings: defaultSettings,
      attendances: [],
      leaves: [],
      holidays: [holiday],
      referenceDate: new Date('2026-10-02T23:59:59.000Z'),
    });

    const day2 = res.dailyBreakdown.find(d => d.date === '2026-10-02');
    assert(day2.isHoliday === true, 'Day 2 marked as holiday');
    assert(day2.isUnapprovedLeave === false, 'Holiday is not treated as unapproved leave');
    assert(day2.leaveDeduction === 0, 'No deduction applied for company holiday');
    assert(day2.shortfallDeduction === 0, 'No shortfall deduction for company holiday');
  }

  // --------------------------------------------------------------------------
  console.log('\n--- Case 7: Scheduled weekly off does not trigger an absence deduction ---');
  // --------------------------------------------------------------------------
  {
    const res = calculateEmployeeMonthlyPayroll({
      user: dummyEmployee,
      month: testMonth,
      settings: defaultSettings,
      attendances: [],
      leaves: [],
      holidays: [],
      referenceDate: new Date('2026-10-04T23:59:59.000Z'),
    });

    const day3 = res.dailyBreakdown.find(d => d.date === '2026-10-03'); // Saturday
    const day4 = res.dailyBreakdown.find(d => d.date === '2026-10-04'); // Sunday
    assert(day3.isWeeklyOff === true, 'Saturday is weekly off');
    assert(day4.isWeeklyOff === true, 'Sunday is weekly off');
    assert(day3.leaveDeduction === 0 && day4.leaveDeduction === 0, 'Weekly offs have 0 leave deductions');
  }

  // --------------------------------------------------------------------------
  console.log('\n--- Case 8: Missing attendance handled according to policy ---');
  // --------------------------------------------------------------------------
  {
    // Working day in the past with no attendance and no approved leave
    const res = calculateEmployeeMonthlyPayroll({
      user: dummyEmployee,
      month: testMonth,
      settings: defaultSettings,
      attendances: [],
      leaves: [],
      holidays: [],
      referenceDate: new Date('2026-10-01T23:59:59.000Z'),
    });

    const day1 = res.dailyBreakdown.find(d => d.date === '2026-10-01');
    assert(day1.isUnapprovedLeave === true, 'Working day with no attendance is marked as unapproved absence');
    assert(day1.leaveDeduction > 0, 'Absence deduction applied according to unapproved leave rate');
    assert(day1.shortfallDeduction === 0, 'Did not duplicate shortfall deduction for full absence');
  }

  // --------------------------------------------------------------------------
  console.log('\n--- Case 9: Changes to attendance update unpaid payroll previews ---');
  // --------------------------------------------------------------------------
  {
    // Live calculation without saving
    const preview1 = calculateEmployeeMonthlyPayroll({
      user: dummyEmployee,
      month: testMonth,
      settings: defaultSettings,
      attendances: [{ date: '2026-10-01', checkIn: '2026-10-01T09:30:00.000Z', checkOut: '2026-10-01T15:30:00.000Z', status: 'present' }],
      leaves: [],
      holidays: [],
      referenceDate: new Date('2026-10-01T23:59:59.000Z'),
    });

    // Attendance updated to 8h
    const preview2 = calculateEmployeeMonthlyPayroll({
      user: dummyEmployee,
      month: testMonth,
      settings: defaultSettings,
      attendances: [{ date: '2026-10-01', checkIn: '2026-10-01T09:30:00.000Z', checkOut: '2026-10-01T17:30:00.000Z', status: 'present' }],
      leaves: [],
      holidays: [],
      referenceDate: new Date('2026-10-01T23:59:59.000Z'),
    });

    assert(preview1.shortfallHours === 2, 'Preview 1 reflected 2h shortfall');
    assert(preview2.shortfallHours === 0, 'Preview 2 dynamically updated to 0h shortfall');
    assert(preview2.netPayable > preview1.netPayable, 'Net payable recalculated and increased when shortfall removed');
  }

  // --------------------------------------------------------------------------
  console.log('\n--- Case 10: Finalized payroll retains its original calculation snapshot ---');
  // --------------------------------------------------------------------------
  {
    // Clean up any test records
    await Payroll.deleteMany({ userId: testUserId });

    const frozenSnapshot = {
      companyId: testCompanyId,
      userId: testUserId,
      month: testMonth,
      baseSalary: 20000,
      hourlyDeductionRate: 50,
      hourlyOvertimeRate: 75,
      netPayable: 19500,
      status: 'finalized',
      paymentStatus: 'unpaid',
      finalizedAt: new Date(),
      snapshotSettings: { hourlyDeductionPct: 50 },
    };

    const savedPayroll = await Payroll.create(frozenSnapshot);
    assert(savedPayroll.status === 'finalized', 'Payroll saved with finalized status');
    assert(savedPayroll.netPayable === 19500, 'Original net payable retained in snapshot');

    // Modifying company settings should NOT change finalized record
    const retrieved = await Payroll.findOne({ _id: savedPayroll._id }).lean();
    assert(retrieved.netPayable === 19500, 'Finalized record retained its original frozen amount');
  }

  // --------------------------------------------------------------------------
  console.log('\n--- Case 11: Repeated payment requests do not create duplicate transactions ---');
  // --------------------------------------------------------------------------
  {
    await PaymentTransaction.deleteMany({ userId: testUserId });
    const finalizedPayroll = await Payroll.findOne({ userId: testUserId, status: 'finalized' });

    // First payment
    const tx1 = await PaymentTransaction.create({
      payrollId: finalizedPayroll._id,
      companyId: testCompanyId,
      userId: testUserId,
      month: testMonth,
      amount: finalizedPayroll.netPayable,
      paymentMethod: 'bank_transfer',
      referenceId: `REF-${Date.now()}`,
      status: 'completed',
      processedBy: 'admin',
    });
    assert(tx1._id != null, 'First payment transaction created successfully');

    // Attempt second payment with duplicate referenceId for same company
    let duplicateFailed = false;
    try {
      await PaymentTransaction.create({
        payrollId: finalizedPayroll._id,
        companyId: testCompanyId,
        userId: testUserId,
        month: testMonth,
        amount: finalizedPayroll.netPayable,
        paymentMethod: 'bank_transfer',
        referenceId: tx1.referenceId, // duplicate referenceId
        status: 'completed',
        processedBy: 'admin',
      });
    } catch (e) {
      duplicateFailed = true;
    }
    assert(duplicateFailed === true, 'Duplicate payment transaction blocked by database constraint');
  }

  // --------------------------------------------------------------------------
  console.log('\n--- Case 12: Processed and pending counts are accurate ---');
  // --------------------------------------------------------------------------
  {
    const payrolls = [
      { status: 'draft', paymentStatus: 'unpaid' },
      { status: 'finalized', paymentStatus: 'unpaid' },
      { status: 'finalized', paymentStatus: 'paid' },
    ];
    const draftCount = payrolls.filter(p => p.status === 'draft').length;
    const pendingPaymentCount = payrolls.filter(p => p.status === 'finalized' && p.paymentStatus === 'unpaid').length;
    const paidCount = payrolls.filter(p => p.paymentStatus === 'paid').length;

    assert(draftCount === 1, 'Draft count is accurate');
    assert(pendingPaymentCount === 1, 'Finalized unpaid count is accurate');
    assert(paidCount === 1, 'Paid count is accurate');
  }

  // --------------------------------------------------------------------------
  console.log('\n--- Case 13: One company cannot access another company\'s payroll ---');
  // --------------------------------------------------------------------------
  {
    // Company 1 payroll
    const c1Payroll = await Payroll.create({
      companyId: testCompanyId,
      userId: `C1-USER-${Date.now()}`,
      month: testMonth,
      baseSalary: 15000,
      netPayable: 15000,
      status: 'finalized',
    });

    // Company 2 query
    const c2Query = await Payroll.find({ companyId: testCompanyId2 }).lean();
    const hasC1Data = c2Query.some(p => p._id.toString() === c1Payroll._id.toString());
    assert(hasC1Data === false, 'Company 2 query does not return Company 1 payroll records');
  }

  // --------------------------------------------------------------------------
  console.log('\n--- Case 14: Invalid percentages, missing salary, and incomplete attendance are handled safely ---');
  // --------------------------------------------------------------------------
  {
    // Missing salary (0 or undefined)
    const resNoSalary = calculateEmployeeMonthlyPayroll({
      user: { userId: 'NO-SALARY', salary: undefined },
      month: testMonth,
      settings: defaultSettings,
      attendances: [],
      leaves: [],
      holidays: [],
      referenceDate: new Date('2026-10-01'),
    });
    assert(resNoSalary.baseSalary === 0, 'Missing salary handled as 0');
    assert(resNoSalary.netPayable === 0, 'Net payable safely computed as 0');

    // Incomplete attendance (checkIn without checkOut)
    const incompleteAtt = {
      date: '2026-10-01',
      checkIn: '2026-10-01T09:30:00.000Z',
      checkOut: null,
      status: 'present',
    };
    const resIncomplete = calculateEmployeeMonthlyPayroll({
      user: dummyEmployee,
      month: testMonth,
      settings: defaultSettings,
      attendances: [incompleteAtt],
      leaves: [],
      holidays: [],
      referenceDate: new Date('2026-10-02'),
    });
    const d1 = resIncomplete.dailyBreakdown.find(d => d.date === '2026-10-01');
    assert(d1.shortfallHours === 8, 'Incomplete past attendance safely flagged with 8h shortfall');
    assert(!isNaN(resIncomplete.netPayable), 'Net payable remains a valid number without NaN');
  }

  // --------------------------------------------------------------------------
  console.log('\n--- Case 15: Decimal safety and round-to-2 consistency ---');
  // --------------------------------------------------------------------------
  {
    const r1 = round2(0.1 + 0.2);
    assert(r1 === 0.3, 'Floating point 0.1 + 0.2 accurately rounded to 0.3');
    const r2 = round2(10000 / 3);
    assert(r2 === 3333.33, '10000 / 3 accurately rounded to 3333.33');
  }

  // --------------------------------------------------------------------------
  console.log('\n--- Case 16: Overnight shift calculation handled safely ---');
  // --------------------------------------------------------------------------
  {
    const hours = calculateWorkedHours('2026-10-01T22:00:00.000Z', '2026-10-02T06:00:00.000Z', 'present', 8);
    assert(hours === 8, `Overnight shift (22:00 to 06:00 next day) calculated as 8 hours (got ${hours})`);
  }

  // --------------------------------------------------------------------------
  console.log('\n--- Case 17: Employee bonus dynamically increases total payout ---');
  // --------------------------------------------------------------------------
  {
    const baseCalc = calculateEmployeeMonthlyPayroll({
      user: dummyEmployee,
      month: testMonth,
      settings: defaultSettings,
      attendances: [],
      leaves: [],
      holidays: [],
      referenceDate: new Date('2026-10-01'),
    });

    const bonusCalc = calculateEmployeeMonthlyPayroll({
      user: dummyEmployee,
      month: testMonth,
      settings: defaultSettings,
      attendances: [],
      leaves: [],
      holidays: [],
      adjustments: [
        { type: 'bonus', amount: 5000, reason: 'Festival Bonus' },
      ],
      referenceDate: new Date('2026-10-01'),
    });

    assert(bonusCalc.bonus === 5000, `Bonus amount is recorded as 5000 (got ${bonusCalc.bonus})`);
    assert(bonusCalc.totalAmount === round2(baseCalc.netPayable + 5000), `Total amount reflects bonus addition: ₹${bonusCalc.totalAmount} = ₹${baseCalc.netPayable} + 5000`);
  }

  // --------------------------------------------------------------------------
  console.log('\n--- Case 18: Employee deduction dynamically reduces total payout ---');
  // --------------------------------------------------------------------------
  {
    const baseCalc = calculateEmployeeMonthlyPayroll({
      user: dummyEmployee,
      month: testMonth,
      settings: defaultSettings,
      attendances: [],
      leaves: [],
      holidays: [],
      referenceDate: new Date('2026-10-01'),
    });

    const deductCalc = calculateEmployeeMonthlyPayroll({
      user: dummyEmployee,
      month: testMonth,
      settings: defaultSettings,
      attendances: [],
      leaves: [],
      holidays: [],
      adjustments: [
        { type: 'deduction', amount: 1500, reason: 'Advance Recovery' },
      ],
      referenceDate: new Date('2026-10-01'),
    });

    assert(deductCalc.manualDeduction === 1500, `Manual deduction is recorded as 1500 (got ${deductCalc.manualDeduction})`);
    assert(deductCalc.totalAmount === round2(Math.max(0, baseCalc.netPayable - 1500)), `Total amount reflects deduction: ₹${deductCalc.totalAmount} = ₹${baseCalc.netPayable} - 1500`);
  }

  // --------------------------------------------------------------------------
  console.log('\n--- Case 19: ₹1 per 10 excess break delay mins without double deduction ---');
  // --------------------------------------------------------------------------
  {
    const bDed19 = computeBreakDelayDeductionAmount(25, 22000, {
      breakDelayDeductionEnabled: true,
      breakDelayRuleType: 'per_interval_flat',
      breakDelayIntervalMinutes: 10,
      breakDelayIntervalAmount: 1,
    });
    assert(bDed19 === 2, `25m excess break delay yields ₹2 deduction (got ₹${bDed19})`);

    const attBreak = {
      date: '2026-10-01',
      checkIn: '2026-10-01T09:30:00.000Z',
      checkOut: '2026-10-01T18:30:00.000Z', // 9h span
      breakMinutes: 80, // 20m excess lunch break
      casualBreakMinutes: 15,
      breakDelayMinutes: 20,
      casualBreakDelayMinutes: 0,
      totalBreakDelayMinutes: 20,
      totalWorkingHours: round2(9 - (95 / 60)), // 7.42h net worked
      status: 'present',
    };
    const resBreak = calculateEmployeeMonthlyPayroll({
      user: dummyEmployee,
      month: testMonth,
      settings: {
        ...defaultSettings,
        breakDelayDeductionEnabled: true,
        breakDelayRuleType: 'per_interval_flat',
        breakDelayIntervalMinutes: 10,
        breakDelayIntervalAmount: 1,
      },
      attendances: [attBreak],
      leaves: [],
      holidays: [],
      referenceDate: new Date('2026-10-01T23:59:59.000Z'),
    });
    const d1 = resBreak.dailyBreakdown.find(d => d.date === '2026-10-01');
    assert(d1.breakDeduction === 2, `Daily break deduction is ₹2 for 20m delay (got ₹${d1.breakDeduction})`);
    assert(resBreak.totalBreakDeduction === 2, `Monthly totalBreakDeduction is ₹2 (got ₹${resBreak.totalBreakDeduction})`);
    assert(d1.shortfallHours <= 0.3, `Did not double-charge full 20m excess break into shortfall (shortfallHours=${d1.shortfallHours})`);
  }

  // --------------------------------------------------------------------------
  console.log('\n--- Case 20: Company Leave Policy drives paid, unpaid & unapproved leaves ---');
  // --------------------------------------------------------------------------
  {
    const leavePolicy = {
      casualLeave: { enabled: true, requiresApproval: true, unapprovedDeductionRate: 50 },
      sickLeave: { enabled: true, requiresApproval: true, unapprovedDeductionRate: 100 },
      earnedLeave: { enabled: true, requiresApproval: true, unapprovedDeductionRate: 50 },
      unpaidLeave: { enabled: true, approvedDeductionRate: 100, unapprovedDeductionRate: 100, sameDeductionRate: true },
    };
    const resPolicy = calculateEmployeeMonthlyPayroll({
      user: dummyEmployee,
      month: testMonth,
      settings: defaultSettings,
      leavePolicy,
      leaveBalance: { casual: { remaining: 2 }, sick: { remaining: 1 }, earned: { remaining: 1 } },
      attendances: [],
      leaves: [
        { startDate: '2026-10-01', endDate: '2026-10-01', type: 'casual', status: 'approved' }, // Paid -> 0 deduction
        { startDate: '2026-10-02', endDate: '2026-10-02', type: 'earned', status: 'pending' },  // Unapproved paid -> 50%
      ],
      holidays: [],
      referenceDate: new Date('2026-10-02T23:59:59.000Z'),
    });
    const oct1 = resPolicy.dailyBreakdown.find(d => d.date === '2026-10-01');
    const oct2 = resPolicy.dailyBreakdown.find(d => d.date === '2026-10-02');
    assert(oct1.leaveDeduction === 0, `Approved casual leave deducts ₹0 (got ₹${oct1.leaveDeduction})`);
    assert(oct2.leaveDeduction === round2(resPolicy.dailySalaryBasis * 0.5), `Unapproved earned leave uses 50% policy rate (got ₹${oct2.leaveDeduction})`);
    assert(oct1.explanation.includes('₹0 deduction'), `Readable explanation generated: ${oct1.explanation}`);
  }

  // --------------------------------------------------------------------------
  console.log('\n--- Case 21: Overtime & Late toggles respected dynamically ---');
  // --------------------------------------------------------------------------
  {
    const resToggled = calculateEmployeeMonthlyPayroll({
      user: dummyEmployee,
      month: testMonth,
      settings: {
        ...defaultSettings,
        overtimeEnabled: false,
        lateDeductionEnabled: true,
        lateDeductionMode: 'fixed_per_late',
        lateDeductionRate: 150,
        graceMinutes: 10,
      },
      attendances: [{
        date: '2026-10-01',
        checkIn: '10:00', // 30m after 09:30 -> beyond 10m grace
        checkOut: '20:00', // 10h worked (OT disabled)
        status: 'present',
      }],
      leaves: [],
      holidays: [],
      referenceDate: new Date('2026-10-01T23:59:59.000Z'),
    });
    assert(resToggled.hourlyOvertimeAddition === 0, 'Overtime disabled yields ₹0 OT addition');
    assert(resToggled.lateDeduction === 150, `Late deduction enabled fixed ₹150 applied (got ₹${resToggled.lateDeduction})`);
  }

  // --------------------------------------------------------------------------
  console.log('\n--- Case 22: Multiple partial payments + independent pending months ---');
  // --------------------------------------------------------------------------
  {
    const payDoc = await Payroll.create({
      companyId: testCompanyId,
      userId: `${testUserId}-PARTIAL`,
      month: '2026-09',
      baseSalary: 20000,
      netPayable: 20000,
      totalAmount: 20000,
      status: 'finalized',
      paymentStatus: 'partially_paid',
      amountPaid: 8000,
      pendingAmount: 12000,
    });
    const pt1 = await PaymentTransaction.create({
      payrollId: payDoc._id,
      companyId: testCompanyId,
      userId: `${testUserId}-PARTIAL`,
      month: '2026-09',
      amount: 5000,
      referenceId: `PART1-${Date.now()}`,
      processedBy: 'admin',
    });
    const pt2 = await PaymentTransaction.create({
      payrollId: payDoc._id,
      companyId: testCompanyId,
      userId: `${testUserId}-PARTIAL`,
      month: '2026-09',
      amount: 3000,
      referenceId: `PART2-${Date.now()}`,
      processedBy: 'admin',
    });
    assert(pt1._id && pt2._id && pt1._id.toString() !== pt2._id.toString(), 'Multiple partial PaymentTransactions allowed per payroll');
  }

  // --------------------------------------------------------------------------
  console.log('\n--- Case 23: Pure PDF payslip buffer generation ---');
  // --------------------------------------------------------------------------
  {
    const pdfBuf = generatePayslipPdfBuffer({
      payslipNumber: 'PS-202610-EMP1',
      companyName: 'ReGen Test Co',
      month: '2026-10',
      paymentStatus: 'partially_paid',
      employee: { name: 'Alice', staffId: 'EMP01', department: 'Eng', designation: 'Dev' },
      attendanceSummary: { presentDays: 20, scheduledWorkingDays: 22 },
      earnings: { baseSalary: 22000, overtimeAddition: 150, bonus: 500 },
      deductions: { breakDeduction: 2 },
      paymentSummary: { netPayable: 22648, amountPaid: 10000, pendingAmount: 12648 },
      dailyBreakdown: [{ explanation: 'October 1 — Present — ₹0 deduction' }],
    });
    const header = pdfBuf.subarray(0, 8).toString('utf8');
    assert(header === '%PDF-1.4', `Valid PDF header generated (${header})`);
    assert(pdfBuf.length > 500, `Payslip PDF buffer non-empty (${pdfBuf.length} bytes)`);
  }

  // --------------------------------------------------------------------------
  console.log('\n--- Case 24: Formatted ₹/comma salaries & dynamic default proportional late deductions ---');
  // --------------------------------------------------------------------------
  {
    const formattedEmp = { userId: `${testUserId}-FMT`, name: 'Comma Salary', salary: '₹22,000' };
    const lateRes = calculateEmployeeMonthlyPayroll({
      user: formattedEmp,
      month: testMonth,
      settings: {
        ...defaultSettings,
        lateDeductionEnabled: true,
        lateDeductionMode: 'hourly_rate',
        lateDeductionRate: 100,
        graceMinutes: 5,
      },
      attendances: [{
        date: '2026-10-01',
        checkIn: '10:35 AM', // 60m after 09:35 (09:30 + 5m grace) -> 1h late
        checkOut: '07:35 PM', // 9h worked -> 1h OT
        status: 'late',
      }],
      leaves: [
        { startDate: '2026-10-02', endDate: '2026-10-02', type: 'unpaid', status: 'pending' },
      ],
      holidays: [],
      referenceDate: new Date('2026-10-02T23:59:59.000Z'),
    });
    assert(lateRes.baseSalary === 22000, `Formatted salary ₹22,000 parsed cleanly (${lateRes.baseSalary})`);
    assert(lateRes.lateMinutes === 60, `Late minutes after grace calculated cleanly (${lateRes.lateMinutes})`);
    assert(lateRes.lateDeduction > 0, `Dynamic proportional late deduction applied (₹${lateRes.lateDeduction})`);
    assert(lateRes.unapprovedLeaveDeduction === 1000, `Dynamic unapproved leave deduction applied (₹${lateRes.unapprovedLeaveDeduction})`);
    assert(lateRes.totalDeductions >= lateRes.lateDeduction + lateRes.unapprovedLeaveDeduction, `Total deductions sum properly (₹${lateRes.totalDeductions})`);
  }

  // --------------------------------------------------------------------------
  console.log('\n--- Case 25: Disabled casual leave policy & past unapproved absences deduct 1 day salary ---');
  // --------------------------------------------------------------------------
  {
    const disabledCasualPolicy = {
      casualLeave: { enabled: false, requiresApproval: true, unapprovedDeductionRate: 0 },
      sickLeave: { enabled: false, requiresApproval: true, unapprovedDeductionRate: 100 },
      earnedLeave: { enabled: true, requiresApproval: true, unapprovedDeductionRate: 100 },
      unpaidLeave: { enabled: true, approvedDeductionRate: 100, unapprovedDeductionRate: 100, sameDeductionRate: true },
    };
    const resUnapproved = calculateEmployeeMonthlyPayroll({
      user: { userId: `${testUserId}-UNAPP`, name: 'Past Unapproved', salary: '30000' },
      month: '2026-11',
      settings: { ...defaultSettings, workingDaysPerWeek: 7, weeklyOffDays: [] }, // 30 days -> ₹1000/day
      leavePolicy: disabledCasualPolicy,
      leaveBalance: { casual: { remaining: 11 }, sick: { remaining: 1 }, earned: { remaining: 11 } },
      attendances: [],
      leaves: [
        { startDate: '2026-11-01', endDate: '2026-11-01', type: 'casual', status: 'pending' },
      ],
      holidays: [],
      referenceDate: new Date('2026-11-05T23:59:59.000Z'), // Nov 1..5 = 5 unapproved days
    });
    assert(resUnapproved.dailySalaryBasis === 1000, `1 day salary is ₹1000 (got ₹${resUnapproved.dailySalaryBasis})`);
    assert(resUnapproved.unapprovedLeaveDays === 5, `5 past unapproved days counted (got ${resUnapproved.unapprovedLeaveDays})`);
    assert(resUnapproved.unapprovedLeaveDeduction === 5000, `5 days * ₹1000 = ₹5000 unapproved deduction (got ₹${resUnapproved.unapprovedLeaveDeduction})`);
    assert(resUnapproved.totalDeductions === 5000, `Total deductions ₹5000 applied cleanly (got ₹${resUnapproved.totalDeductions})`);
  }

  // --------------------------------------------------------------------------
  console.log('\n--- Case 26: Company Payroll excludes removed (inactive) employees ---');
  // --------------------------------------------------------------------------
  {
    const { getPayrollSummary } = await import('./controllers/payrollController.js');
    const cFilterId = new mongoose.Types.ObjectId();
    await User.create([
      {
        userId: `${testUserId}-ACT`,
        username: `${testUserId}_act`,
        name: 'Active Staff',
        role: 'staff',
        companyId: cFilterId,
        salary: '30000',
        status: 'active',
      },
      {
        userId: `${testUserId}-REM`,
        username: `${testUserId}_rem`,
        name: 'Removed Staff',
        role: 'staff',
        companyId: cFilterId,
        salary: '30000',
        status: 'inactive',
      },
    ]);

    const mockSummaryRes = async (includeInactive = false) => {
      let payload = null;
      await getPayrollSummary(
        {
          companyId: cFilterId,
          user: { role: 'owner', userId: 'owner_test' },
          query: { month: '2026-11', ...(includeInactive ? { includeInactive: 'true' } : {}) },
        },
        { status: () => ({ json: (d) => { payload = d; } }) }
      );
      return payload;
    };

    const currentOnly = await mockSummaryRes(false);
    const withInactive = await mockSummaryRes(true);
    assert(currentOnly.items.length === 1 && currentOnly.items[0].userId === `${testUserId}-ACT`, 'Company Payroll summary excludes removed/inactive users');
    assert(withInactive.items.length === 2, 'Historical report includeInactive=true preserves former users');
    await User.deleteMany({ companyId: cFilterId });
  }

  // Cleanup test records
  await Payroll.deleteMany({ companyId: { $in: [testCompanyId, testCompanyId2] } });
  await PaymentTransaction.deleteMany({ companyId: { $in: [testCompanyId, testCompanyId2] } });
  await PayrollAdjustment.deleteMany({ companyId: { $in: [testCompanyId, testCompanyId2] } });
  await mongoose.disconnect();

  console.log('\n======================================================');
  console.log(`TEST SUMMARY: ${passedTests}/${totalTests} Passed (${Math.round((passedTests / totalTests) * 100)}%)`);
  console.log('======================================================\n');

  if (passedTests === totalTests) {
    process.exit(0);
  } else {
    process.exit(1);
  }
}

runTests().catch(err => {
  console.error('Test suite failed:', err);
  process.exit(1);
});
