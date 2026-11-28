/**
 * Zero-dependency Firebase Cloud Messaging (FCM HTTP v1) dispatcher for ReGen.
 *
 * Uses a Firebase Service Account configured via:
 *   - FIREBASE_SERVICE_ACCOUNT_JSON (raw JSON or base64-encoded JSON), OR
 *   - FIREBASE_SERVICE_ACCOUNT_PATH / GOOGLE_APPLICATION_CREDENTIALS, OR
 *   - server/firebase-service-account.json
 *
 * Gracefully degrades with explicit structured diagnostics when credentials are not yet configured,
 * and cleans up invalid/unregistered device tokens automatically when FCM rejects them.
 */
import crypto from 'crypto';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import mongoose from 'mongoose';
import User from '../models/User.js';
import SuperAdmin from '../models/SuperAdmin.js';
import { logCommEvent } from './commLogger.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

let cachedServiceAccount = null;
let cachedAttemptedLoad = false;
let cachedAccessToken = null;
let cachedAccessTokenExpiryMs = 0;
let fcmStatusState = {
  configured: false,
  initialized: false,
  source: null,
  projectId: null,
  clientEmailMasked: null,
  error: 'Not initialized',
};

function maskClientEmail(email) {
  const s = String(email || '').trim();
  const atIdx = s.indexOf('@');
  if (atIdx <= 3) return atIdx > 0 ? `***${s.slice(atIdx)}` : null;
  return `${s.slice(0, 4)}***${s.slice(atIdx)}`;
}

function validateServiceAccount(parsed) {
  if (!parsed || typeof parsed !== 'object') {
    return 'Service account payload is not an object';
  }
  if (parsed.type && parsed.type !== 'service_account') {
    return `Unexpected credential type "${parsed.type}" (expected service_account)`;
  }
  if (!parsed.project_id || typeof parsed.project_id !== 'string') {
    return 'Missing project_id in Firebase service account';
  }
  if (!parsed.client_email || typeof parsed.client_email !== 'string') {
    return 'Missing client_email in Firebase service account';
  }
  if (
    !parsed.private_key ||
    typeof parsed.private_key !== 'string' ||
    !parsed.private_key.includes('BEGIN') ||
    !parsed.private_key.includes('PRIVATE KEY')
  ) {
    return 'Missing or invalid PEM private_key in Firebase service account';
  }
  return null;
}

