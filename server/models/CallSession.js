import mongoose from 'mongoose';

export const CALL_STATES = [
  'initiated',
  'ringing',
  'accepted',
  'rejected',
  'cancelled',
  'missed',
  'failed',
  'ended',
];

export const TERMINAL_CALL_STATES = new Set([
  'rejected',
  'cancelled',
  'missed',
  'failed',
  'ended',
]);

const ALLOWED_TRANSITIONS = {
  initiated: new Set(['initiated', 'ringing', 'accepted', 'rejected', 'cancelled', 'missed', 'failed', 'ended']),
  ringing: new Set(['ringing', 'accepted', 'rejected', 'cancelled', 'missed', 'failed', 'ended']),
  accepted: new Set(['accepted', 'ended', 'failed']),
  rejected: new Set(),
  cancelled: new Set(),
  missed: new Set(),
  failed: new Set(),
  ended: new Set(),
};

export function isValidCallTransition(fromState, toState) {
  if (!fromState) return toState === 'initiated' || toState === 'ringing';
  const allowed = ALLOWED_TRANSITIONS[fromState];
  if (!allowed) return false;
  return allowed.has(toState);
}

const callSessionSchema = new mongoose.Schema({
  callId: { type: String, required: true, unique: true, index: true },
  correlationId: { type: String, required: true, index: true },
  callerId: { type: String, required: true, index: true },
  callerName: { type: String, default: 'Someone' },
  recipientId: { type: String, required: true, index: true },
  recipientName: { type: String, default: '' },
  companyId: { type: mongoose.Schema.Types.ObjectId, ref: 'Company', default: null },
  mediaType: { type: String, enum: ['voice', 'video'], default: 'voice' },
  state: { type: String, enum: CALL_STATES, default: 'initiated', index: true },
  reason: { type: String, default: '' },
  offer: { type: mongoose.Schema.Types.Mixed, default: null },
  answer: { type: mongoose.Schema.Types.Mixed, default: null },
  callerCandidates: { type: [mongoose.Schema.Types.Mixed], default: [] },
  recipientCandidates: { type: [mongoose.Schema.Types.Mixed], default: [] },
  initiatedAt: { type: Date, default: Date.now },
  ringingAt: { type: Date, default: null },
  acceptedAt: { type: Date, default: null },
  endedAt: { type: Date, default: null },
  expiresAt: { type: Date, required: true, index: true },
  pushDispatched: { type: Boolean, default: false },
  pushResult: { type: String, default: '' },
}, { timestamps: true });

export default mongoose.model('CallSession', callSessionSchema);
