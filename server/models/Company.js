import mongoose from 'mongoose';

const companySchema = new mongoose.Schema({
  name: { type: String, required: true },
  logo: { type: String },
  gst: { type: String },
  phoneNumber: { type: String, required: true },
  email: { type: String },
  category: { type: String },
  about: { type: String },
  address: { type: String }, 
  city: { type: String, required: true },
  state: { type: String },
  zip: { type: String },
  taxDetails: { type: String },
  policies: { type: String },
  companyPolicies: [{
    title: { type: String, required: true },
    content: { type: String, required: true },
    effectiveDate: { type: String },
    createdAt: { type: Date, default: Date.now },
  }],
  ownerId: { type: String, required: true }, // Links to the user who created it (Owner)
  ownerName: { type: String, trim: true }, // Full personal name of company owner
  status: { type: String, enum: ['active', 'blocked'], default: 'active' },
  leavePolicy: {
    casualLeave: {
      enabled: { type: Boolean, default: true },
      monthlyEntitlement: { type: Number, default: 1 },
      carryForward: { type: Boolean, default: true },
      maxCarryForward: { type: Number, default: 12 },
      requiresApproval: { type: Boolean, default: true },
      unapprovedDeductionRate: { type: Number, default: 100 }
    },
    sickLeave: {
      enabled: { type: Boolean, default: true },
      monthlyEntitlement: { type: Number, default: 1 },
      carryForward: { type: Boolean, default: false },
      maxCarryForward: { type: Number, default: 6 },
      requiresApproval: { type: Boolean, default: true },
      unapprovedDeductionRate: { type: Number, default: 100 }
    },
    unpaidLeave: {
      enabled: { type: Boolean, default: true },
      approvedDeductionRate: { type: Number, default: 100 },
      unapprovedDeductionRate: { type: Number, default: 100 },
      sameDeductionRate: { type: Boolean, default: true }
    }
  },
  officeLocation: {
    latitude: { type: Number },
    longitude: { type: Number },
    address: { type: String },
    radius: { type: Number, default: 5 },
    updatedAt: { type: Date },
  },
}, { timestamps: true });

export default mongoose.model('Company', companySchema);