function loadServiceAccount({ forceReload = false } = {}) {
  if (!forceReload && cachedAttemptedLoad) return cachedServiceAccount;
  cachedAttemptedLoad = true;
  cachedServiceAccount = null;
  if (forceReload) {
    cachedAccessToken = null;
    cachedAccessTokenExpiryMs = 0;
  }

  try {
    // 1. Explicit absolute/configured path env (preferred for production server /etc/regen/secrets/...)
    const explicitPath = process.env.FIREBASE_SERVICE_ACCOUNT_PATH?.trim();
    if (explicitPath) {
      const resolvedPath = path.isAbsolute(explicitPath)
        ? explicitPath
        : path.resolve(__dirname, '..', explicitPath);
      if (!fs.existsSync(resolvedPath)) {
        const msg = `FIREBASE_SERVICE_ACCOUNT_PATH does not exist: ${resolvedPath}`;
        fcmStatusState = {
          configured: false,
          initialized: true,
          source: 'FIREBASE_SERVICE_ACCOUNT_PATH',
          projectId: null,
          clientEmailMasked: null,
          error: msg,
        };
        logCommEvent('fcm:config_invalid', { source: 'FIREBASE_SERVICE_ACCOUNT_PATH', error: msg });
        return null;
      }
      const parsed = JSON.parse(fs.readFileSync(resolvedPath, 'utf8'));
      const valErr = validateServiceAccount(parsed);
      if (valErr) {
        fcmStatusState = {
          configured: false,
          initialized: true,
          source: 'FIREBASE_SERVICE_ACCOUNT_PATH',
          projectId: parsed?.project_id || null,
          clientEmailMasked: maskClientEmail(parsed?.client_email),
          error: valErr,
        };
        logCommEvent('fcm:config_invalid', { source: 'FIREBASE_SERVICE_ACCOUNT_PATH', error: valErr });
        return null;
      }
      cachedServiceAccount = parsed;
      fcmStatusState = {
        configured: true,
        initialized: true,
        source: `FIREBASE_SERVICE_ACCOUNT_PATH (${resolvedPath})`,
        projectId: parsed.project_id,
        clientEmailMasked: maskClientEmail(parsed.client_email),
        error: null,
      };
      return cachedServiceAccount;
    }

    // 2. Inline JSON / base64 JSON env
    const rawJsonEnv = process.env.FIREBASE_SERVICE_ACCOUNT_JSON?.trim();
    if (rawJsonEnv) {
      const jsonStr = rawJsonEnv.startsWith('{')
        ? rawJsonEnv
        : Buffer.from(rawJsonEnv, 'base64').toString('utf8');
      const parsed = JSON.parse(jsonStr);
      const valErr = validateServiceAccount(parsed);
      if (valErr) {
        fcmStatusState = {
          configured: false,
          initialized: true,
          source: 'FIREBASE_SERVICE_ACCOUNT_JSON',
          projectId: parsed?.project_id || null,
          clientEmailMasked: maskClientEmail(parsed?.client_email),
          error: valErr,
        };
        logCommEvent('fcm:config_invalid', { source: 'FIREBASE_SERVICE_ACCOUNT_JSON', error: valErr });
        return null;
      }
      cachedServiceAccount = parsed;
      fcmStatusState = {
        configured: true,
        initialized: true,
        source: 'FIREBASE_SERVICE_ACCOUNT_JSON',
        projectId: parsed.project_id,
        clientEmailMasked: maskClientEmail(parsed.client_email),
        error: null,
      };
      return cachedServiceAccount;
    }

    // 3. Fallback file paths: GOOGLE_APPLICATION_CREDENTIALS -> local server JSON -> persistent Linux /etc/regen/secrets
    const candidates = [
      process.env.GOOGLE_APPLICATION_CREDENTIALS?.trim()
        ? { label: 'GOOGLE_APPLICATION_CREDENTIALS', filePath: process.env.GOOGLE_APPLICATION_CREDENTIALS.trim() }
        : null,
      { label: 'server/firebase-service-account.json', filePath: path.join(__dirname, '..', 'firebase-service-account.json') },
      { label: '/etc/regen/secrets/firebase-service-account.json', filePath: '/etc/regen/secrets/firebase-service-account.json' },
    ].filter(Boolean);

    for (const candidate of candidates) {
      if (fs.existsSync(candidate.filePath)) {
        const parsed = JSON.parse(fs.readFileSync(candidate.filePath, 'utf8'));
        const valErr = validateServiceAccount(parsed);
        if (valErr) {
          fcmStatusState = {
            configured: false,
            initialized: true,
            source: candidate.label,
            projectId: parsed?.project_id || null,
            clientEmailMasked: maskClientEmail(parsed?.client_email),
            error: valErr,
          };
          logCommEvent('fcm:config_invalid', { source: candidate.label, error: valErr });
          return null;
        }
        cachedServiceAccount = parsed;
        fcmStatusState = {
          configured: true,
          initialized: true,
          source: candidate.label,
          projectId: parsed.project_id,
          clientEmailMasked: maskClientEmail(parsed.client_email),
          error: null,
        };
        return cachedServiceAccount;
      }
    }

    fcmStatusState = {
      configured: false,
      initialized: true,
      source: null,
      projectId: null,
      clientEmailMasked: null,
      error: 'No Firebase service account configured',
    };
  } catch (err) {
    fcmStatusState = {
      configured: false,
      initialized: true,
      source: null,
      projectId: null,
      clientEmailMasked: null,
      error: err.message,
    };
    logCommEvent('fcm:config_error', { error: err.message });
  }
  return null;
}

export function initializeFcmStartup(opts = {}) {
  const sa = loadServiceAccount(opts);
  logCommEvent('fcm:startup_check', {
    configured: Boolean(sa),
    source: fcmStatusState.source || 'none',
    projectId: fcmStatusState.projectId || '',
    ...(fcmStatusState.error ? { error: fcmStatusState.error } : {}),
  });
  return { ...fcmStatusState };
}

export function getFcmStatus() {
  if (!cachedAttemptedLoad) {
    loadServiceAccount();
  }
  return { ...fcmStatusState };
}

