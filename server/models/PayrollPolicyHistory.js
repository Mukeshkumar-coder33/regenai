import mongoose from 'mongoose';

const payrollPolicyHistorySchema = new mongoose.Schema({
  companyId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Company',
    required: true,
    index: true,
  },
  policyVersion: {
    type: Number,
    required: true,
    default: 1,
  },
  effectiveFrom: {
    type: String, // 'YYYY-MM-DD'
    required: true,
    index: true,
  },
  settingsSnapshot: {
    type: mongoose.Schema.Types.Mixed,
    required: true,
  },
  leavePolicySnapshot: {
    type: mongoose.Schema.Types.Mixed,
    default: null,
  },
  updatedBy: {
    type: String,
    trim: true,
  },
}, { timestamps: true });

payrollPolicyHistorySchema.index({ companyId: 1, effectiveFrom: -1, policyVersion: -1 });

export default mongoose.model('PayrollPolicyHistory', payrollPolicyHistorySchema);
