/**
 * Socket.IO server setup for real-time data synchronization & WebRTC signaling.
 *
 * Channels (rooms) are strictly role- & company-scoped:
 *   company:<companyId> — all users in a company get company events
 *   global              — SuperAdmin sees platform monitoring events
 *   user:<userId>       — targeted direct messages, 1:1 calls, notifications (across all user ID aliases)
 *   meeting:<meetingId> — authorized group voice/video call room (WebRTC Mesh)
 */
import { Server } from 'socket.io';
import jwt from 'jsonwebtoken';
import mongoose from 'mongoose';
import User from './models/User.js';
import SuperAdmin from './models/SuperAdmin.js';
import Conversation from './models/Conversation.js';
import DirectMessage from './models/DirectMessage.js';
import Notification from './models/Notification.js';
import CallSession, { TERMINAL_CALL_STATES, isValidCallTransition } from './models/CallSession.js';
import {
  resolveMessengerActor,
  canCommunicate,
  canAccessConversation,
  normalizeId,
} from './utils/messengerAuth.js';
import { sendFcmPushToUsers } from './utils/fcmPush.js';
import { createCorrelationId, logCommEvent } from './utils/commLogger.js';

let io = null;

const CALL_RING_TIMEOUT_MS = 45000;

// In-memory active 1:1 calls cache + timeout handles backed by MongoDB CallSession
const activeCalls = new Map(); // callId -> call object
const callTimeoutHandles = new Map(); // callId -> NodeJS.Timeout

// In-memory active group/team meetings ACL cache for strict room authorization
const activeMeetings = new Map();

// In-memory online user tracking (userId -> Set<socket.id>)
const onlineUserSockets = new Map();

// Per-socket active conversation tracking (socket.id -> { userId, conversationId })
// Prevents one device/tab disconnect from clearing another device's active chat!
const socketActiveConversations = new Map();

/**
 * Return whether any connected socket for [userId] is actively viewing [conversationId].
 */
export function isUserActiveInConversation(userId, conversationId) {
  if (!userId || !conversationId) return false;
  const uid = String(userId);
  const cid = String(conversationId);
  for (const entry of socketActiveConversations.values()) {
    if (entry.userId === uid && entry.conversationId === cid) {
      return true;
    }
  }
  return false;
}

/**
 * Return the set of currently connected userIds.
 */
export function getOnlineUserIds() {
  return new Set(onlineUserSockets.keys());
}

/**
 * Return redacted communication diagnostics for debugging.
 */
export function getSocketDiagnostics() {
  const connectedUsers = {};
  for (const [uid, sockSet] of onlineUserSockets.entries()) {
    connectedUsers[uid] = sockSet.size;
  }
  const activeCallStates = [];
  for (const c of activeCalls.values()) {
    activeCallStates.push({
      callId: c.callId,
      correlationId: c.correlationId,
      state: c.state || c.actionStatus,
      mediaType: c.mediaType,
      startedAt: c.startedAt,
    });
  }
  return {
    initialized: io !== null,
    onlineUserCount: onlineUserSockets.size,
    totalSockets: io ? io.engine.clientsCount : 0,
    connectedUsers,
    activeCallsCount: activeCalls.size,
    activeCalls: activeCallStates,
    activeMeetingsCount: activeMeetings.size,
  };
}

/**
 * Resolve all socket room aliases for a given user identifier (User or SuperAdmin).
 */
async function resolveUserRooms(identifier) {
  const rooms = new Set();
  if (!identifier) return rooms;
  const strId = String(identifier).trim();
  rooms.add(`user:${strId}`);
  try {
    const isOid = mongoose.isValidObjectId(strId);
    const [u, sa] = await Promise.all([
      User.findOne({
        $or: [
          { userId: strId },
          { StaffId: strId },
          { username: strId },
          ...(isOid ? [{ _id: new mongoose.Types.ObjectId(strId) }] : []),
        ],
      }).select('_id userId StaffId username companyId').lean(),
      SuperAdmin.findOne({
        $or: [
          { adminId: strId },
          { username: strId },
          ...(isOid ? [{ _id: new mongoose.Types.ObjectId(strId) }] : []),
        ],
      }).select('_id adminId username').lean(),
    ]);

    if (u) {
      if (u.userId) rooms.add(`user:${u.userId}`);
      if (u.StaffId) rooms.add(`user:${u.StaffId}`);
      if (u._id) rooms.add(`user:${u._id.toString()}`);
      if (u.username) rooms.add(`user:${u.username}`);
    }
    if (sa) {
      if (sa.adminId) rooms.add(`user:${sa.adminId}`);
      if (sa._id) rooms.add(`user:${sa._id.toString()}`);
      if (sa.username) rooms.add(`user:${sa.username}`);
    }
  } catch (_) {}
  return rooms;
}

/**
 * Broadcast an event to multiple candidate rooms with automatic Socket.IO deduplication.
 */
function broadcastToRooms(roomSet, event, payload) {
  if (!io || !roomSet || roomSet.size === 0) return;
  let broadcaster = io;
  for (const r of roomSet) {
    broadcaster = broadcaster.to(r);
  }
  broadcaster.emit(event, payload);
}

function clearCallTimer(callId) {
  const t = callTimeoutHandles.get(callId);
  if (t) {
    clearTimeout(t);
    callTimeoutHandles.delete(callId);
  }
}

const _callTransitionLocks = new Map();

async function withCallTransitionLock(callId, task) {
  const prev = _callTransitionLocks.get(callId) || Promise.resolve();
  let release;
  const current = new Promise((resolve) => {
    release = resolve;
  });
  const chained = prev.catch(() => {}).then(() => current);
  _callTransitionLocks.set(callId, chained);
  await prev.catch(() => {});
  try {
    return await task();
  } finally {
    release();
    if (_callTransitionLocks.get(callId) === chained) {
      _callTransitionLocks.delete(callId);
    }
  }
}

async function resolveDirectConversationId(userA, userB) {
  try {
    const a = normalizeId(userA);
    const b = normalizeId(userB);
    if (!a || !b || a === b) return '';
    const convo = await Conversation.findOne({
      isGroup: false,
      participants: { $all: [a, b] },
    })
      .select('_id')
      .lean();
    return convo?._id ? convo._id.toString() : '';
  } catch {
    return '';
  }
}