export function isFcmConfigured() {
  return loadServiceAccount() !== null;
}

function base64UrlEncode(input) {
  return Buffer.from(input)
    .toString('base64')
    .replace(/=/g, '')
    .replace(/\+/g, '-')
    .replace(/\//g, '_');
}

async function getAccessToken(sa) {
  const now = Date.now();
  if (cachedAccessToken && now < cachedAccessTokenExpiryMs - 60000) {
    return cachedAccessToken;
  }

  const iat = Math.floor(now / 1000);
  const exp = iat + 3600;
  const header = base64UrlEncode(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const claim = base64UrlEncode(JSON.stringify({
    iss: sa.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    iat,
    exp,
  }));

  const signer = crypto.createSign('RSA-SHA256');
  signer.update(`${header}.${claim}`);
  const sig = base64UrlEncode(signer.sign(sa.private_key));
  const assertion = `${header}.${claim}.${sig}`;

  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion,
    }).toString(),
  });

  if (!res.ok) {
    const errText = await res.text().catch(() => '');
    throw new Error(`OAuth2 token exchange failed (${res.status}): ${errText.slice(0, 180)}`);
  }

  const data = await res.json();
  cachedAccessToken = data.access_token;
  cachedAccessTokenExpiryMs = now + (Number(data.expires_in) || 3600) * 1000;
  return cachedAccessToken;
}

async function removeStalePushToken(token) {
  if (!token) return;
  try {
    await Promise.all([
      User.updateMany({}, { $pull: { pushTokens: { token } } }),
      SuperAdmin.updateMany({}, { $pull: { pushTokens: { token } } }),
    ]);
    logCommEvent('fcm:token_pruned', { tokenPrefix: `${token.slice(0, 8)}...` });
  } catch (err) {
    logCommEvent('fcm:token_prune_failed', { error: err.message });
  }
}

async function resolvePushTargets(userIdentifiers = []) {
  const ids = Array.from(new Set(userIdentifiers.map((v) => String(v || '').trim()).filter(Boolean)));
  if (ids.length === 0) return [];

  const objectIds = ids.filter((id) => mongoose.isValidObjectId(id)).map((id) => new mongoose.Types.ObjectId(id));
  const [users, superAdmins] = await Promise.all([
    User.find({
      $or: [
        { userId: { $in: ids } },
        { StaffId: { $in: ids } },
        { username: { $in: ids } },
        ...(objectIds.length ? [{ _id: { $in: objectIds } }] : []),
      ],
      status: { $ne: 'inactive' },
    }).select('userId pushTokens').lean(),
    SuperAdmin.find({
      $or: [
        { adminId: { $in: ids } },
        { username: { $in: ids } },
        ...(objectIds.length ? [{ _id: { $in: objectIds } }] : []),
      ],
    }).select('adminId pushTokens').lean(),
  ]);

  const tokenMap = new Map();
  for (const doc of [...users, ...superAdmins]) {
    const uid = String(doc.userId || doc.adminId || '');
    for (const entry of doc.pushTokens || []) {
      const tok = String(entry?.token || '').trim();
      if (!tok) continue;
      if (!tokenMap.has(tok)) {
        tokenMap.set(tok, {
          token: tok,
          platform: String(entry?.platform || 'android'),
          userId: uid,
        });
      }
    }
  }
  return Array.from(tokenMap.values());
}

/**
 * Send push notifications via FCM HTTP v1 to one or more users' registered devices.
 *
 * For incoming calls (`dataOnly: true`), sends a high-priority data-only FCM message
 * so the Android background handler wakes reliably without OS auto-display overriding call UI.
 */
