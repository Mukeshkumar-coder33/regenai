import mongoose from 'mongoose';

const dailyBreakdownItemSchema = new mongoose.Schema({
  date: { type: String, required: true }, // 'YYYY-MM-DD'
  dayOfWeek: { type: Number, required: true }, // 0 = Sunday, 1 = Monday, ...
  dayName: { type: String }, // 'Monday', 'Tuesday', etc.
  isHoliday: { type: Boolean, default: false },
  holidayName: { type: String },
  isWeeklyOff: { type: Boolean, default: false },
  isApprovedLeave: { type: Boolean, default: false },
  isUnapprovedLeave: { type: Boolean, default: false },
  isPresent: { type: Boolean, default: false },
  isFuture: { type: Boolean, default: false },
  checkIn: { type: String },
  checkOut: { type: String },
  requiredHours: { type: Number, default: 0 },
  actualHours: { type: Number, default: 0 },
  shortfallHours: { type: Number, default: 0 },
  overtimeHours: { type: Number, default: 0 },
  shortfallDeduction: { type: Number, default: 0 },
  overtimeAddition: { type: Number, default: 0 },
  leaveDeduction: { type: Number, default: 0 },
  attendanceStatus: { type: String },
  leaveType: { type: String },
  leaveApprovalStatus: { type: String },
  lateMinutes: { type: Number, default: 0 },
  lateDeduction: { type: Number, default: 0 },
  breakMinutes: { type: Number, default: 0 },
  casualBreakMinutes: { type: Number, default: 0 },
  breakDelayMinutes: { type: Number, default: 0 },
  casualBreakDelayMinutes: { type: Number, default: 0 },
  totalBreakDelayMinutes: { type: Number, default: 0 },
  breakDeduction: { type: Number, default: 0 },
  explanation: { type: String },
  dailyAdjustments: [{
    type: { type: String },
    amount: { type: Number, default: 0 },
    reason: { type: String },
  }],
  notes: { type: String },
}, { _id: false });

const payrollSchema = new mongoose.Schema({
  id: {
    type: String,
    required: true,
    unique: true,
    default: () => new mongoose.Types.ObjectId().toString(),
  },
  companyId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Company',
    required: true,
    index: true,
  },
  userId: {
    type: String,
    required: true,
    index: true,
  },
  month: {
    type: String,
    required: true,
    index: true, // 'YYYY-MM' format, e.g. '2026-10'
  },
  status: {
    type: String,
    enum: ['draft', 'finalized'],
    default: 'draft',
    index: true,
  },
  paymentStatus: {
    type: String,
    enum: ['unpaid', 'paid', 'partially_paid'],
    default: 'unpaid',
    index: true,
  },
  baseSalary: {
    type: Number,
    required: true,
    default: 0,
  },
  scheduledWorkingDays: {
    type: Number,
    default: 0,
  },
  scheduledWorkingHours: {
    type: Number,
    default: 0,
  },
  actualWorkingHours: {
    type: Number,
    default: 0,
  },
  shortfallHours: {
    type: Number,
    default: 0,
  },
  overtimeHours: {
    type: Number,
    default: 0,
  },
  approvedLeaveDays: {
    type: Number,
    default: 0,
  },
  unapprovedLeaveDays: {
    type: Number,
    default: 0,
  },
  holidayDays: {
    type: Number,
    default: 0,
  },
  weeklyOffDays: {
    type: Number,
    default: 0,
  },
  presentDays: {
    type: Number,
    default: 0,
  },
  payrollDivisor: {
    type: Number,
    default: 1,
  },
  hourlyDeductionRate: {
    type: Number,
    default: 0,
  },
  hourlyOvertimeRate: {
    type: Number,
    default: 0,
  },
  dailySalaryBasis: {
    type: Number,
    default: 0,
  },
  hourlyShortfallDeduction: {
    type: Number,
    default: 0,
  },
  hourlyOvertimeAddition: {
    type: Number,
    default: 0,
  },
  approvedLeaveDeduction: {
    type: Number,
    default: 0,
  },
  unapprovedLeaveDeduction: {
    type: Number,
    default: 0,
  },
  lateMinutes: {
    type: Number,
    default: 0,
  },
  lateDeduction: {
    type: Number,
    default: 0,
  },
  totalBreakDelayMinutes: {
    type: Number,
    default: 0,
  },
  totalBreakDeduction: {
    type: Number,
    default: 0,
  },
  leaveDeductionBreakdown: {
    paidUnapproved: { type: Number, default: 0 },
    unpaidApproved: { type: Number, default: 0 },
    unpaidUnapproved: { type: Number, default: 0 },
  },
  otherAdjustments: {
    type: Number,
    default: 0,
  },
  earnedSalary: {
    type: Number,
    default: 0,
  },
  grossPayable: {
    type: Number,
    default: 0,
  },
  totalDeductions: {
    type: Number,
    default: 0,
  },
  totalAdditions: {
    type: Number,
    default: 0,
  },
  bonus: {
    type: Number,
    default: 0,
  },
  manualDeduction: {
    type: Number,
    default: 0,
  },
  totalAmount: {
    type: Number,
    default: 0,
  },
  netPayable: {
    type: Number,
    required: true,
    default: 0,
  },
  excessDeduction: {
    type: Number,
    default: 0,
  },
  amountPaid: {
    type: Number,
    default: 0,
  },
  pendingAmount: {
    type: Number,
    default: 0,
  },
  snapshotSettings: {
    type: mongoose.Schema.Types.Mixed,
    default: null,
  },
  dailyBreakdown: [dailyBreakdownItemSchema],
  finalizedAt: {
    type: Date,
  },
  finalizedBy: {
    type: String,
  },
  isClosed: {
    type: Boolean,
    default: false,
    index: true,
  },
  closedAt: {
    type: Date,
  },
  closedBy: {
    type: String,
  },
  payslipNumber: {
    type: String,
  },
  payslipGeneratedAt: {
    type: Date,
  },
  paidAt: {
    type: Date,
  },
  paymentId: {
    type: String,
  },
  notes: {
    type: String,
  },
  auditTrail: [{
    action: { type: String, required: true },
    performedBy: { type: String, required: true },
    timestamp: { type: Date, default: Date.now },
    details: { type: mongoose.Schema.Types.Mixed },
  }],
}, { timestamps: true });

// Ensure unique payroll per company, employee, and month
payrollSchema.index({ companyId: 1, userId: 1, month: 1 }, { unique: true });

export default mongoose.model('Payroll', payrollSchema);