async function transitionCallSession(callId, toState, updates = {}) {
  if (!callId) return { ok: false, reason: 'missing_call_id', call: null };
  return withCallTransitionLock(callId, async () => {
    let memCall = activeCalls.get(callId);
    let dbCall = null;

    if (!memCall) {
      dbCall = await CallSession.findOne({ callId }).lean();
      if (dbCall) {
        memCall = {
          callId: dbCall.callId,
          correlationId: dbCall.correlationId,
          callerId: dbCall.callerId,
          callerName: dbCall.callerName,
          recipientId: dbCall.recipientId,
          recipientName: dbCall.recipientName,
          companyId: dbCall.companyId,
          mediaType: dbCall.mediaType,
          offer: dbCall.offer,
          answer: dbCall.answer,
          state: dbCall.state,
          actionStatus: dbCall.state === 'accepted' ? 'accepted' : 'pending',
          startedAt: dbCall.initiatedAt ? new Date(dbCall.initiatedAt).getTime() : Date.now(),
          expiresAt: dbCall.expiresAt ? new Date(dbCall.expiresAt).getTime() : Date.now() + CALL_RING_TIMEOUT_MS,
        };
      }
    }

    if (!memCall) {
      return { ok: false, reason: 'not_found', call: null };
    }

    const fromState = memCall.state || 'initiated';
    if (TERMINAL_CALL_STATES.has(fromState) || !isValidCallTransition(fromState, toState)) {
      return { ok: false, reason: `invalid_transition:${fromState}->${toState}`, call: memCall };
    }

    Object.assign(memCall, updates, { state: toState });
    if (toState === 'accepted') {
      memCall.actionStatus = 'accepted';
      memCall.acceptedAt = memCall.acceptedAt || new Date().toISOString();
    }
    if (TERMINAL_CALL_STATES.has(toState)) {
      clearCallTimer(callId);
      activeCalls.delete(callId);
    } else {
      activeCalls.set(callId, memCall);
    }

    const dbSet = {
      state: toState,
      ...updates,
      ...(toState === 'ringing' ? { ringingAt: new Date() } : {}),
      ...(toState === 'accepted' ? { acceptedAt: new Date() } : {}),
      ...(TERMINAL_CALL_STATES.has(toState) ? { endedAt: new Date() } : {}),
    };

    await CallSession.updateOne({ callId }, { $set: dbSet }).catch(() => {});

    logCommEvent('call:state_transition', {
      callId,
      correlationId: memCall.correlationId,
      from: fromState,
      to: toState,
      callerId: memCall.callerId,
      recipientId: memCall.recipientId,
    });

    return { ok: true, call: memCall, previousState: fromState };
  });
}

function scheduleCallTimeout(callId) {
  clearCallTimer(callId);
  const handle = setTimeout(async () => {
    try {
      callTimeoutHandles.delete(callId);
      const res = await transitionCallSession(callId, 'missed', { reason: 'timeout' });
      if (!res.ok || !res.call) return;
      const call = res.call;

      logCommEvent('call:timeout', {
        callId,
        correlationId: call.correlationId,
        callerId: call.callerId,
        recipientId: call.recipientId,
      });

      await Notification.updateOne(
        { id: `call-notif-${callId}` },
        { $set: { actionStatus: 'missed', read: true } }
      ).catch(() => {});

      const [callerRooms, recipientRooms] = await Promise.all([
        resolveUserRooms(call.callerId),
        resolveUserRooms(call.recipientId),
      ]);
      const allRooms = new Set([...callerRooms, ...recipientRooms]);

      broadcastToRooms(allRooms, 'call:state', {
        callId,
        correlationId: call.correlationId,
        state: 'missed',
        reason: 'timeout',
      });
      broadcastToRooms(allRooms, 'call:cancelled', {
        callId,
        correlationId: call.correlationId,
        callerId: call.callerId,
        reason: 'timeout',
        wasPending: true,
      });
      broadcastToRooms(allRooms, 'call:ended', {
        callId,
        correlationId: call.correlationId,
        endedBy: 'system',
        reason: 'timeout',
        wasPending: true,
      });

      await Promise.all([
        sendFcmPushToUsers({
          userIds: Array.from(recipientRooms).map((r) => r.replace(/^user:/, '')),
          dataOnly: true,
          highPriority: true,
          correlationId: call.correlationId,
          ttlSeconds: 30,
          data: {
            type: 'call_cancelled',
            callId,
            reason: 'timeout',
            callerId: call.callerId,
            callerName: call.callerName || 'Someone',
            mediaType: call.mediaType || 'voice',
          },
        }),
      ]);

      const conversationId = await resolveDirectConversationId(call.callerId, call.recipientId);
      const missedNotifId = `missed-${callId}`;
      const missedNotifData = {
        id: missedNotifId,
        companyId: call.companyId || null,
        userId: call.recipientId,
        title: `Missed ${call.mediaType === 'video' ? 'Video' : 'Voice'} Call`,
        message: `${call.callerName || 'Someone'} called you`,
        type: 'missed_call',
        senderId: call.callerId,
        senderName: call.callerName || 'Someone',
        callId,
        conversationId,
        metadata: {
          mediaType: call.mediaType || 'voice',
          callId,
          callerId: call.callerId,
          conversationId,
          reason: 'timeout',
        },
        createdAt: new Date().toISOString(),
        read: false,
      };
      const missedNotif = await Notification.findOneAndUpdate(
        { id: missedNotifId },
        { $setOnInsert: missedNotifData },
        { upsert: true, new: true }
      ).catch(() => new Notification(missedNotifData));
      broadcastToRooms(recipientRooms, 'notification:new', missedNotif);

      await sendFcmPushToUsers({
        userIds: Array.from(recipientRooms).map((r) => r.replace(/^user:/, '')),
        title: missedNotifData.title,
        body: missedNotifData.message,
        channelId: 'regen_missed_calls_v2',
        highPriority: true,
        dataOnly: false,
        correlationId: call.correlationId,
        data: {
          type: 'missed_call',
          notificationId: missedNotifId,
          callId,
          callerId: call.callerId,
          callerName: call.callerName || 'Someone',
          mediaType: call.mediaType || 'voice',
          conversationId,
        },
      });
    } catch (err) {
      logCommEvent('call:timeout_error', { callId, error: err.message });
    }
  }, CALL_RING_TIMEOUT_MS);

  if (typeof handle.unref === 'function') handle.unref();
  callTimeoutHandles.set(callId, handle);
}

/**
 * Initialise Socket.IO on an existing HTTP server.
 * Call once from index.js after `app.listen()`.
 */
