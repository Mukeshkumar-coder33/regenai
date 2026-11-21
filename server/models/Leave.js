import mongoose from 'mongoose';

const leaveSchema = new mongoose.Schema({
  id: { type: String, required: true, default: () => new mongoose.Types.ObjectId().toString(), unique: true },
  companyId: { type: mongoose.Schema.Types.ObjectId, ref: 'Company', index: true },
  userId: { type: String, required: true },
  displayId: { type: String },
  type: { type: String, enum: ['casual', 'sick', 'earned', 'unpaid'], default: 'casual' },
  startDate: { type: String, required: true },
  endDate: { type: String, required: true },
  workingDays: { type: Number, default: 1 },
  reason: { type: String },
  status: { type: String, enum: ['pending', 'approved', 'rejected'], default: 'pending' },
  appliedAt: { type: String, default: () => new Date().toISOString() },
  approvedBy: { type: String },
  approvedByName: { type: String },
  approvalDate: { type: String },
  rejectionReason: { type: String },
  remarks: { type: String },
  employeeName: { type: String },
  department: { type: String },
  balanceAtRequest: { type: Number },
  documentUrl: { type: String },
  createdAt: { type: String, default: () => new Date().toISOString() }
}, { timestamps: true });

export default mongoose.model('Leave', leaveSchema);
