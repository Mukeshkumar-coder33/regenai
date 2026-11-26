import assert from 'node:assert/strict';
import dotenv from 'dotenv';
import path from 'path';
import { fileURLToPath } from 'url';
import mongoose from 'mongoose';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
dotenv.config({ path: path.join(__dirname, '.env') });

import {
  assertCompanyReportAccess,
  resolveReportWindow,
  isDateInWindow,
  parseDateBreakdown,
  paginateItems,
  buildCsvDocument,
} from './utils/reportHelpers.js';
import Company from './models/Company.js';
import User from './models/User.js';
import Attendance from './models/Attendance.js';
import Leave from './models/Leave.js';
import Holiday from './models/Holiday.js';
import PayrollSetting from './models/PayrollSetting.js';
import Payroll from './models/Payroll.js';
import PayrollAdjustment from './models/PayrollAdjustment.js';
import PaymentTransaction from './models/PaymentTransaction.js';
import Task from './models/Task.js';
import Project from './models/Project.js';
import { buildAttendanceReportData } from './controllers/attendanceController.js';
import { buildPayrollReportData } from './controllers/payrollController.js';
import { buildSchedulesReportData } from './controllers/taskController.js';
import { buildProjectReportData } from './controllers/projectController.js';

let passed = 0;
const test = async (name, fn) => {
  await fn();
  passed += 1;
  console.log(`PASS: ${name}`);
};

const makeResMock = () => {
  const res = { statusCode: 200, body: null };
  res.status = (code) => {
    res.statusCode = code;
    return res;
  };
  res.json = (payload) => {
    res.body = payload;
    return res;
  };
  return res;
};

await test('Tenant & RBAC guard rejects missing companyId and non-admin employees', () => {
  const resMissing = makeResMock();
  assert.equal(assertCompanyReportAccess({ user: { role: 'owner' } }, resMissing), false);
  assert.equal(resMissing.statusCode, 400);

  const resStaff = makeResMock();
  assert.equal(
    assertCompanyReportAccess({ companyId: 'comp_1', user: { role: 'staff' } }, resStaff),
    false,
  );
  assert.equal(resStaff.statusCode, 403);

  const resOwner = makeResMock();
  assert.equal(
    assertCompanyReportAccess({ companyId: 'comp_1', user: { role: 'owner' } }, resOwner),
    true,
  );
});

await test('resolveReportWindow resolves all, range, day, month, and year accurately', () => {
  const allWin = resolveReportWindow({ period: 'all' }, '2023-05-01');
  assert.equal(allWin.period, 'all');
  assert.equal(allWin.startDate, '2023-05-01');
  assert.equal(isDateInWindow('2023-05-01', allWin), true);
  assert.equal(isDateInWindow('2022-12-31', allWin), false);

  const rangeWin = resolveReportWindow({
    period: 'range',
    startDate: '2024-02-01',
    endDate: '2024-03-15',
  });
  assert.equal(rangeWin.startDate, '2024-02-01');
  assert.equal(rangeWin.endDate, '2024-03-15');
  assert.equal(isDateInWindow('2024-02-20', rangeWin), true);
  assert.equal(isDateInWindow('2024-04-01', rangeWin), false);

  const monthWin = resolveReportWindow({ period: 'month', month: '2024-02' });
  assert.equal(monthWin.startDate, '2024-02-01');
  assert.equal(monthWin.endDate, '2024-02-29');

  const yearWin = resolveReportWindow({ period: 'year', year: '2025' });
  assert.equal(yearWin.startDate, '2025-01-01');
  assert.equal(yearWin.endDate, '2025-12-31');
});

await test('parseDateBreakdown computes weekday, month, and year', () => {
  const d = parseDateBreakdown('2026-11-25');
  assert.equal(d.weekday, 'Wednesday');
  assert.equal(d.month, '2026-11');
  assert.equal(d.year, '2026');
});

await test('paginateItems and buildCsvDocument behave deterministically', () => {
  const arr = Array.from({ length: 60 }, (_, i) => ({ id: i + 1 }));
  const full = paginateItems(arr, {});
  assert.equal(full.items.length, 60);

  const p2 = paginateItems(arr, { page: '2', limit: '25' });
  assert.equal(p2.items.length, 25);
  assert.equal(p2.items[0].id, 26);
  assert.equal(p2.pagination.totalPages, 3);

  const csv = buildCsvDocument(['# Test'], ['Name', 'Notes'], [['Alice, Bob', 'Said "Hi"']]);
  assert.equal(csv.includes('"Alice, Bob"'), true);
  assert.equal(csv.includes('"Said ""Hi"""'), true);
});