export function initSocketIO(httpServer) {
  io = new Server(httpServer, {
    cors: { origin: '*', methods: ['GET', 'POST'] },
    path: '/ws', // matches website frontend & Flutter
    transports: ['websocket', 'polling'],
    pingInterval: 20000,
    pingTimeout: 20000,
    allowEIO3: true,
    connectionStateRecovery: {
      maxDisconnectionDuration: 2 * 60 * 1000,
      skipMiddlewares: false,
    },
  });

  // ── Auth middleware ──────────────────────────────────────────────
  io.use(async (socket, next) => {
    const corr = createCorrelationId('auth');
    try {
      const token = socket.handshake.auth?.token || socket.handshake.query?.token;
      if (!token) {
        logCommEvent('socket:auth_rejected', { correlationId: corr, reason: 'missing_token' });
        return next(new Error('Authentication required'));
      }

      const secret = process.env.JWT_SECRET;
      if (!secret) return next(new Error('Server misconfigured'));

      const decoded = jwt.verify(token, secret);
      const actor = await resolveMessengerActor(decoded.userId, decoded.role);
      if (!actor) {
        logCommEvent('socket:auth_rejected', { correlationId: corr, userId: decoded.userId, reason: 'invalid_session' });
        return next(new Error('Invalid session'));
      }
      if (actor.role !== 'param' && actor.status === 'inactive') {
        logCommEvent('socket:auth_rejected', { correlationId: corr, userId: actor.userId, reason: 'suspended' });
        return next(new Error('Account suspended'));
      }

      // Enforce tokenVersion check against DB (reject stale JWTs after password change/suspension/logout)
      let currentTokenVersion = 0;
      if (actor.role === 'param') {
        const sa = await SuperAdmin.findOne({ adminId: actor.userId }).select('tokenVersion').lean();
        currentTokenVersion = Number(sa?.tokenVersion || 0);
      } else {
        const dbUser = await User.findOne({ userId: actor.userId }).select('tokenVersion').lean();
        currentTokenVersion = Number(dbUser?.tokenVersion || 0);
      }
      if (Number(decoded.tokenVersion || 0) !== currentTokenVersion) {
        logCommEvent('socket:auth_rejected', { correlationId: corr, userId: actor.userId, reason: 'token_version_mismatch' });
        return next(new Error('Session expired'));
      }

      socket.userRooms = await resolveUserRooms(actor.userId);

      socket.user = {
        userId: actor.userId,
        username: actor.username,
        name: actor.name,
        role: actor.role,
        companyId: actor.companyId,
        isSuperAdmin: actor.isSuperAdmin,
        isOwnerOrAdmin: actor.isOwnerOrAdmin,
        isEmployee: actor.isEmployee,
        status: actor.status,
        deviceId: String(socket.handshake.auth?.deviceId || socket.id),
      };

      next();
    } catch (err) {
      logCommEvent('socket:auth_failed', { correlationId: corr, error: err.message });
      next(new Error('Invalid token'));
    }
  });

  // ── Connection handler ───────────────────────────────────────────
  io.on('connection', (socket) => {
    if (!socket.user || !socket.user.userId) {
      logCommEvent('socket:missing_user_guard', { socketId: socket.id, recovered: socket.recovered === true });
      socket.disconnect(true);
      return;
    }
    const { userId, role, companyId, deviceId } = socket.user;
    const connCorr = createCorrelationId('conn');

    // Join global room for SuperAdmin
    if (role === 'param') {
      socket.join('global');
    }

    // Join all pre-resolved user identifier alias rooms synchronously before registering listeners
    const myRooms = socket.userRooms instanceof Set ? socket.userRooms : new Set([`user:${userId}`]);
    myRooms.forEach((room) => socket.join(room));

    // Join company room (strictly validated from DB via socket.user.companyId)
    if (companyId) {
      socket.join(`company:${companyId}`);
    }

    // Track online presence per device socket
    if (!onlineUserSockets.has(userId)) {
      onlineUserSockets.set(userId, new Set());
    }
    const userSockets = onlineUserSockets.get(userId);
    const wasOffline = userSockets.size === 0;
    userSockets.add(socket.id);

    logCommEvent('socket:connected', {
      correlationId: connCorr,
      userId,
      role,
      socketId: socket.id,
      deviceId,
      transport: socket.conn?.transport?.name || 'unknown',
      recovered: socket.recovered === true,
      deviceCount: userSockets.size,
      roomsCount: myRooms.size,
    });

    if (wasOffline) {
      const nowIso = new Date().toISOString();
      const presencePayload = { userId, online: true, status: 'online', lastActive: nowIso };
      if (companyId) {
        io.to(`company:${companyId}`).emit('presence:update', presencePayload);
      }
      if (socket.user.isOwnerOrAdmin || socket.user.isSuperAdmin) {
        io.to('global').emit('presence:update', presencePayload);
      }
    }

    // Send live presence snapshot to the newly connected socket so indicators populate immediately
    socket.emit('presence:snapshot', {
      onlineUserIds: Array.from(onlineUserSockets.keys()),
      timestamp: new Date().toISOString(),
    });

    // Helper: push any pending incoming calls targeting this user on connect/reconnect/sync
    const syncPendingCallsToSocket = async () => {
      try {
        const aliasUserIds = Array.from(myRooms).map((r) => r.replace(/^user:/, ''));
        const pendingCalls = await CallSession.find({
          recipientId: { $in: aliasUserIds },
          state: { $in: ['initiated', 'ringing'] },
          expiresAt: { $gt: new Date() },
        }).sort({ initiatedAt: -1 }).lean();

        for (const call of pendingCalls) {
          if (!activeCalls.has(call.callId)) {
            activeCalls.set(call.callId, {
              ...call,
              startedAt: call.initiatedAt ? new Date(call.initiatedAt).getTime() : Date.now(),
              expiresAt: call.expiresAt ? new Date(call.expiresAt).getTime() : Date.now() + CALL_RING_TIMEOUT_MS,
            });
          }
          if (call.state === 'initiated') {
            await CallSession.updateOne(
              { callId: call.callId, state: 'initiated' },
              { $set: { state: 'ringing', ringingAt: new Date() } }
            ).catch(() => {});
            const cached = activeCalls.get(call.callId);
            if (cached && cached.state === 'initiated') cached.state = 'ringing';
            const callerRooms = await resolveUserRooms(call.callerId);
            broadcastToRooms(callerRooms, 'call:state', {
              callId: call.callId,
              correlationId: call.correlationId,
              state: 'ringing',
              recipientId: userId,
            });
          }
          socket.emit('call:incoming', {
            callId: call.callId,
            correlationId: call.correlationId,
            callerId: call.callerId,
            callerName: call.callerName || 'Someone',
            mediaType: call.mediaType || 'voice',
            offer: call.offer,
            recoveredOnSync: true,
          });
          logCommEvent('call:synced_on_connect', {
            callId: call.callId,
            correlationId: call.correlationId,
            recipientId: userId,
            socketId: socket.id,
          });
        }
      } catch (err) {
        logCommEvent('call:sync_error', { userId, error: err.message });
      }
    };

    // ── Active Conversation Tracking ───────────────────────────────
    socket.on('dm:join-conversation', async (data) => {
      try {
        const convId = data?.conversationId ? String(data.conversationId) : null;
        if (!convId) return;
        const convo = await Conversation.findById(convId).select('participants companyId isGroup scope').lean();
        if (!convo) return;
        const access = canAccessConversation(socket.user, convo);
        if (!access.allowed) return;
        socketActiveConversations.set(socket.id, { userId: String(userId), conversationId: convId });
        socket.join(`dm:${convId}`);
      } catch (_) {}
    });

    socket.on('dm:leave-conversation', (data) => {
      const convId = data?.conversationId ? String(data.conversationId) : null;
      const current = socketActiveConversations.get(socket.id);
      if (current && (!convId || current.conversationId === convId)) {
        socketActiveConversations.delete(socket.id);
      }
      if (convId) {
        socket.leave(`dm:${convId}`);
      }
    });

    socket.on('dm:read', async (data) => {
      try {
        const convId = data?.conversationId ? String(data.conversationId) : null;
        if (!convId) return;
        const convo = await Conversation.findById(convId);
        if (!convo) return;
        const access = canAccessConversation(socket.user, convo);
        if (!access.allowed) return;

        const upd = await DirectMessage.updateMany(
          { conversationId: convo._id, senderId: { $ne: String(userId) }, readBy: { $ne: String(userId) } },
          { $addToSet: { readBy: String(userId) } }
        );
        if (upd?.modifiedCount > 0) {
          await emitToParticipantsAndRoom(convo.participants, `dm:${convo._id.toString()}`, 'dm:change', {
            action: 'read',
            conversationId: convo._id.toString(),
            userId: String(userId),
            readBy: [String(userId)],
          });
        }
      } catch (err) {
        logCommEvent('dm:read_error', { userId, error: err.message });
      }
    });

    // ── Authoritative 1-to-1 WebRTC Call Signaling ─────────────────
    socket.on('call:initiate', async (data, ackCallback) => {
      const correlationId = createCorrelationId('call');
      try {
        const { callId, recipientId, mediaType, offer } = data || {};
        const targetId = normalizeId(recipientId);
        if (!targetId || !callId) {
          if (typeof ackCallback === 'function') ackCallback({ ok: false, reason: 'invalid_payload' });
          return;
        }

        // Idempotency / duplicate protection for existing callId
        const existingDb = await CallSession.findOne({ callId }).lean();
        if (existingDb) {
          if (TERMINAL_CALL_STATES.has(existingDb.state)) {
            socket.emit('call:state', { callId, state: existingDb.state, reason: existingDb.reason || 'expired' });
            if (typeof ackCallback === 'function') ackCallback({ ok: false, state: existingDb.state, reason: 'already_terminal' });
            return;
          }
          if (typeof ackCallback === 'function') ackCallback({ ok: true, callId, state: existingDb.state, deduplicated: true });
          return;
        }

        const targetActor = await resolveMessengerActor(targetId);
        const authCheck = canCommunicate(socket.user, targetActor);
        if (!authCheck.allowed) {
          logCommEvent('call:unauthorized', { callId, correlationId, callerId: userId, targetId, reason: authCheck.reason });
          socket.emit('call:rejected', {
            callId,
            correlationId,
            recipientId: targetId,
            reason: authCheck.reason || 'unauthorized',
          });
          if (typeof ackCallback === 'function') ackCallback({ ok: false, reason: authCheck.reason || 'unauthorized' });
          return;
        }

        // Busy check: if recipient already has an active accepted or live ringing call, fail fast with busy
        const busyCall = await CallSession.findOne({
          $or: [
            { state: 'accepted', expiresAt: { $gt: new Date(Date.now() - 3600000) } },
            { state: { $in: ['initiated', 'ringing'] }, expiresAt: { $gt: new Date() } },
          ],
          $and: [
            {
              $or: [
                { callerId: targetActor.userId },
                { recipientId: targetActor.userId },
              ],
            },
          ],
        }).lean();

        const callerName = socket.user?.name || socket.user?.username || 'Someone';
        const callMediaType = mediaType === 'video' ? 'video' : 'voice';
        const notifType = callMediaType === 'video' ? 'video_call' : 'voice_call';
        const targetRooms = await resolveUserRooms(targetActor.userId);
        const recipientSocketCount = Array.from(targetRooms).reduce((cnt, roomName) => {
          const room = io?.sockets?.adapter?.rooms?.get(roomName);
          return cnt + (room ? room.size : 0);
        }, 0);

        if (busyCall && busyCall.callId !== callId) {
          logCommEvent('call:recipient_busy', { callId, correlationId, callerId: userId, recipientId: targetActor.userId });
          socket.emit('call:rejected', {
            callId,
            correlationId,
            recipientId: targetActor.userId,
            reason: 'busy',
          });
          if (typeof ackCallback === 'function') ackCallback({ ok: false, reason: 'busy' });
          return;
        }

        const initialState = recipientSocketCount > 0 ? 'ringing' : 'initiated';
        const now = Date.now();
        const expiresAt = new Date(now + CALL_RING_TIMEOUT_MS);

        const callRecord = {
          callId,
          correlationId,
          callerId: userId,
          callerName,
          recipientId: targetActor.userId,
          recipientName: targetActor.name || targetActor.username || '',
          companyId: socket.user.companyId || targetActor.companyId || null,
          mediaType: callMediaType,
          offer,
          callerCandidates: [],
          recipientCandidates: [],
          state: initialState,
          actionStatus: 'pending',
          startedAt: now,
          expiresAt: expiresAt.getTime(),
        };

        activeCalls.set(callId, callRecord);
        await CallSession.create({
          callId,
          correlationId,
          callerId: userId,
          callerName,
          recipientId: targetActor.userId,
          recipientName: callRecord.recipientName,
          companyId: callRecord.companyId,
          mediaType: callMediaType,
          state: initialState,
          offer,
          callerCandidates: [],
          recipientCandidates: [],
          initiatedAt: new Date(now),
          ...(initialState === 'ringing' ? { ringingAt: new Date(now) } : {}),
          expiresAt,
        }).catch(() => {});

        scheduleCallTimeout(callId);

        // Persist notification for recipient
        const notifId = `call-notif-${callId}`;
        const existingNotif = await Notification.findOne({ id: notifId });
        let notif = existingNotif;
        if (!existingNotif) {
          notif = new Notification({
            id: notifId,
            companyId: callRecord.companyId,
            userId: targetActor.userId,
            title: callMediaType === 'video' ? 'Incoming Video Call' : 'Incoming Voice Call',
            message: `${callerName} is calling you...`,
            type: notifType,
            senderId: userId,
            senderName: callerName,
            callId,
            actionStatus: 'pending',
            metadata: { mediaType: callMediaType, callerName, callerId: userId, correlationId },
            createdAt: new Date().toISOString(),
            read: false,
          });
          await notif.save().catch(() => {});
        }

        const incomingPayload = {
          callId,
          correlationId,
          callerId: userId,
          callerName,
          mediaType: callMediaType,
          offer,
        };

        logCommEvent('call:initiate', {
          callId,
          correlationId,
          callerId: userId,
          recipientId: targetActor.userId,
          mediaType: callMediaType,
          state: initialState,
          recipientOnlineSockets: recipientSocketCount,
        });

        socket.emit('call:state', { callId, correlationId, state: initialState });
        broadcastToRooms(targetRooms, 'notification:new', notif);
        broadcastToRooms(targetRooms, 'call:incoming', incomingPayload);

        // Always dispatch FCM high-priority wakeup fallback (receiver deduplicates by callId if socket already delivered)
        const targetIds = Array.from(targetRooms).map((r) => r.replace(/^user:/, ''));
        sendFcmPushToUsers({
          userIds: targetIds,
          title: callMediaType === 'video' ? 'Incoming Video Call' : 'Incoming Voice Call',
          body: `${callerName} is calling you...`,
          channelId: 'regen_incoming_calls_v2',
          highPriority: true,
          dataOnly: true,
          ttlSeconds: 45,
          collapseKey: `call_${callId}`,
          correlationId,
          data: {
            type: notifType,
            callId,
            correlationId,
            callerId: userId,
            callerName,
            mediaType: callMediaType,
            sentAt: String(now),
          },
        }).then((pushRes) => {
          CallSession.updateOne(
            { callId },
            {
              $set: {
                pushDispatched: pushRes.sentCount > 0,
                pushResult: `sent=${pushRes.sentCount},failed=${pushRes.failedCount},configured=${pushRes.configured}`,
              },
            }
          ).catch(() => {});
        }).catch(() => {});

        if (typeof ackCallback === 'function') {
          ackCallback({ ok: true, callId, correlationId, state: initialState, recipientOnlineSockets: recipientSocketCount });
        }
      } catch (err) {
        logCommEvent('call:initiate_error', { correlationId, error: err.message });
        if (typeof ackCallback === 'function') ackCallback({ ok: false, reason: 'server_error' });
      }
    });

    // Receiver device acknowledges incoming call UI/ringtone started
    socket.on('call:ringing', async (data) => {
      try {
        const { callId } = data || {};
        if (!callId) return;
        const res = await transitionCallSession(callId, 'ringing');
        if (!res.ok || !res.call) return;
        const callerRooms = await resolveUserRooms(res.call.callerId);
        broadcastToRooms(callerRooms, 'call:state', {
          callId,
          correlationId: res.call.correlationId,
          state: 'ringing',
          recipientId: userId,
        });
      } catch (err) {
        logCommEvent('call:ringing_error', { userId, error: err.message });
      }
    });

    // Client requests offer & authoritative status for active call (or syncs pending calls after reconnect/resume)
    socket.on('call:get-active', async (data, callback) => {
      try {
        const callId = data?.callId;
        if (!callId) {
          if (typeof callback === 'function') callback(null);
          return;
        }
        let call = activeCalls.get(callId);
        if (!call) {
          call = await CallSession.findOne({ callId }).lean();
        }
        if (typeof callback === 'function') {
          if (
            call &&
            (call.recipientId === userId || call.callerId === userId) &&
            !TERMINAL_CALL_STATES.has(call.state) &&
            (!call.expiresAt || new Date(call.expiresAt).getTime() > Date.now())
          ) {
            callback(call);
          } else {
            callback(null);
          }
        }
      } catch (_) {
        if (typeof callback === 'function') callback(null);
      }
    });

    socket.on('call:sync', async (data, callback) => {
      try {
        await syncPendingCallsToSocket();
        const checkCallId = data?.callId ? String(data.callId) : null;
        let checkState = null;
        let callSnapshot = null;
        if (checkCallId) {
          const mem = activeCalls.get(checkCallId);
          if (mem) {
            checkState = mem.state;
            callSnapshot = mem;
          } else {
            const db = await CallSession.findOne({ callId: checkCallId }).lean();
            checkState = db?.state || 'ended';
            callSnapshot = db || null;
          }
        }
        if (typeof callback === 'function') {
          const isParticipant =
            callSnapshot &&
            (callSnapshot.callerId === userId || callSnapshot.recipientId === userId);
          callback({
            ok: true,
            callId: checkCallId,
            state: checkState,
            ...(isParticipant && callSnapshot
              ? {
                  answer: callSnapshot.answer || null,
                  offer: callSnapshot.offer || null,
                  callerCandidates: callSnapshot.callerCandidates || [],
                  recipientCandidates: callSnapshot.recipientCandidates || [],
                  callerId: callSnapshot.callerId,
                  callerName: callSnapshot.callerName,
                  recipientId: callSnapshot.recipientId,
                  mediaType: callSnapshot.mediaType || 'voice',
                  acceptedAt: callSnapshot.acceptedAt || null,
                }
              : {}),
          });
        }
      } catch (_) {
        if (typeof callback === 'function') callback({ ok: false });
      }
    });

    socket.on('call:accept', async (data, ackCallback) => {
      try {
        const { callId, callerId, answer, deviceId } = data || {};
        if (!callerId || !callId) {
          if (typeof ackCallback === 'function') ackCallback({ ok: false, reason: 'invalid_payload' });
          return;
        }

        const existingDb = activeCalls.get(callId) || (await CallSession.findOne({ callId }).lean());
        if (!existingDb) {
          socket.emit('call:ended', { callId, endedBy: 'system', reason: 'expired' });
          if (typeof ackCallback === 'function') ackCallback({ ok: false, reason: 'expired' });
          return;
        }

        if (existingDb.recipientId !== userId && existingDb.callerId !== userId) {
          if (typeof ackCallback === 'function') ackCallback({ ok: false, reason: 'unauthorized' });
          return;
        }

        if (TERMINAL_CALL_STATES.has(existingDb.state) || (existingDb.expiresAt && new Date(existingDb.expiresAt).getTime() < Date.now())) {
          socket.emit('call:ended', { callId, endedBy: 'system', reason: existingDb.state || 'expired' });
          if (typeof ackCallback === 'function') ackCallback({ ok: false, reason: existingDb.state || 'expired' });
          return;
        }

        const res = await transitionCallSession(callId, 'accepted', { answer });
        if (!res.ok) {
          socket.emit('call:ended', { callId, endedBy: 'system', reason: res.reason });
          if (typeof ackCallback === 'function') ackCallback({ ok: false, reason: res.reason });
          return;
        }

        await Notification.updateOne(
          { id: `call-notif-${callId}` },
          { $set: { actionStatus: 'accepted', read: true } }
        ).catch(() => {});

        const authCallerId = existingDb.callerId || callerId;
        const [callerRooms, receiverRooms] = await Promise.all([
          resolveUserRooms(authCallerId),
          resolveUserRooms(userId),
        ]);
        const acceptedByDeviceId = String(deviceId || '');

        broadcastToRooms(callerRooms, 'call:accepted', {
          callId,
          correlationId: res.call.correlationId,
          recipientId: userId,
          answer,
          recipientCandidates: res.call.recipientCandidates || [],
          acceptedBySocketId: socket.id,
          acceptedByDeviceId,
        });

        // Broadcast authoritative accepted state + answer to caller and receiver devices
        broadcastToRooms(callerRooms, 'call:state', {
          callId,
          correlationId: res.call.correlationId,
          state: 'accepted',
          recipientId: userId,
          answer,
          recipientCandidates: res.call.recipientCandidates || [],
          acceptedBySocketId: socket.id,
          acceptedByDeviceId,
        });

        broadcastToRooms(receiverRooms, 'call:state', {
          callId,
          correlationId: res.call.correlationId,
          state: 'accepted',
          acceptedBySocketId: socket.id,
          acceptedByDeviceId,
        });

        // Cancel background incoming call notifications on other receiver devices
        sendFcmPushToUsers({
          userIds: Array.from(receiverRooms).map((r) => r.replace(/^user:/, '')),
          dataOnly: true,
          highPriority: true,
          ttlSeconds: 15,
          correlationId: res.call.correlationId,
          data: {
            type: 'call_cancelled',
            callId,
            reason: 'accepted_elsewhere',
            acceptedBySocketId: socket.id,
            acceptedByDeviceId,
          },
        }).catch(() => {});

        if (typeof ackCallback === 'function') ackCallback({ ok: true, callId, state: 'accepted' });
      } catch (err) {
        logCommEvent('call:accept_error', { userId, error: err.message });
        if (typeof ackCallback === 'function') ackCallback({ ok: false, reason: 'server_error' });
      }
    });

    socket.on('call:reject', async (data) => {
      try {
        const { callId, callerId, reason } = data || {};
        if (!callerId || !callId) return;

        const existingCall = activeCalls.get(callId) || (await CallSession.findOne({ callId }).lean());
        if (!existingCall) return;
        if (existingCall.state === 'accepted' || TERMINAL_CALL_STATES.has(existingCall.state)) {
          return; // Never terminate an already accepted or terminal call from duplicate reject packets
        }
        if (existingCall.recipientId !== userId && existingCall.callerId !== userId) {
          return;
        }

        const res = await transitionCallSession(callId, 'rejected', { reason: reason || 'declined' });
        if (!res.ok) return;

        await Notification.updateOne(
          { id: `call-notif-${callId}` },
          { $set: { actionStatus: 'rejected', read: true } }
        ).catch(() => {});

        const [callerRooms, receiverRooms] = await Promise.all([
          resolveUserRooms(callerId),
          resolveUserRooms(userId),
        ]);
        const allRooms = new Set([...callerRooms, ...receiverRooms]);

        broadcastToRooms(callerRooms, 'call:rejected', {
          callId,
          correlationId: res.call.correlationId,
          recipientId: userId,
          reason: reason || 'declined',
        });
        broadcastToRooms(allRooms, 'call:state', {
          callId,
          correlationId: res.call.correlationId,
          state: 'rejected',
          reason: reason || 'declined',
        });

        sendFcmPushToUsers({
          userIds: Array.from(receiverRooms).map((r) => r.replace(/^user:/, '')),
          dataOnly: true,
          highPriority: true,
          ttlSeconds: 15,
          correlationId: res.call.correlationId,
          data: { type: 'call_cancelled', callId, reason: reason || 'declined' },
        }).catch(() => {});
      } catch (err) {
        logCommEvent('call:reject_error', { userId, error: err.message });
      }
    });

    socket.on('call:signal', async (data) => {
      try {
        const { targetUserId, signal, callId } = data || {};
        const targetId = normalizeId(targetUserId);
        if (!targetId || !callId) return;

        // Validate call isn't already terminal (prevent late signaling resurrecting expired calls)
        const existing = activeCalls.get(callId) || (await CallSession.findOne({ callId }).lean());
        if (existing && TERMINAL_CALL_STATES.has(existing.state)) {
          return;
        }

        // Buffer trickle ICE candidates on the call session so waking/reconnecting peers never lose candidates
        if (signal && signal.candidate && existing) {
          const isCallerSignal = String(existing.callerId) === String(userId);
          const candField = isCallerSignal ? 'callerCandidates' : 'recipientCandidates';
          if (Array.isArray(existing[candField])) {
            existing[candField].push(signal.candidate);
          } else {
            existing[candField] = [signal.candidate];
          }
          CallSession.updateOne(
            { callId },
            { $push: { [candField]: signal.candidate } }
          ).catch(() => {});
        }

        const targetActor = await resolveMessengerActor(targetId);
        const authCheck = canCommunicate(socket.user, targetActor);
        if (!authCheck.allowed) return;

        const targetRooms = await resolveUserRooms(targetActor.userId);
        broadcastToRooms(targetRooms, 'call:signal', {
          senderId: userId,
          signal,
          callId,
        });
      } catch (err) {
        logCommEvent('call:signal_error', { userId, error: err.message });
      }
    });

    socket.on('call:end', async (data) => {
      try {
        const { targetUserId, callId, reason } = data || {};
        if (!callId) return;

        const existingCall = activeCalls.get(callId) || (await CallSession.findOne({ callId }).lean());
        if (!existingCall || TERMINAL_CALL_STATES.has(existingCall.state)) {
          return;
        }

        const wasPending = existingCall.state === 'initiated' || existingCall.state === 'ringing';
        const nextState = wasPending ? 'cancelled' : 'ended';
        const res = await transitionCallSession(callId, nextState, { reason: reason || (wasPending ? 'cancelled' : 'hangup') });
        if (!res.ok) return;

        await Notification.updateOne(
          { id: `call-notif-${callId}` },
          { $set: { actionStatus: wasPending ? 'missed' : 'ended', read: true } }
        ).catch(() => {});

        const otherPartyId = normalizeId(targetUserId) || (existingCall.callerId === userId ? existingCall.recipientId : existingCall.callerId);
        const [otherRooms, myUserRooms] = await Promise.all([
          otherPartyId ? resolveUserRooms(otherPartyId) : Promise.resolve(new Set()),
          resolveUserRooms(userId),
        ]);
        const allRooms = new Set([...otherRooms, ...myUserRooms]);

        broadcastToRooms(allRooms, 'call:state', {
          callId,
          correlationId: res.call.correlationId,
          state: nextState,
          endedBy: userId,
          wasPending,
        });
        broadcastToRooms(allRooms, 'call:ended', {
          callId,
          correlationId: res.call.correlationId,
          endedBy: userId,
          wasPending,
          reason: nextState,
        });
        if (wasPending) {
          broadcastToRooms(allRooms, 'call:cancelled', {
            callId,
            correlationId: res.call.correlationId,
            callerId: userId,
            wasPending: true,
            reason: 'cancelled',
          });
        }

        if (wasPending && otherPartyId) {
          const callerName = socket.user?.name || socket.user?.username || 'Someone';
          const mediaType = existingCall?.mediaType || 'voice';
          const recipientIds = Array.from(otherRooms).map((r) => r.replace(/^user:/, ''));

          await sendFcmPushToUsers({
            userIds: recipientIds,
            dataOnly: true,
            highPriority: true,
            ttlSeconds: 20,
            correlationId: res.call.correlationId,
            data: { type: 'call_cancelled', callId, reason: 'cancelled' },
          }).catch(() => {});

          const conversationId = await resolveDirectConversationId(userId, existingCall.recipientId);
          const missedNotifId = `missed-${callId}`;
          const missedNotifData = {
            id: missedNotifId,
            companyId: socket.user.companyId || null,
            userId: existingCall.recipientId,
            title: `Missed ${mediaType === 'video' ? 'Video' : 'Voice'} Call`,
            message: `${callerName} called you`,
            type: 'missed_call',
            senderId: userId,
            senderName: callerName,
            callId,
            conversationId,
            metadata: { mediaType, callId, callerId: userId, conversationId },
            createdAt: new Date().toISOString(),
            read: false,
          };
          const missedNotif = await Notification.findOneAndUpdate(
            { id: missedNotifId },
            { $setOnInsert: missedNotifData },
            { upsert: true, new: true }
          ).catch(() => new Notification(missedNotifData));
          broadcastToRooms(otherRooms, 'notification:new', missedNotif);

          await sendFcmPushToUsers({
            userIds: recipientIds,
            title: missedNotifData.title,
            body: missedNotifData.message,
            channelId: 'regen_missed_calls_v2',
            highPriority: true,
            dataOnly: false,
            correlationId: res.call.correlationId,
            data: {
              type: 'missed_call',
              notificationId: missedNotifId,
              callId,
              callerId: userId,
              callerName,
              mediaType,
              conversationId,
            },
          }).catch(() => {});
        }
      } catch (err) {
        logCommEvent('call:end_error', { userId, error: err.message });
      }
    });

    // ── Group / Team Voice & Video Meeting Signaling (WebRTC Mesh with ACLs) ──
    socket.on('meeting:start', async (data) => {
      const correlationId = createCorrelationId('mtg');
      try {
        const { meetingId, title, mediaType, conversationId, participantIds } = data || {};
        if (!meetingId) return;

        const hostName = socket.user?.name || socket.user?.username || 'Team Lead';
        const effectiveMediaType = mediaType === 'voice' ? 'voice' : 'video';
        const allowedUserIds = new Set([userId]);
        let invitedActors = [];
        let meetingScope = socket.user.isSuperAdmin ? 'superadmin_owners' : 'company';
        let meetingCompanyId = socket.user.companyId || null;

        if (conversationId && mongoose.isValidObjectId(conversationId)) {
          const convo = await Conversation.findById(conversationId).lean();
          const access = canAccessConversation(socket.user, convo);
          if (!access.allowed) {
            socket.emit('meeting:error', { meetingId, message: access.reason || 'Unauthorized' });
            return;
          }
          meetingScope = convo.scope || meetingScope;
          meetingCompanyId = convo.companyId ? convo.companyId.toString() : meetingCompanyId;
          for (const pid of convo.participants || []) {
            const pNorm = normalizeId(pid);
            if (!pNorm) continue;
            allowedUserIds.add(pNorm);
            if (pNorm !== userId) {
              const target = await resolveMessengerActor(pNorm);
              if (target && target.status !== 'inactive') invitedActors.push(target);
            }
          }
        } else if (Array.isArray(participantIds) && participantIds.length > 0) {
          for (const rawPid of participantIds) {
            const pid = normalizeId(rawPid);
            if (!pid || pid === userId) continue;
            const target = await resolveMessengerActor(pid);
            const authCheck = canCommunicate(socket.user, target);
            if (authCheck.allowed) {
              allowedUserIds.add(target.userId);
              invitedActors.push(target);
            }
          }
          if (invitedActors.length === 0) {
            socket.emit('meeting:error', { meetingId, message: 'No authorized participants selected' });
            return;
          }
        } else if (meetingCompanyId) {
          const isOid = mongoose.isValidObjectId(meetingCompanyId);
          const companyFilter = isOid
            ? { $in: [meetingCompanyId, new mongoose.Types.ObjectId(meetingCompanyId)] }
            : meetingCompanyId;

          const members = await User.find({
            companyId: companyFilter,
            userId: { $ne: userId },
            status: { $ne: 'inactive' },
          }).select('userId _id username name companyId').lean();

          for (const m of members) {
            allowedUserIds.add(m.userId);
            invitedActors.push({
              userId: m.userId,
              companyId: m.companyId?.toString() || meetingCompanyId,
            });
          }
        } else {
          socket.emit('meeting:error', { meetingId, message: 'Select participants to start a group call' });
          return;
        }

        const meetingTitle = title || (effectiveMediaType === 'voice' ? 'Group Voice Call' : 'Team Meeting');
        activeMeetings.set(meetingId, {
          meetingId,
          correlationId,
          title: meetingTitle,
          hostId: userId,
          hostName,
          mediaType: effectiveMediaType,
          companyId: meetingCompanyId,
          conversationId: conversationId || null,
          scope: meetingScope,
          allowedUserIds,
          createdAt: Date.now(),
        });

        const meetingPayload = {
          meetingId,
          correlationId,
          title: meetingTitle,
          hostId: userId,
          hostName,
          mediaType: effectiveMediaType,
          companyId: meetingCompanyId,
          conversationId: conversationId || null,
        };

        logCommEvent('meeting:start', {
          meetingId,
          correlationId,
          hostId: userId,
          invitedCount: invitedActors.length,
          mediaType: effectiveMediaType,
        });

        const pushRecipientIds = [];
        for (const m of invitedActors) {
          pushRecipientIds.push(m.userId);
          const notif = new Notification({
            id: `meeting-notif-${meetingId}-${m.userId}`,
            companyId: meetingCompanyId || m.companyId || null,
            userId: m.userId,
            title: effectiveMediaType === 'voice' ? 'Group Voice Call Started' : 'Team Meeting Started',
            message: `${hostName} started ${meetingTitle}`,
            type: 'team_meeting',
            senderId: userId,
            senderName: hostName,
            meetingId,
            conversationId: conversationId || undefined,
            actionStatus: 'pending',
            metadata: {
              title: meetingTitle,
              mediaType: effectiveMediaType,
              hostName,
              hostId: userId,
              conversationId: conversationId || null,
            },
            createdAt: new Date().toISOString(),
            read: false,
          });
          await notif.save().catch(() => {});
          const targetRooms = await resolveUserRooms(m.userId);
          broadcastToRooms(targetRooms, 'notification:new', notif);
          broadcastToRooms(targetRooms, 'meeting:started', meetingPayload);
        }

        if (pushRecipientIds.length > 0) {
          sendFcmPushToUsers({
            userIds: pushRecipientIds,
            title: meetingTitle,
            body: `${hostName} started a ${effectiveMediaType === 'voice' ? 'group voice call' : 'team video call'}`,
            channelId: 'regen_incoming_calls_v2',
            highPriority: true,
            dataOnly: true,
            ttlSeconds: 45,
            correlationId,
            data: {
              type: 'team_meeting',
              meetingId,
              callId: meetingId,
              callerId: userId,
              callerName: hostName,
              title: meetingTitle,
              mediaType: effectiveMediaType,
              conversationId: conversationId || '',
            },
          }).catch(() => {});
        }

        if (!conversationId && (!Array.isArray(participantIds) || participantIds.length === 0) && meetingCompanyId) {
          io.to(`company:${meetingCompanyId}`).emit('meeting:started', meetingPayload);
        }
      } catch (err) {
        logCommEvent('meeting:start_error', { correlationId, error: err.message });
      }
    });

    socket.on('meeting:get-active', (data, callback) => {
      try {
        const meetingId = data?.meetingId ? String(data.meetingId) : null;
        if (!meetingId) {
          if (typeof callback === 'function') callback(null);
          return;
        }
        const meeting = activeMeetings.get(meetingId);
        if (!meeting) {
          if (typeof callback === 'function') callback(null);
          return;
        }
        const inAllowList = meeting.allowedUserIds?.has(userId);
        const sameCompanyTeamMeeting =
          meeting.scope === 'company' && companyId && meeting.companyId === companyId;
        if (!inAllowList && !sameCompanyTeamMeeting) {
          if (typeof callback === 'function') callback(null);
          return;
        }
        if (typeof callback === 'function') {
          callback({
            meetingId: meeting.meetingId,
            title: meeting.title,
            hostId: meeting.hostId,
            hostName: meeting.hostName,
            mediaType: meeting.mediaType || 'video',
            companyId: meeting.companyId || null,
            conversationId: meeting.conversationId || null,
          });
        }
      } catch (_) {
        if (typeof callback === 'function') callback(null);
      }
    });

    socket.on('meeting:join', async (data) => {
      try {
        const { meetingId, userInfo } = data || {};
        if (!meetingId) return;

        const meeting = activeMeetings.get(meetingId);
        if (meeting) {
          const inAllowList = meeting.allowedUserIds.has(userId);
          const sameCompanyTeamMeeting =
            meeting.scope === 'company' &&
            !meeting.conversationId &&
            meeting.companyId &&
            socket.user.companyId &&
            String(meeting.companyId) === String(socket.user.companyId);

          if (!inAllowList && !sameCompanyTeamMeeting) {
            socket.emit('meeting:error', {
              meetingId,
              message: 'Access denied: you are not authorized to join this call',
            });
            return;
          }
        }

        socket.join(`meeting:${meetingId}`);

        socket.to(`meeting:${meetingId}`).emit('meeting:user-joined', {
          meetingId,
          userId,
          userInfo: userInfo || {
            userId,
            username: socket.user.name || socket.user.username,
          },
        });

        const socketsInRoom = await io.in(`meeting:${meetingId}`).fetchSockets();
        const seen = new Set();
        const existingUsers = [];
        for (const s of socketsInRoom) {
          if (s.id !== socket.id && s.user?.userId && !seen.has(s.user.userId)) {
            seen.add(s.user.userId);
            existingUsers.push({
              userId: s.user.userId,
              username: s.user.name || s.user.username || 'Colleague',
            });
          }
        }
        socket.emit('meeting:existing-users', {
          meetingId,
          users: existingUsers,
        });
      } catch (err) {
        logCommEvent('meeting:join_error', { userId, error: err.message });
      }
    });

    socket.on('meeting:signal', async (data) => {
      try {
        const { targetUserId, signal, meetingId } = data || {};
        const targetId = normalizeId(targetUserId);
        if (!targetId || !meetingId) return;
        if (!socket.rooms.has(`meeting:${meetingId}`)) return;

        const targetActor = await resolveMessengerActor(targetId);
        const authCheck = canCommunicate(socket.user, targetActor);
        if (!authCheck.allowed) return;

        const targetRooms = await resolveUserRooms(targetActor.userId);
        broadcastToRooms(targetRooms, 'meeting:signal', {
          fromUserId: userId,
          fromUsername: socket.user?.name || socket.user?.username || 'Colleague',
          signal,
          meetingId,
        });
      } catch (err) {
        logCommEvent('meeting:signal_error', { userId, error: err.message });
      }
    });

    socket.on('meeting:leave', async (data) => {
      const { meetingId } = data || {};
      if (!meetingId) return;
      socket.leave(`meeting:${meetingId}`);
      socket.to(`meeting:${meetingId}`).emit('meeting:user-left', {
        meetingId,
        userId,
      });

      try {
        const remaining = await io.in(`meeting:${meetingId}`).fetchSockets();
        if (remaining.length === 0) {
          activeMeetings.delete(meetingId);
        }
      } catch {}
    });

    socket.on('disconnect', (reason) => {
      // Remove only THIS socket's active conversation tracking (preserves other devices/tabs)
      socketActiveConversations.delete(socket.id);

      const sockets = onlineUserSockets.get(userId);
      let remainingSockets = 0;
      if (sockets) {
        sockets.delete(socket.id);
        remainingSockets = sockets.size;
        if (sockets.size === 0) {
          onlineUserSockets.delete(userId);
          const nowIso = new Date().toISOString();
          const presencePayload = { userId, online: false, status: 'offline', lastActive: nowIso };
          if (companyId) {
            io.to(`company:${companyId}`).emit('presence:update', presencePayload);
          }
          if (socket.user.isOwnerOrAdmin || socket.user.isSuperAdmin) {
            io.to('global').emit('presence:update', presencePayload);
          }
          // Update persistent lastActive timestamp cleanly
          if (role === 'param') {
            SuperAdmin.updateOne({ adminId: userId }, { $set: { lastActive: new Date() } }).catch(() => {});
          } else {
            User.updateOne({ userId }, { $set: { lastActive: new Date() } }).catch(() => {});
          }
        }
      }

      logCommEvent('socket:disconnected', {
        userId,
        socketId: socket.id,
        reason,
        remainingSockets,
      });
    });

    // Run pending-call sync asynchronously AFTER all socket handlers are registered
    void syncPendingCallsToSocket();
  });

  return io;
}

export function getIO() {
  return io;
}

export function emitToCompany(event, companyId, payload = {}) {
  if (!io) return;
  if (companyId) {
    io.to(`company:${companyId.toString()}`).emit(event, payload);
  }
  if (!event.startsWith('dm:')) {
    io.to('global').emit(event, payload);
  }
}

export async function emitToUser(userId, event, payload = {}) {
  if (!io || !userId) return;
  const targetRooms = await resolveUserRooms(userId);
  broadcastToRooms(targetRooms, event, payload);
}

/**
 * Emit once across all participant user-alias rooms AND an optional conversation room
 * using Socket.IO's multi-room chain so multi-room sockets receive only ONE packet.
 */
export async function emitToParticipantsAndRoom(participants, roomName, event, payload = {}) {
  if (!io) return;
  const roomSet = new Set();
  if (roomName) roomSet.add(roomName);
  const unique = Array.from(new Set((participants || []).map(normalizeId).filter(Boolean)));
  const perUserRooms = await Promise.all(unique.map((pid) => resolveUserRooms(pid)));
  for (const rSet of perUserRooms) {
    for (const r of rSet) roomSet.add(r);
  }
  broadcastToRooms(roomSet, event, payload);
}
