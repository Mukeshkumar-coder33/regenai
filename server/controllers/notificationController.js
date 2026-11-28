import mongoose from 'mongoose';
import Notification from '../models/Notification.js';
import User from '../models/User.js';
import SuperAdmin from '../models/SuperAdmin.js';
import Company from '../models/Company.js';
import { resolveCompanyId } from '../utils/resolveCompanyId.js';
import { emitToUser, rejectCallSessionByUser } from '../socket.js';
import { sendFcmPushToUsers, isFcmConfigured, getFcmStatus } from '../utils/fcmPush.js';
import { createCorrelationId, logCommEvent, getRecentCommEvents } from '../utils/commLogger.js';

const parseMonthDay = (dob) => {
  if (!dob) return null;
  const s = String(dob).trim();
  const m = s.match(/^(\d{4})\D(\d{2})\D(\d{2})/);
  if (m) return { month: Number(m[2]), day: Number(m[3]) };
  const d = new Date(s);
  if (Number.isNaN(d.getTime())) return null;
  return { month: d.getMonth() + 1, day: d.getDate() };
};

const isStaffUser = (u) => {
  if (!u?.role) return false;
  if (typeof u.role === 'string') return u.role === 'staff';
  return !!u.role?.staff;
};

const getUserDisplayName = (u) => {
  return (u?.name || u?.username || u?.userId || '').toString().trim();
};

const startOfTodayLocal = () => {
  const d = new Date();
  d.setHours(0, 0, 0, 0);
  return d;
};

const diffDays = (fromDate, toDate) => {
  const ms = toDate.getTime() - fromDate.getTime();
  return Math.floor(ms / (1000 * 60 * 60 * 24));
};

const computeNextBirthday = (dob, fromDate) => {
  const md = parseMonthDay(dob);
  if (!md) return null;
  const year = fromDate.getFullYear();
  const isLeap = (y) => (y % 4 === 0 && y % 100 !== 0) || (y % 400 === 0);
  const normalizeDay = (y, month, day) => {
    if (month === 2 && day === 29 && !isLeap(y)) return 28;
    return day;
  };
  const dayThisYear = normalizeDay(year, md.month, md.day);
  let candidate = new Date(year, md.month - 1, dayThisYear);
  candidate.setHours(0, 0, 0, 0);
  if (candidate < fromDate) {
    const nextYear = year + 1;
    const dayNextYear = normalizeDay(nextYear, md.month, md.day);
    candidate = new Date(nextYear, md.month - 1, dayNextYear);
    candidate.setHours(0, 0, 0, 0);
  }
  return candidate;
};

const buildReminderNotifications = (staffUser, birthdayDate, daysBefore, recipients) => {
  const pad2 = (n) => String(n).padStart(2, '0');
  const birthdayIso = `${birthdayDate.getFullYear()}-${pad2(birthdayDate.getMonth() + 1)}-${pad2(birthdayDate.getDate())}`;
  const staffName = getUserDisplayName(staffUser);
  const createdAt = new Date().toISOString();
  const title = 'Birthday Reminder';
  const message = `Reminder: ${staffName}'s birthday is on ${birthdayIso}.`;
  return recipients.map((r) => {
    const recipientId = (r?.userId || '').toString();
    const staffId = (staffUser?.userId || '').toString();
    return {
      id: `bday-${staffId}-${birthdayIso}-d${daysBefore}-${recipientId}`,
      userId: recipientId,
      title,
      message,
      createdAt,
      read: false
    };
  });
};

