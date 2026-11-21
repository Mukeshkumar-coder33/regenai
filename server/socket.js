/**
 * Socket.IO server setup for real-time data synchronization & WebRTC signaling.
 *
 * Channels (rooms) are strictly role- & company-scoped:
 *   company:<companyId> — all users in a company get company events
 *   global              — SuperAdmin sees platform monitoring events
 *   user:<userId>       — targeted direct messages, 1:1 calls, notifications
 *   meeting:<meetingId> — authorized group voice/video call room (WebRTC Mesh)
 */
import { Server } from 'socket.io';
import jwt from 'jsonwebtoken';
import mongoose from 'mongoose';
import User from './models/User.js';
import SuperAdmin from './models/SuperAdmin.js';
import Conversation from './models/Conversation.js';
import Notification from './models/Notification.js';
import {
  resolveMessengerActor,
  canCommunicate,
  canAccessConversation,
  normalizeId
} from './utils/messengerAuth.js';

let io = null;

// In-memory active 1:1 calls cache for reliable WebRTC offer delivery across tabs & notification clicks
const activeCalls = new Map(); // callId -> { callId, callerId, callerName, recipientId, mediaType, offer, actionStatus, startedAt }

// In-memory active group/team meetings ACL cache for strict room authorization
const activeMeetings = new Map(); // meetingId -> { meetingId, title, hostId, hostName, mediaType, companyId, conversationId, scope, allowedUserIds: Set<string>, createdAt }

// In-memory online user tracking (userId -> Set<socket.id>)
const onlineUserSockets = new Map();

// In-memory active conversation tracking (userId -> conversationId)
const userActiveConversations = new Map();

/**
 * Return whether a user is currently actively viewing a specific conversation.
 */
export function isUserActiveInConversation(userId, conversationId) {
  if (!userId || !conversationId) return false;
  return userActiveConversations.get(String(userId)) === String(conversationId);
}

/**
 * Return the set of currently connected userIds.
 */
export function getOnlineUserIds() {
  return new Set(onlineUserSockets.keys());
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
          { username: strId },
          ...(isOid ? [{ _id: new mongoose.Types.ObjectId(strId) }] : [])
        ]
      }).select('_id userId username companyId').lean(),
      SuperAdmin.findOne({
        $or: [
          { adminId: strId },
          { username: strId },
          ...(isOid ? [{ _id: new mongoose.Types.ObjectId(strId) }] : [])
        ]
      }).select('_id adminId username').lean()
    ]);

    if (u) {
      if (u.userId) rooms.add(`user:${u.userId}`);
      if (u._id) rooms.add(`user:${u._id.toString()}`);
      if (u.username) rooms.add(`user:${u.username}`);
    }
    if (sa) {
      if (sa.adminId) rooms.add(`user:${sa.adminId}`);
      if (sa._id) rooms.add(`user:${sa._id.toString()}`);
      if (sa.username) rooms.add(`user:${sa.username}`);
    }
  } catch {}
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

/**
 * Initialise Socket.IO on an existing HTTP server.
 * Call once from index.js after `app.listen()`.
 */
