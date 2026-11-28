import crypto from 'crypto';

const MAX_RECENT_EVENTS = 250;
const recentEvents = [];

const REDACT_KEYS = new Set([
  'token',
  'password',
  'secret',
  'authorization',
  'offer',
  'answer',
  'sdp',
  'content',
  'decryptedcontent',
  'ciphertext',
  'privatekey',
]);

function sanitizeMeta(meta) {
  if (!meta || typeof meta !== 'object') return {};
  const clean = {};
  for (const [k, v] of Object.entries(meta)) {
    if (REDACT_KEYS.has(k.toLowerCase())) {
      clean[k] = '[REDACTED]';
    } else if (v && typeof v === 'object' && !Array.isArray(v)) {
      clean[k] = sanitizeMeta(v);
    } else {
      clean[k] = v;
    }
  }
  return clean;
}

export function createCorrelationId(prefix = 'comm') {
  return `${prefix}-${Date.now().toString(36)}-${crypto.randomBytes(3).toString('hex')}`;
}

export function logCommEvent(event, meta = {}) {
  const entry = {
    ts: new Date().toISOString(),
    event: String(event || 'comm:event'),
    ...sanitizeMeta(meta),
  };
  recentEvents.unshift(entry);
  if (recentEvents.length > MAX_RECENT_EVENTS) {
    recentEvents.length = MAX_RECENT_EVENTS;
  }

  const compactParts = Object.entries(entry)
    .filter(([k]) => k !== 'ts' && k !== 'event')
    .map(([k, v]) => `${k}=${typeof v === 'object' ? JSON.stringify(v) : v}`);
  console.log(`[CommDiag] ${entry.event}${compactParts.length ? ' | ' + compactParts.join(' ') : ''}`);
  return entry;
}

export function getRecentCommEvents(limit = 60) {
  return recentEvents.slice(0, Math.max(1, Math.min(Number(limit) || 60, MAX_RECENT_EVENTS)));
}
