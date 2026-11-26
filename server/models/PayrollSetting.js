import mongoose from 'mongoose';

const payrollSettingSchema = new mongoose.Schema({
  companyId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Company',
    required: true,
    unique: true,
    index: true,
  },
  checkInTime: {
    type: String,
    default: '09:30',
    trim: true,
  },
  checkOutTime: {
    type: String,
    default: '18:30',
    trim: true,
  },
  workingHoursPerDay: {
    type: Number,
    default: 8,
    min: 1,
    max: 24,
  },
  workingDaysPerWeek: {
    type: Number,
    default: 5,
    min: 1,
    max: 7,
  },
  breakTime: {
    type: Number,
    default: 60, // in minutes (official / lunch break)
    min: 0,
    max: 300,
  },
  casualBreakTime: {
    type: Number,
    default: 15, // in minutes (casual / tea break)
    min: 0,
    max: 180,
  },
  weeklyOffDays: {
    type: [Number],
    default: [0, 6], // 0 = Sunday, 6 = Saturday
  },
  hourlyDeductionPct: {
    type: Number,
    default: 50,
    min: 0,
    max: 500,
  },
  hourlyOvertimePct: {
    type: Number,
    default: 75,
    min: 0,
    max: 500,
  },
  approvedLeaveDeductionPct: {
    type: Number,
    default: 25,
    min: 0,
    max: 100,
  },
  unapprovedLeaveDeductionPct: {
    type: Number,
    default: 100,
    min: 0,
    max: 200,
  },
  graceMinutes: {
    type: Number,
    default: 0,
    min: 0,
    max: 120,
  },
  payrollDivisorType: {
    type: String,
    enum: ['scheduled_hours', 'fixed_hours'],
    default: 'scheduled_hours',
  },
  fixedPayrollDivisor: {
    type: Number,
    default: 200,
    min: 1,
  },
  dailyBasisType: {
    type: String,
    enum: ['scheduled_days', 'calendar_days'],
    default: 'scheduled_days',
  },
  lateDeductionEnabled: {
    type: Boolean,
    default: true,
  },
  lateDeductionMode: {
    type: String,
    enum: ['fixed_per_late', 'per_minute', 'hourly_rate'],
    default: 'hourly_rate',
  },
  lateDeductionRate: {
    type: Number,
    default: 100,
    min: 0,
  },
  shortfallDeductionEnabled: {
    type: Boolean,
    default: true,
  },
  overtimeEnabled: {
    type: Boolean,
    default: true,
  },
  overtimeMinMinutes: {
    type: Number,
    default: 0,
    min: 0,
    max: 480,
  },
  breakDelayDeductionEnabled: {
    type: Boolean,
    default: true,
  },
  breakDelayRuleType: {
    type: String,
    enum: ['per_interval_flat', 'salary_minute_rate'],
    default: 'per_interval_flat',
  },
  breakDelayIntervalMinutes: {
    type: Number,
    default: 10,
    min: 1,
    max: 120,
  },
  breakDelayIntervalAmount: {
    type: Number,
    default: 1,
    min: 0,
  },
  policyVersion: {
    type: Number,
    default: 1,
  },
  updatedBy: {
    type: String,
    trim: true,
  },
}, { timestamps: true });

export default mongoose.model('PayrollSetting', payrollSettingSchema);