export const runBirthdayReminderJob = async () => {
  const today = startOfTodayLocal();
  const allUsers = await User.find();

  // Group users by companyId for isolation
  const companyMap = new Map(); // companyId -> [users]
  for (const u of allUsers) {
    const cid = u.companyId ? u.companyId.toString() : '__global__';
    if (!companyMap.has(cid)) companyMap.set(cid, []);
    companyMap.get(cid).push(u);
  }

  const targetDays = new Set([7, 1]);
  const toInsert = [];

  for (const [companyIdStr, users] of companyMap) {
    const recipients = users.filter((u) => String(u.status || 'active') !== 'inactive');
    const staff = recipients.filter((u) => isStaffUser(u) && u.dateOfBirth);

    for (const s of staff) {
      const nextBday = computeNextBirthday(s.dateOfBirth, today);
      if (!nextBday) continue;
      const daysUntil = diffDays(today, nextBday);
      if (!targetDays.has(daysUntil)) continue;
      // Skip users without companyId — they can't receive scoped notifications
      if (!s.companyId) continue;
      const notifications = buildReminderNotifications(s, nextBday, daysUntil, recipients);
      // Stamp companyId on each notification
      for (const n of notifications) n.companyId = s.companyId;
      toInsert.push(...notifications);
    }
  }

  if (toInsert.length === 0) {
    return { created: 0, attempted: 0 };
  }

  const ops = toInsert.map((doc) => ({
    updateOne: {
      filter: { id: doc.id },
      update: { $setOnInsert: doc },
      upsert: true
    }
  }));
  const result = await Notification.bulkWrite(ops, { ordered: false });
  const created = result?.upsertedCount || 0;
  if (created > 0) {
    const upsertedIndices = Object.keys(result.upsertedIds || {}).map(Number);
    for (const idx of upsertedIndices) {
      const doc = toInsert[idx];
      if (!doc) continue;
      emitToUser(doc.userId, 'notification:new', doc);
      sendFcmPushToUsers({
        userIds: [doc.userId],
        title: doc.title,
        body: doc.message,
        channelId: 'regen_messages_v2',
        data: { notificationId: doc.id, type: 'general' },
      }).catch(() => {});
    }
  }
  return { created, attempted: toInsert.length };
};

export const createNotification = async (req, res) => {
  try {
    const role = String(req.user?.role || '').toLowerCase();
    const isAdmin = ['param', 'owner', 'admin'].includes(role);
    const body = { ...req.body };
    const reqUid = String(req.user?.userId || '').trim();
    const targetUid = String(body.userId || reqUid).trim();
    if (!isAdmin && reqUid && targetUid !== reqUid) {
      return res.status(403).json({ message: 'Forbidden: cannot create notifications for another user' });
    }
    body.userId = targetUid;
    body.companyId = await resolveCompanyId(req, body);
    const notification = await createAndSendNotification(body);
    if (!notification) {
      return res.status(400).json({ message: 'Failed to create notification' });
    }
    res.status(201).json(notification);
  } catch (error) {
    res.status(400).json({ message: error.message });
  }
};