export function initSocketIO(httpServer) {
  io = new Server(httpServer, {
    cors: { origin: '*', methods: ['GET', 'POST'] },
    path: '/ws', // matches existing website frontend/src/hooks/useSocket.js
    transports: ['websocket', 'polling'],
  });

  // ── Auth middleware ──────────────────────────────────────────────
  io.use(async (socket, next) => {
    try {
      const token = socket.handshake.auth?.token || socket.handshake.query?.token;
      if (!token) return next(new Error('Authentication required'));

      const secret = process.env.JWT_SECRET;
      if (!secret) return next(new Error('Server misconfigured'));

      const decoded = jwt.verify(token, secret);
      const actor = await resolveMessengerActor(decoded.userId, decoded.role);
      if (!actor) return next(new Error('Invalid session'));
      if (actor.role !== 'param' && actor.status === 'inactive') {
        return next(new Error('Account suspended'));
      }

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
      };

      next();
    } catch (err) {
      next(new Error('Invalid token'));
    }
  });

  // ── Connection handler ───────────────────────────────────────────
  io.on('connection', async (socket) => {
    const { userId, role, companyId } = socket.user;

    // Join global room for SuperAdmin
    if (role === 'param') {
      socket.join('global');
    }

    // Join all user identifier alias rooms
    const myRooms = await resolveUserRooms(userId);
    myRooms.forEach((room) => socket.join(room));

    // Join company room (strictly validated from DB via socket.user.companyId)
    if (companyId) {
      socket.join(`company:${companyId}`);
    }

    // Track online presence
    if (!onlineUserSockets.has(userId)) {
      onlineUserSockets.set(userId, new Set());
    }
    const userSockets = onlineUserSockets.get(userId);
    const wasOffline = userSockets.size === 0;
    userSockets.add(socket.id);

    if (wasOffline) {
      const presencePayload = { userId, online: true, lastActive: new Date().toISOString() };
      if (companyId) {
        io.to(`company:${companyId}`).emit('presence:update', presencePayload);
      }
      if (socket.user.isOwnerOrAdmin || socket.user.isSuperAdmin) {
        io.to('global').emit('presence:update', presencePayload);
      }
    }

    // ── Active Conversation Tracking (WhatsApp-like presence & notification suppression) ──
    socket.on('dm:join-conversation', (data) => {
      const convId = data?.conversationId ? String(data.conversationId) : null;
      if (convId) {
        userActiveConversations.set(String(userId), convId);
      }
    });

    socket.on('dm:leave-conversation', (data) => {
      const convId = data?.conversationId ? String(data.conversationId) : null;
      if (!convId || userActiveConversations.get(String(userId)) === convId) {
        userActiveConversations.delete(String(userId));
      }
    });

    // ── 1-to-1 WebRTC Call Signaling (with server-side role & company validation) ──
    socket.on('call:initiate', async (data) => {
      try {
        const { callId, recipientId, mediaType, offer } = data || {};
        const targetId = normalizeId(recipientId);
        if (!targetId || !callId) return;

        // Server-side authorization check (never trust client recipientId)
        const targetActor = await resolveMessengerActor(targetId);
        const authCheck = canCommunicate(socket.user, targetActor);
        if (!authCheck.allowed) {
          socket.emit('call:rejected', {
            callId,
            recipientId: targetId,
            reason: authCheck.reason || 'unauthorized',
          });
          return;
        }

        const callerName = socket.user?.name || socket.user?.username || 'Someone';
        const type = mediaType === 'video' ? 'video_call' : 'voice_call';

        // Cache active call offer in memory for notification clicks / tab transitions
        activeCalls.set(callId, {
          callId,
          callerId: userId,
          callerName,
          recipientId: targetActor.userId,
          mediaType: mediaType || 'voice',
          offer,
          actionStatus: 'pending',
          startedAt: Date.now(),
        });

        // Auto-clean active call after 60s if not answered
        setTimeout(() => {
          const call = activeCalls.get(callId);
          if (call && call.actionStatus !== 'accepted') {
            activeCalls.delete(callId);
          }
        }, 60000);

        const targetRooms = await resolveUserRooms(targetActor.userId);

        // Persist notification for recipient
        const notifId = `call-notif-${callId}`;
        const existing = await Notification.findOne({ id: notifId });
        let notif = existing;
        if (!existing) {
          notif = new Notification({
            id: notifId,
            companyId: socket.user.companyId || targetActor.companyId || null,
            userId: targetActor.userId,
            title: mediaType === 'video' ? 'Incoming Video Call' : 'Incoming Voice Call',
            message: `${callerName} is calling you...`,
            type,
            senderId: userId,
            senderName: callerName,
            callId,
            actionStatus: 'pending',
            metadata: { mediaType: mediaType || 'voice', callerName, callerId: userId },
            createdAt: new Date().toISOString(),
            read: false,
          });
          await notif.save().catch(() => {});
        }

        const incomingPayload = {
          callId,
          callerId: userId,
          callerName,
          mediaType: mediaType || 'voice',
          offer,
        };

        broadcastToRooms(targetRooms, 'notification:new', notif);
        broadcastToRooms(targetRooms, 'call:incoming', incomingPayload);
      } catch (err) {
        console.error('[Socket] call:initiate error:', err.message);
      }
    });

    // Client requests offer for active call (e.g. when opening from notification)
    socket.on('call:get-active', (data, callback) => {
      const call = activeCalls.get(data?.callId);
      if (typeof callback === 'function') {
        if (call && (call.recipientId === userId || call.callerId === userId)) {
          callback(call);
        } else {
          callback(null);
        }
      }
    });

    socket.on('call:accept', async (data) => {
      try {
        const { callId, callerId, answer } = data || {};
        if (!callerId) return;

        const call = callId ? activeCalls.get(callId) : null;
        if (call && call.recipientId !== userId && call.callerId !== userId) {
          return; // Unauthorized participant
        }

        if (callId) {
          if (call) {
            call.actionStatus = 'accepted';
            call.acceptedAt = Date.now();
          }
          await Notification.updateOne(
            { id: `call-notif-${callId}` },
            { $set: { actionStatus: 'accepted', read: true } }
          ).catch(() => {});
        }

        const targetRooms = await resolveUserRooms(callerId);
        broadcastToRooms(targetRooms, 'call:accepted', {
          callId,
          recipientId: userId,
          answer,
        });
      } catch (err) {
        console.error('[Socket] call:accept error:', err.message);
      }
    });

    socket.on('call:reject', async (data) => {
      try {
        const { callId, callerId, reason } = data || {};
        if (!callerId) return;

        // Never terminate an already accepted call from duplicate reject packets
        const existingCall = activeCalls.get(callId);
        if (existingCall?.actionStatus === 'accepted') {
          return;
        }
        if (existingCall && existingCall.recipientId !== userId && existingCall.callerId !== userId) {
          return;
        }

        if (callId) {
          activeCalls.delete(callId);
          await Notification.updateOne(
            { id: `call-notif-${callId}` },
            { $set: { actionStatus: 'rejected', read: true } }
          ).catch(() => {});
        }

        const targetRooms = await resolveUserRooms(callerId);
        broadcastToRooms(targetRooms, 'call:rejected', {
          callId,
          recipientId: userId,
          reason: reason || 'declined',
        });
      } catch (err) {
        console.error('[Socket] call:reject error:', err.message);
      }
    });

    socket.on('call:signal', async (data) => {
      try {
        const { targetUserId, signal, callId } = data || {};
        const targetId = normalizeId(targetUserId);
        if (!targetId) return;

        // Validate authorization on ICE/SDP signal forwarding
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
        console.error('[Socket] call:signal error:', err.message);
      }
    });

    socket.on('call:end', async (data) => {
      try {
        const { targetUserId, callId } = data || {};
        if (callId) {
          activeCalls.delete(callId);
          await Notification.updateOne(
            { id: `call-notif-${callId}` },
            { $set: { actionStatus: 'ended', read: true } }
          ).catch(() => {});
        }
        if (targetUserId) {
          const targetRooms = await resolveUserRooms(targetUserId);
          broadcastToRooms(targetRooms, 'call:ended', {
            callId,
            endedBy: userId,
          });
          broadcastToRooms(targetRooms, 'call:cancelled', {
            callId,
            callerId: userId,
          });
        }
      } catch (err) {
        console.error('[Socket] call:end error:', err.message);
      }
    });

    // ── Group / Team Voice & Video Meeting Signaling (WebRTC Mesh with ACLs) ──
    socket.on('meeting:start', async (data) => {
      try {
        const { meetingId, title, mediaType, conversationId, participantIds } = data || {};
        if (!meetingId) return;

        const hostName = socket.user?.name || socket.user?.username || 'Team Lead';
        const effectiveMediaType = mediaType === 'voice' ? 'voice' : 'video';
        const allowedUserIds = new Set([userId]);
        let invitedActors = [];
        let meetingScope = socket.user.isSuperAdmin ? 'superadmin_owners' : 'company';
        let meetingCompanyId = socket.user.companyId || null;

        // Case 1: Group call tied to a specific Conversation (validates membership)
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
        }
        // Case 2: Explicit participant list (e.g. SuperAdmin calling selected company owners, or ad-hoc group call)
        else if (Array.isArray(participantIds) && participantIds.length > 0) {
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
        }
        // Case 3: Company-wide Team Meeting (existing website behavior)
        else if (meetingCompanyId) {
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
          title: meetingTitle,
          hostId: userId,
          hostName,
          mediaType: effectiveMediaType,
          companyId: meetingCompanyId,
          conversationId: conversationId || null,
        };

        // Notify every authorized participant directly
        for (const m of invitedActors) {
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

        // For company-wide meetings without explicit subset, also emit to company room (website parity)
        if (!conversationId && (!Array.isArray(participantIds) || participantIds.length === 0) && meetingCompanyId) {
          io.to(`company:${meetingCompanyId}`).emit('meeting:started', meetingPayload);
        }
      } catch (err) {
        console.error('[Socket] meeting:start error:', err.message);
      }
    });

    socket.on('meeting:join', async (data) => {
      try {
        const { meetingId, userInfo } = data || {};
        if (!meetingId) return;

        // Server-side meeting room authorization check
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
        console.error('[Socket] meeting:join error:', err.message);
      }
    });

    socket.on('meeting:signal', async (data) => {
      try {
        const { targetUserId, signal, meetingId } = data || {};
        const targetId = normalizeId(targetUserId);
        if (!targetId || !meetingId) return;

        // Ensure caller is actually in this meeting room
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
        console.error('[Socket] meeting:signal error:', err.message);
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

      // Clean up meeting ACL if room is now empty
      try {
        const remaining = await io.in(`meeting:${meetingId}`).fetchSockets();
        if (remaining.length === 0) {
          activeMeetings.delete(meetingId);
        }
      } catch {}
    });

    socket.on('disconnect', () => {
      // Clean up active conversation tracking
      userActiveConversations.delete(String(userId));

      // Clean up pending unanswered calls initiated by this user
      for (const [cId, cInfo] of activeCalls.entries()) {
        if (cInfo.callerId === userId && cInfo.actionStatus !== 'accepted') {
          activeCalls.delete(cId);
        }
      }

      // Clean up presence tracking
      const sockets = onlineUserSockets.get(userId);
      if (sockets) {
        sockets.delete(socket.id);
        if (sockets.size === 0) {
          onlineUserSockets.delete(userId);
          const presencePayload = { userId, online: false, lastActive: new Date().toISOString() };
          if (companyId) {
            io.to(`company:${companyId}`).emit('presence:update', presencePayload);
          }
          if (socket.user.isOwnerOrAdmin || socket.user.isSuperAdmin) {
            io.to('global').emit('presence:update', presencePayload);
          }
        }
      }
    });
  });

  return io;
}

/**
 * Get the current Socket.IO server instance.
 */
export function getIO() {
  return io;
}

/**
 * Emit a real-time event to all users in a company.
 */
export function emitToCompany(event, companyId, payload = {}) {
  if (!io) return;
  if (companyId) {
    io.to(`company:${companyId.toString()}`).emit(event, payload);
  }
  // SuperAdmin monitoring events (never leak private DMs into global)
  if (!event.startsWith('dm:')) {
    io.to('global').emit(event, payload);
  }
}

/**
 * Emit a real-time event directly to a specific user (deduplicated across alias rooms).
 */
export async function emitToUser(userId, event, payload = {}) {
  if (!io || !userId) return;
  const targetRooms = await resolveUserRooms(userId);
  broadcastToRooms(targetRooms, event, payload);
}
