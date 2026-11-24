import mongoose from 'mongoose';

const taskSchema = new mongoose.Schema({
  id: { type: String, required: true, unique: true },
  companyId: { type: mongoose.Schema.Types.ObjectId, ref: 'Company', index: true },
  title: { type: String, required: true },
  description: { type: String },
  assignedTo: { type: String }, // User ID (Principal)
  status: { type: String, enum: ['todo', 'in_progress', 'paused', 'blocked', 'review', 'done', 'not_completed'], default: 'todo' },
  priority: { type: String, enum: ['low', 'medium', 'high'], default: 'medium' },
  assignorName: { type: String },
  durationValue: { type: Number },
  durationUnit: { type: String, enum: ['hours', 'days', 'minutes'] },
  dueDate: { type: String },
  dueTime: { type: String },
  startDate: { type: String },
  endDate: { type: String },
  endTime: { type: String },
  projectId: { type: String, index: true },
  projectName: { type: String },
  isProjectTask: { type: Boolean, default: false },
  attachments: [{
    name: { type: String },
    url: { type: String },
    fileType: { type: String },
    size: { type: Number },
    data: { type: String }, // base64 payload if stored inline
  }],
  startedAt: { type: String },
  workingTime: { type: String },
  completedAt: { type: String },
  completionTime: { type: String },
  progressPercentage: { type: Number, default: 0, min: 0, max: 100 },
  progressUpdates: [{
    date: { type: String },
    updateText: { type: String },
    percentage: { type: Number },
    employeeName: { type: String },
    employeeId: { type: String },
  }],
  completionReport: {
    reportText: { type: String },
    submittedAt: { type: String },
    startDay: { type: String },
    startTime: { type: String },
    endDay: { type: String },
    endTime: { type: String },
    employeeName: { type: String },
    employeeId: { type: String },
    workingTime: { type: String },
  },
  extensionRequest: {
    requestedDueDate: { type: String },
    requestedDueTime: { type: String },
    reason: { type: String },
    status: { type: String, enum: ['none', 'pending', 'accepted', 'rejected'], default: 'none' },
    requestedAt: { type: String },
    reviewedAt: { type: String },
    companyResponse: { type: String },
  },
}, { timestamps: true });

export default mongoose.model('Task', taskSchema);