export const getUserNotifications = async (req, res) => {
  try {
    const targetUserId = req.params.userId;
    const userIds = new Set([targetUserId]);
    if (req.user?.userId) userIds.add(String(req.user.userId));
    if (req.user?.id) userIds.add(String(req.user.id));
    if (req.user?.StaffId) userIds.add(String(req.user.StaffId));

    let userCompId = req.companyId;
    let isOwnerOrAdmin = false;

    try {
      const isOid = mongoose.isValidObjectId(targetUserId);
      const u = await User.findOne({
        $or: [
          { userId: targetUserId },
          { StaffId: targetUserId },
          { username: targetUserId },
          ...(isOid ? [{ _id: targetUserId }] : [])
        ]
      }).select('userId StaffId username _id role companyId').lean();

      if (u) {
        if (u.userId) userIds.add(String(u.userId));
        if (u.StaffId) userIds.add(String(u.StaffId));
        if (u.username) userIds.add(String(u.username));
        if (u._id) userIds.add(String(u._id));
        if (u.companyId) userCompId = u.companyId;
        if (u.role === 'owner' || u.role === 'admin' || u.role === 'superadmin') {
          isOwnerOrAdmin = true;
        }
      }
    } catch (_) {}

    // Check if targetUserId is a company owner or matches company
    if (!userCompId || !isOwnerOrAdmin) {
      try {
        const comp = await Company.findOne({
          $or: [
            { ownerId: targetUserId },
            ...(mongoose.isValidObjectId(targetUserId) ? [{ _id: targetUserId }] : [])
          ]
        }).lean();
        if (comp) {
          userCompId = comp._id;
          isOwnerOrAdmin = true;
          if (comp.ownerId) userIds.add(String(comp.ownerId));
        }
      } catch (_) {}
    }

    let filter;
    if (isOwnerOrAdmin && userCompId) {
      // Company Owner / Admin sees their personal notifications PLUS all company activities/notifications!
      filter = {
        $or: [
          { userId: { $in: Array.from(userIds) } },
          { companyId: userCompId }
        ]
      };
    } else {
      filter = { userId: { $in: Array.from(userIds) } };
      if (userCompId) filter.companyId = userCompId;
    }

    const list = await Notification.find(filter).sort({ createdAt: -1 });
    res.status(200).json(list);
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
};

export const markNotificationRead = async (req, res) => {
  try {
    const rawId = req.params.id;
    const role = String(req.user?.role || '').toLowerCase();
    const isOwnerOrAdmin = ['param', 'owner', 'admin'].includes(role);
    const ownershipFilter = isOwnerOrAdmin
      ? (req.companyId && role !== 'param' ? { companyId: req.companyId } : {})
      : { userId: { $in: [req.user?.userId, req.user?.StaffId, req.user?.id].filter(Boolean).map(String) } };

    let notification = await Notification.findOneAndUpdate(
      { id: rawId, ...ownershipFilter },
      { $set: { read: true } },
      { new: true }
    );
    if (!notification && mongoose.isValidObjectId(rawId)) {
      notification = await Notification.findOneAndUpdate(
        { _id: rawId, ...ownershipFilter },
        { $set: { read: true } },
        { new: true }
      );
    }
    if (!notification) return res.status(404).json({ message: 'Notification not found' });
    emitToUser(notification.userId, 'notification:read', { id: notification.id, read: true });
    if (notification.companyId) {
      emitToUser(req.user?.userId, 'notification:read', { id: notification.id, read: true });
    }
    res.status(200).json(notification);
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
};

export const markAllNotificationsRead = async (req, res) => {
  try {
    const targetUserId = req.params.userId;
    const userIds = new Set([targetUserId]);
    if (req.user?.userId) userIds.add(String(req.user.userId));
    if (req.user?.id) userIds.add(String(req.user.id));
    if (req.user?.StaffId) userIds.add(String(req.user.StaffId));

    let userCompId = req.companyId;
    let isOwnerOrAdmin = false;

    try {
      const isOid = mongoose.isValidObjectId(targetUserId);
      const u = await User.findOne({
        $or: [
          { userId: targetUserId },
          { StaffId: targetUserId },
          { username: targetUserId },
          ...(isOid ? [{ _id: targetUserId }] : [])
        ]
      }).select('userId StaffId username _id role companyId').lean();

      if (u) {
        if (u.userId) userIds.add(String(u.userId));
        if (u.StaffId) userIds.add(String(u.StaffId));
        if (u.username) userIds.add(String(u.username));
        if (u._id) userIds.add(String(u._id));
        if (u.companyId) userCompId = u.companyId;
        if (u.role === 'owner' || u.role === 'admin' || u.role === 'superadmin') {
          isOwnerOrAdmin = true;
        }
      }
    } catch (_) {}

    if (!userCompId || !isOwnerOrAdmin) {
      try {
        const comp = await Company.findOne({
          $or: [
            { ownerId: targetUserId },
            ...(mongoose.isValidObjectId(targetUserId) ? [{ _id: targetUserId }] : [])
          ]
        }).lean();
        if (comp) {
          userCompId = comp._id;
          isOwnerOrAdmin = true;
          if (comp.ownerId) userIds.add(String(comp.ownerId));
        }
      } catch (_) {}
    }

    let filter;
    if (isOwnerOrAdmin && userCompId) {
      filter = {
        $or: [
          { userId: { $in: Array.from(userIds) } },
          { companyId: userCompId }
        ],
        read: false
      };
    } else {
      filter = { userId: { $in: Array.from(userIds) }, read: false };
    }

    const result = await Notification.updateMany(filter, { $set: { read: true } });
    
    userIds.forEach(uid => {
      emitToUser(uid, 'notification:read_all', { userId: uid });
    });
    res.status(200).json({ message: 'All notifications marked as read', modifiedCount: result.modifiedCount });
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
};

export const updateNotificationAction = async (req, res) => {
  try {
    const { actionStatus } = req.body;
    const filter = { id: req.params.id };
    if (req.companyId) filter.companyId = req.companyId;
    const notification = await Notification.findOneAndUpdate(
      filter,
      { $set: { actionStatus, read: true } },
      { new: true }
    );
    if (!notification) return res.status(404).json({ message: 'Notification not found' });
    emitToUser(notification.userId, 'notification:change', notification);
    res.status(200).json(notification);
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
};

export const deleteNotification = async (req, res) => {
  try {
    const filter = { id: req.params.id };
    if (req.companyId) filter.companyId = req.companyId;
    const n = await Notification.findOneAndDelete(filter);
    if (!n) return res.status(404).json({ message: 'Notification not found' });
    emitToUser(n.userId, 'notification:change', { id: n.id, deleted: true });
    res.status(200).json({ message: 'Notification deleted successfully' });
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
};

export const createAndSendNotification = async (payload) => {
  try {
    const rawType = payload.type || 'general';
    const resolvedTitle = String(payload.title || '').trim() || (payload.senderName ? String(payload.senderName) : 'ReGen Alert');
    const resolvedMessage =
      String(payload.message || payload.body || payload.text || '').trim() ||
      (payload.senderName ? `Update from ${payload.senderName}` : `${rawType.replace(/_/g, ' ')} update`);

    const doc = {
      id: payload.id || `notif-${Date.now()}-${Math.random().toString(36).substring(2, 7)}`,
      companyId: payload.companyId,
      userId: payload.userId,
      title: resolvedTitle,
      message: resolvedMessage,
      type: rawType,
      senderId: payload.senderId,
      senderName: payload.senderName,
      conversationId: payload.conversationId,
      callId: payload.callId,
      meetingId: payload.meetingId,
      actionStatus: payload.actionStatus || 'none',
      metadata: payload.metadata || {},
      createdAt: payload.createdAt || new Date().toISOString(),
      read: false
    };

    // Deduplicate: return existing notification record if caller supplied an id already persisted
    if (payload.id) {
      const existingById = await Notification.findOne({ id: doc.id });
      if (existingById) return existingById;
    }

    // Prevent duplicate calls/meetings if pending notification already exists for this user
    if (doc.type === 'voice_call' || doc.type === 'video_call') {
      const existing = await Notification.findOne({
        userId: doc.userId,
        callId: doc.callId,
        actionStatus: 'pending'
      });
      if (existing) return existing;
    }
    if (doc.type === 'team_meeting' && doc.meetingId) {
      const existingMeeting = await Notification.findOne({
        userId: doc.userId,
        meetingId: doc.meetingId,
      });
      if (existingMeeting) return existingMeeting;
    }

    const n = new Notification(doc);
    await n.save();

    const userIdsToNotify = new Set([String(doc.userId)]);
    try {
      const isOid = mongoose.isValidObjectId(doc.userId);
      const recipient = await User.findOne({
        $or: [
          { userId: doc.userId },
          { StaffId: doc.userId },
          { username: doc.userId },
          ...(isOid ? [{ _id: doc.userId }] : [])
        ]
      }).select('userId StaffId username _id').lean();
      if (recipient) {
        if (recipient.userId) userIdsToNotify.add(String(recipient.userId));
        if (recipient.StaffId) userIdsToNotify.add(String(recipient.StaffId));
        if (recipient.username) userIdsToNotify.add(String(recipient.username));
        if (recipient._id) userIdsToNotify.add(String(recipient._id));
      } else {
        const { default: SuperAdmin } = await import('../models/SuperAdmin.js');
        const sa = await SuperAdmin.findOne({
          $or: [
            { adminId: doc.userId },
            { username: doc.userId },
            ...(isOid ? [{ _id: doc.userId }] : [])
          ]
        }).select('adminId username _id').lean();
        if (sa) {
          if (sa.adminId) userIdsToNotify.add(String(sa.adminId));
          if (sa.username) userIdsToNotify.add(String(sa.username));
          if (sa._id) userIdsToNotify.add(String(sa._id));
        }
      }
    } catch (_) {}

    userIdsToNotify.forEach(uid => {
      emitToUser(uid, 'notification:new', n);
    });

    // Trigger FCM push fallback for messages & alerts when recipient devices hold registered tokens
    // (1:1 calls & team meetings dispatch high-priority call wakeup pushes directly in socket.js)
    const isCallAlert = [
      'voice_call',
      'video_call',
      'team_meeting',
      'call',
      'meeting',
      'call_cancelled',
      'call_ended',
    ].includes(doc.type);
    if (!isCallAlert) {
      const correlationId = createCorrelationId('notif');
      const isMissed = doc.type === 'missed_call';
      sendFcmPushToUsers({
        userIds: Array.from(userIdsToNotify),
        title: doc.title,
        body: doc.message,
        channelId: isMissed ? 'regen_missed_calls_v2' : 'regen_messages_v2',
        highPriority: isMissed || ['text_message', 'voice_message', 'leave', 'project_task', 'attendance', 'task'].includes(doc.type),
        dataOnly: false,
        correlationId,
        data: {
          notificationId: doc.id,
          type: doc.type,
          title: doc.title,
          body: doc.message,
          message: doc.message,
          conversationId: doc.conversationId || '',
          senderId: doc.senderId || '',
          senderName: doc.senderName || '',
          callerId: isMissed ? (doc.senderId || '') : '',
          callerName: isMissed ? (doc.senderName || '') : '',
          callId: doc.callId || '',
          meetingId: doc.meetingId || '',
        },
      }).catch((err) => {
        logCommEvent('notif:fcm_error', { correlationId, error: err.message });
      });
    }

    return n;
  } catch (err) {
    console.error('[Notification] Failed to create notification:', err.message);
    return null;
  }
};

export const runBirthdayReminders = async (_req, res) => {
  try {
    const result = await runBirthdayReminderJob();
    res.status(200).json(result);
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
};

export const clearAllNotifications = async (req, res) => {
  try {
    const targetUserId = req.params.userId || req.user?.userId;
    const authUserId = req.user?.userId;
    const authId = req.user?.id;
    const authStaffId = req.user?.StaffId;

    const userIds = new Set([String(targetUserId)]);
    if (authUserId) userIds.add(String(authUserId));
    if (authId) userIds.add(String(authId));
    if (authStaffId) userIds.add(String(authStaffId));

    let userCompId = req.companyId;
    let isOwnerOrAdmin = false;

    try {
      const isOid = mongoose.isValidObjectId(targetUserId);
      const u = await User.findOne({
        $or: [
          { userId: targetUserId },
          { StaffId: targetUserId },
          { username: targetUserId },
          ...(isOid ? [{ _id: targetUserId }] : [])
        ]
      }).select('userId StaffId username _id role companyId').lean();

      if (u) {
        if (u.userId) userIds.add(String(u.userId));
        if (u.StaffId) userIds.add(String(u.StaffId));
        if (u.username) userIds.add(String(u.username));
        if (u._id) userIds.add(String(u._id));
        if (u.companyId) userCompId = u.companyId;
        if (u.role === 'owner' || u.role === 'admin' || u.role === 'superadmin') {
          isOwnerOrAdmin = true;
        }
      }
    } catch (_) {}

    if (!userCompId || !isOwnerOrAdmin) {
      try {
        const comp = await Company.findOne({
          $or: [
            { ownerId: targetUserId },
            ...(mongoose.isValidObjectId(targetUserId) ? [{ _id: targetUserId }] : [])
          ]
        }).lean();
        if (comp) {
          userCompId = comp._id;
          isOwnerOrAdmin = true;
          if (comp.ownerId) userIds.add(String(comp.ownerId));
        }
      } catch (_) {}
    }

    let filter;
    if (isOwnerOrAdmin && userCompId) {
      filter = {
        $or: [
          { userId: { $in: Array.from(userIds) } },
          { companyId: userCompId }
        ]
      };
    } else {
      filter = { userId: { $in: Array.from(userIds) } };
      if (userCompId) filter.companyId = userCompId;
    }

    const result = await Notification.deleteMany(filter);

    userIds.forEach(uid => {
      emitToUser(uid, 'notification:clear_all', { userId: uid });
    });

    res.status(200).json({ message: 'All notifications cleared successfully', deletedCount: result.deletedCount });
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
};

export const registerDeviceToken = async (req, res) => {
  try {
    const token = String(req.body?.token || '').trim();
    const platform = ['android', 'ios', 'web'].includes(String(req.body?.platform || '').toLowerCase())
      ? String(req.body.platform).toLowerCase()
      : 'android';
    if (!token) return res.status(400).json({ message: 'Device push token is required' });

    const uid = String(req.user?.userId || '').trim();
    if (!uid) return res.status(401).json({ message: 'Unauthorized' });

    // Remove this device token from any previous account on the same physical device before linking
    await Promise.all([
      User.updateMany({ userId: { $ne: uid } }, { $pull: { pushTokens: { token } } }),
      SuperAdmin.updateMany({ adminId: { $ne: uid } }, { $pull: { pushTokens: { token } } }),
    ]);

    if (req.user?.role === 'param') {
      await SuperAdmin.updateOne({ adminId: uid }, { $pull: { pushTokens: { token } } });
      await SuperAdmin.updateOne(
        { adminId: uid },
        { $push: { pushTokens: { $each: [{ token, platform, updatedAt: new Date() }], $slice: -10 } } }
      );
    } else {
      await User.updateOne({ userId: uid }, { $pull: { pushTokens: { token } } });
      await User.updateOne(
        { userId: uid },
        { $push: { pushTokens: { $each: [{ token, platform, updatedAt: new Date() }], $slice: -10 } } }
      );
    }

    logCommEvent('fcm:token_registered', {
      userId: uid,
      role: req.user?.role || '',
      platform,
      tokenPrefix: `${token.slice(0, 8)}...`,
    });

    res.status(200).json({ success: true, message: 'Device token registered', fcmConfigured: isFcmConfigured() });
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
};

export const unregisterDeviceToken = async (req, res) => {
  try {
    const token = String(req.body?.token || '').trim();
    const uid = String(req.user?.userId || '').trim();
    if (!uid || !token) return res.status(400).json({ message: 'Token is required' });

    if (req.user?.role === 'param') {
      await SuperAdmin.updateOne({ adminId: uid }, { $pull: { pushTokens: { token } } });
    } else {
      await User.updateOne({ userId: uid }, { $pull: { pushTokens: { token } } });
    }

    logCommEvent('fcm:token_unregistered', {
      userId: uid,
      tokenPrefix: `${token.slice(0, 8)}...`,
    });

    res.status(200).json({ success: true, message: 'Device token removed' });
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
};

export const getCommunicationDiagnostics = async (req, res) => {
  try {
    const { getSocketDiagnostics } = await import('../socket.js');
    const role = String(req.user?.role || '').toLowerCase();
    const isAdminOrOwner = ['param', 'owner', 'admin'].includes(role);
    const sockDiag = getSocketDiagnostics();
    const fcmStatus = getFcmStatus();
    if (!isAdminOrOwner) {
      return res.status(200).json({
        fcmConfigured: fcmStatus.configured,
        fcmStatus: {
          configured: fcmStatus.configured,
          initialized: fcmStatus.initialized,
          projectId: fcmStatus.projectId,
        },
        socket: {
          initialized: sockDiag.initialized,
          onlineUserCount: sockDiag.onlineUserCount,
        },
        recentEvents: [],
      });
    }
    res.status(200).json({
      fcmConfigured: fcmStatus.configured,
      fcmStatus,
      socket: sockDiag,
      recentEvents: getRecentCommEvents(80),
    });
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
};

export const rejectCallFromNotification = async (req, res) => {
  try {
    const uid = String(req.user?.userId || '').trim();
    const callId = String(req.params?.callId || '').trim();
    if (!uid) return res.status(401).json({ message: 'Unauthorized' });
    if (!callId) return res.status(400).json({ message: 'callId is required' });

    const result = await rejectCallSessionByUser({
      callId,
      userId: uid,
      reason: String(req.body?.reason || 'declined'),
    });
    if (!result.ok) {
      return res.status(result.status || 400).json({ ok: false, reason: result.reason });
    }
    return res.status(200).json(result);
  } catch (error) {
    return res.status(500).json({ ok: false, message: error.message });
  }
};


