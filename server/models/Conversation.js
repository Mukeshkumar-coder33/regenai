import mongoose from 'mongoose';

const conversationSchema = new mongoose.Schema({
  companyId: { type: mongoose.Schema.Types.ObjectId, ref: 'Company', required: false, index: true },
  participants: [{ type: String, required: true }], // userId strings (2 for 1:1, 2+ for group)
  isGroup: { type: Boolean, default: false, index: true },
  name: { type: String, default: '' },
  createdBy: { type: String, default: '' },
  scope: {
    type: String,
    enum: ['company', 'superadmin_owners'],
    default: 'company',
    index: true
  },
  lastMessage: {
    content: { type: String, default: '' },
    senderId: { type: String },
    timestamp: { type: Date }
  },
  // E2E: each participant stores their ECDH public key (JWK JSON string)
  publicKeys: {
    type: Map,
    of: String, // userId → JWK JSON string
    default: {}
  }
}, { timestamps: true });

// Compound index to quickly find a conversation between two users in a company
conversationSchema.index({ companyId: 1, participants: 1 });

export default mongoose.model('Conversation', conversationSchema);