export async function sendFcmPushToUsers({
  userIds = [],
  title = '',
  body = '',
  data = {},
  highPriority = false,
  dataOnly = false,
  channelId = 'regen_messages_v2',
  ttlSeconds = null,
  collapseKey = null,
  correlationId = '',
}) {
  const targets = await resolvePushTargets(userIds);
  const sa = loadServiceAccount();

  if (!sa) {
    logCommEvent('fcm:dispatch_skipped_unconfigured', {
      correlationId,
      targetUsers: userIds.length,
      registeredTokens: targets.length,
      type: data?.type || 'general',
    });
    return {
      configured: false,
      targetedTokens: targets.length,
      sentCount: 0,
      failedCount: 0,
      prunedCount: 0,
    };
  }

  if (targets.length === 0) {
    logCommEvent('fcm:dispatch_no_tokens', {
      correlationId,
      targetUsers: userIds.length,
      type: data?.type || 'general',
    });
    return {
      configured: true,
      targetedTokens: 0,
      sentCount: 0,
      failedCount: 0,
      prunedCount: 0,
    };
  }

  const stringData = {};
  for (const [k, v] of Object.entries(data || {})) {
    if (v !== undefined && v !== null) {
      stringData[k] = typeof v === 'string' ? v : JSON.stringify(v);
    }
  }
  if (title && !stringData.title) stringData.title = String(title);
  if (body && !stringData.body) stringData.body = String(body);
  if (correlationId) stringData.correlationId = String(correlationId);

  let accessToken;
  try {
    accessToken = await getAccessToken(sa);
  } catch (err) {
    logCommEvent('fcm:oauth_failed', { correlationId, error: err.message });
    return {
      configured: true,
      targetedTokens: targets.length,
      sentCount: 0,
      failedCount: targets.length,
      prunedCount: 0,
      error: err.message,
    };
  }

  const endpoint = `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`;
  let sentCount = 0;
  let failedCount = 0;
  let prunedCount = 0;

  await Promise.all(targets.map(async (target) => {
    const androidConfig = {
      priority: highPriority ? 'HIGH' : 'NORMAL',
      ...(ttlSeconds ? { ttl: `${ttlSeconds}s` } : {}),
      ...(collapseKey ? { collapse_key: collapseKey } : {}),
    };

    if (!dataOnly) {
      const tag =
        stringData.notificationId ||
        (stringData.type === 'missed_call' && stringData.callId
          ? `missed-${stringData.callId}`
          : stringData.callId) ||
        undefined;
      androidConfig.notification = {
        channel_id: channelId,
        sound: 'default',
        visibility: 'PUBLIC',
        notification_priority: highPriority ? 'PRIORITY_MAX' : 'PRIORITY_HIGH',
        click_action: 'FLUTTER_NOTIFICATION_CLICK',
        ...(tag ? { tag } : {}),
      };
    }

    const messagePayload = {
      message: {
        token: target.token,
        data: stringData,
        android: androidConfig,
        ...(!dataOnly && (title || body)
          ? {
              notification: {
                title: String(title || 'ReGen'),
                body: String(body || ''),
              },
            }
          : {}),
        apns: {
          headers: {
            'apns-priority': highPriority ? '10' : '5',
            ...(dataOnly ? { 'apns-push-type': 'background' } : {}),
          },
          payload: {
            aps: dataOnly
              ? { 'content-available': 1 }
              : { sound: 'default', badge: 1, 'interruption-level': highPriority ? 'time-sensitive' : 'active' },
          },
        },
      },
    };

    try {
      const res = await fetch(endpoint, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${accessToken}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(messagePayload),
      });

      if (res.ok) {
        sentCount++;
      } else {
        failedCount++;
        const errBody = await res.json().catch(() => ({}));
        const fcmErrCode = errBody?.error?.details?.find?.((d) => d.errorCode)?.errorCode || errBody?.error?.status || '';
        logCommEvent('fcm:dispatch_error', {
          correlationId,
          userId: target.userId,
          status: res.status,
          code: fcmErrCode,
        });
        if (['UNREGISTERED', 'INVALID_ARGUMENT', 'NOT_FOUND'].includes(fcmErrCode) || res.status === 404) {
          prunedCount++;
          await removeStalePushToken(target.token);
        }
      }
    } catch (err) {
      failedCount++;
      logCommEvent('fcm:network_error', {
        correlationId,
        userId: target.userId,
        error: err.message,
      });
    }
  }));

  logCommEvent('fcm:dispatch_complete', {
    correlationId,
    type: stringData.type || 'general',
    targetedTokens: targets.length,
    sentCount,
    failedCount,
    prunedCount,
  });

  return {
    configured: true,
    targetedTokens: targets.length,
    sentCount,
    failedCount,
    prunedCount,
  };
}