// End-to-End MongoDB Integration Tests across all 4 historical report builders
const mongoUri = process.env.MONGO_URI || process.env.MONGODB_URI;
if (mongoUri) {
  await mongoose.connect(mongoUri);
  const tag = `rep_test_${Date.now()}`;
  let comp1 = null;
  let comp2 = null;

  try {
    comp1 = await Company.create({
      name: `ReportTestCo ${tag}`,
      phoneNumber: '9000000001',
      city: 'Chennai',
      ownerId: `owner_${tag}`,
    });
    comp2 = await Company.create({
      name: `OtherIsolationCo ${tag}`,
      phoneNumber: '9000000002',
      city: 'Bengaluru',
      ownerId: `owner2_${tag}`,
    });

    await PayrollSetting.create({
      companyId: comp1._id,
      checkInTime: '09:30',
      checkOutTime: '18:30',
      workingHoursPerDay: 8,
      graceMinutes: 5,
    });

    await User.create([
      {
        userId: `u1_${tag}`,
        StaffId: `EMP1_${tag}`,
        username: `u1_${tag}`,
        name: 'Kavin Active',
        role: 'staff',
        companyId: comp1._id,
        department: 'Engineering',
        designation: 'Senior Dev',
        salary: '50000',
        status: 'active',
        joiningDate: '2024-01-15',
      },
      {
        userId: `u2_${tag}`,
        StaffId: `EMP2_${tag}`,
        username: `u2_${tag}`,
        name: 'Meera Former',
        role: 'staff',
        companyId: comp1._id,
        department: 'Design',
        designation: 'UI Lead',
        salary: '40000',
        status: 'inactive',
        joiningDate: '2023-06-01',
      },
      {
        userId: `u_other_${tag}`,
        StaffId: `OTHER_${tag}`,
        username: `u_other_${tag}`,
        name: 'Other Tenant User',
        role: 'staff',
        companyId: comp2._id,
        department: 'Sales',
      },
    ]);

    await Attendance.create([
      {
        id: `att1_${tag}`,
        companyId: comp1._id,
        userId: `u1_${tag}`,
        date: '2024-02-10',
        status: 'late',
        checkIn: '2024-02-10T10:00:00.000Z',
        checkOut: '2024-02-10T19:30:00.000Z',
        totalWorkingHours: 9.5,
        workingHours: 9.5,
        breakMinutes: 60,
        casualBreakMinutes: 15,
        totalBreakDelayMinutes: 5,
        locationCoords: { latitude: 13.08, longitude: 80.27, accuracy: 5, distance: 2 },
      },
      {
        id: `att2_${tag}`,
        companyId: comp1._id,
        userId: `u2_${tag}`,
        date: '2023-07-05',
        status: 'present',
        checkIn: '09:25',
        checkOut: '18:30',
        totalWorkingHours: 8,
        workingHours: 8,
      },
      {
        id: `att_other_${tag}`,
        companyId: comp2._id,
        userId: `u_other_${tag}`,
        date: '2024-02-10',
        status: 'present',
        totalWorkingHours: 8,
      },
    ]);

    await Leave.create({
      id: `lv1_${tag}`,
      companyId: comp1._id,
      userId: `u1_${tag}`,
      type: 'casual',
      startDate: '2024-03-04',
      endDate: '2024-03-04',
      workingDays: 1,
      status: 'approved',
      reason: 'Personal',
    });

    await Holiday.create({
      id: `hol1_${tag}`,
      companyId: comp1._id,
      name: 'Annual Founders Day',
      date: '2024-04-01',
    });

    const p1 = await Payroll.create({
      id: `pay1_${tag}`,
      companyId: comp1._id,
      userId: `u2_${tag}`,
      month: '2023-07',
      status: 'finalized',
      paymentStatus: 'paid',
      baseSalary: 40000,
      earnedSalary: 39000,
      hourlyOvertimeAddition: 500,
      overtimeHours: 2,
      unapprovedLeaveDeduction: 1000,
      manualDeduction: 500,
      totalDeductions: 1500,
      bonus: 1000,
      totalAmount: 40000,
      netPayable: 40000,
      amountPaid: 40000,
      pendingAmount: 0,
      paidAt: new Date('2023-08-01T10:00:00Z'),
      auditTrail: [{ action: 'finalized', performedBy: `owner_${tag}` }],
    });

    await PayrollAdjustment.create({
      id: `adj_pf_${tag}`,
      companyId: comp1._id,
      userId: `u2_${tag}`,
      month: '2023-07',
      type: 'deduction',
      amount: 500,
      reason: 'PF Contribution',
      addedBy: `owner_${tag}`,
    });

    await PaymentTransaction.create({
      id: `tx1_${tag}`,
      payrollId: p1._id,
      type: 'salary',
      companyId: comp1._id,
      userId: `u2_${tag}`,
      month: '2023-07',
      amount: 40000,
      paymentMethod: 'bank_transfer',
      referenceId: `REF_${tag}`,
      processedBy: `owner_${tag}`,
      processedByName: 'Owner',
      paidAt: new Date('2023-08-01T10:00:00Z'),
    });

    await Project.create({
      id: `proj1_${tag}`,
      companyId: comp1._id,
      name: 'Historical Platform Migration',
      description: 'Legacy to Mongo migration',
      status: 'active',
      priority: 'high',
      startDate: '2024-01-20',
      dueDate: '2024-06-01',
      createdBy: 'Owner',
      assignedEmployees: [
        { userId: `u1_${tag}`, name: 'Kavin Active', department: 'Engineering' },
        { userId: `u2_${tag}`, name: 'Meera Former', department: 'Design' },
      ],
    });

    await Task.create([
      {
        id: `gtask1_${tag}`,
        companyId: comp1._id,
        title: 'Security Policy Review',
        description: 'General annual security check',
        assignedTo: `u1_${tag}`,
        assignorName: 'Owner',
        status: 'in_progress',
        priority: 'high',
        startDate: '2024-02-01',
        dueDate: '2024-02-05',
        isProjectTask: false,
        progressPercentage: 60,
        progressUpdates: [
          {
            date: '2024-02-03',
            updateText: 'Drafted checklist',
            percentage: 60,
            employeeName: 'Kavin Active',
            employeeId: `u1_${tag}`,
          },
        ],
      },
      {
        id: `ptask1_${tag}`,
        companyId: comp1._id,
        title: 'Design Schema Map',
        assignedTo: `u2_${tag}`,
        assignorName: 'Owner',
        status: 'done',
        priority: 'medium',
        startDate: '2024-01-22',
        endDate: '2024-02-01',
        completedAt: '2024-01-30T15:00:00.000Z',
        projectId: `proj1_${tag}`,
        projectName: 'Historical Platform Migration',
        isProjectTask: true,
        progressPercentage: 100,
      },
    ]);

    await test('Attendance Report returns complete history including former staff, breaks, GPS, leaves, holidays & tenant isolation', async () => {
      const rep = await buildAttendanceReportData(comp1._id, { period: 'all' });
      assert.equal(rep.totalRecords, 2);
      assert.equal(rep.leaveCount, 1);
      assert.equal(rep.holidayCount, 1);
      assert.equal(rep.records.some((r) => r.userId === `u_other_${tag}`), false);
      const u2Row = rep.records.find((r) => r.userId === `u2_${tag}`);
      assert.ok(u2Row, 'Former/inactive employee attendance history must be preserved');
      assert.equal(u2Row.joiningDate, '2023-06-01');
      assert.equal(u2Row.employeeStatus, 'inactive');
      const u1Row = rep.records.find((r) => r.userId === `u1_${tag}`);
      assert.equal(u1Row.overtimeHours, 1.5);
      assert.equal(u1Row.locationVerified, true);
      assert.equal(u1Row.breakMinutes, 60);
    });

    await test('Payment Report returns historical 2023 payroll, transactions, PF adjustment & former employee', async () => {
      const rep = await buildPayrollReportData(comp1._id, { period: 'all' });
      assert.equal(rep.totalEmployees, 1);
      assert.equal(rep.companyOverallAmountPaid, 40000);
      assert.equal(rep.companyOverallPfDeductions, 500);
      assert.equal(rep.pfSupported, true);
      assert.equal(rep.transactions.length, 1);
      assert.equal(rep.records[0].joiningDate, '2023-06-01');
      assert.equal(rep.records[0].auditTrail.length, 1);
    });

    await test('General Task Report excludes project tasks when scope=general & computes overdue/activity', async () => {
      const rep = await buildSchedulesReportData(comp1._id, { period: 'all', scope: 'general' });
      assert.equal(rep.totalTasks, 1);
      assert.equal(rep.records[0].taskTitle, 'Security Policy Review');
      assert.equal(rep.records[0].isOverdue, true);
      assert.equal(rep.records[0].progressUpdates.length, 1);
      assert.ok(rep.records[0].activityHistory.length >= 2);
    });

    await test('Project Report aggregates project tasks, delays, employee contributions & timeline', async () => {
      const rep = await buildProjectReportData(comp1._id, { period: 'all' });
      assert.equal(rep.totalProjects, 1);
      assert.equal(rep.delayedProjects, 1);
      const proj = rep.projects[0];
      assert.equal(proj.taskMetrics.total, 1);
      assert.equal(proj.taskMetrics.completed, 1);
      assert.equal(proj.employeeContributions.length, 2);
      assert.ok(proj.activityHistory.length >= 2);
    });
  } finally {
    if (comp1?._id || comp2?._id) {
      const ids = [comp1?._id, comp2?._id].filter(Boolean);
      await Promise.all([
        Attendance.deleteMany({ companyId: { $in: ids } }),
        Leave.deleteMany({ companyId: { $in: ids } }),
        Holiday.deleteMany({ companyId: { $in: ids } }),
        PayrollSetting.deleteMany({ companyId: { $in: ids } }),
        Payroll.deleteMany({ companyId: { $in: ids } }),
        PayrollAdjustment.deleteMany({ companyId: { $in: ids } }),
        PaymentTransaction.deleteMany({ companyId: { $in: ids } }),
        Task.deleteMany({ companyId: { $in: ids } }),
        Project.deleteMany({ companyId: { $in: ids } }),
        User.deleteMany({ companyId: { $in: ids } }),
        Company.deleteMany({ _id: { $in: ids } }),
      ]);
    }
    await mongoose.disconnect();
  }
}

console.log(`\nAll ${passed} historical report checks passed!`);
