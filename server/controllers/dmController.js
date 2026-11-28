import Conversation from '../models/Conversation.js';
import DirectMessage from '../models/DirectMessage.js';
import { emitToUser, getOnlineUserIds, isUserActiveInConversation } from '../socket.js';
import { createAndSendNotification } from './notificationController.js';
import {
  resolveMessengerActor,
  canCommunicate,
  canAccessConversation,
  getAuthorizedContacts,
  normalizeId
} from '../utils/messengerAuth.js';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const assetsDir = path.resolve(__dirname, '..', '..', 'assets');

const ensureAssetsDir = async () => {
  await fs.promises.mkdir(assetsDir, { recursive: true });
};
const parseDataUri = (value) => {
  if (!value || typeof value !== 'string') return null;
  const marker = ';base64,';
  const markerIdx = value.indexOf(marker);
  if (markerIdx === -1) return null;
  const prefix = value.slice(0, markerIdx);
  const data = value.slice(markerIdx + marker.length);
  const match = prefix.match(/^data:([^;]+)/);
  if (!match) return null;
  return { mime: match[1], data };
};
const extFromMime = (mime) => {
  const m = String(mime || '').toLowerCase();
  if (m === 'image/jpeg' || m === 'image/jpg') return 'jpg';
  if (m === 'image/png') return 'png';
  if (m === 'image/gif') return 'gif';
  if (m === 'image/webp') return 'webp';
  if (m === 'application/pdf') return 'pdf';
  if (m.includes('webm')) return 'webm';
  if (m.includes('mp4')) return 'mp4';
  if (m.includes('quicktime') || m.includes('mov')) return 'mov';
  if (m.includes('ogg')) return 'ogg';
  if (m.includes('wav')) return 'wav';
  if (m.includes('mp3') || m.includes('mpeg')) return 'mp3';
  if (m.includes('m4a')) return 'm4a';
  if (m.includes('aac')) return 'aac';
  return 'bin';
};
const sanitizeFileBase = (name) => {
  return String(name || '').replace(/[^a-zA-Z0-9._-]/g, '_').replace(/^_+|_+$/g, '').slice(0, 64) || 'file';
};
const saveAttachmentDataUri = async (dataUri, name, seed, index) => {
  const parsed = parseDataUri(dataUri);
  if (!parsed) return null;
  await ensureAssetsDir();
  const base = sanitizeFileBase(name);
  const extFromName = path.extname(base);
  const ext = extFromName || `.${extFromMime(parsed.mime)}`;
  const isVideo = parsed.mime.startsWith('video') || base.includes('video') || (ext === '.mp4' || ext === '.mov');
  const isVoice = parsed.mime.startsWith('audio') || base.includes('voice');
  const prefix = isVideo ? 'dm-video' : (isVoice ? 'dm-voice' : `dm-${sanitizeFileBase(seed)}`);
  const filename = `${prefix}-${Date.now()}-${index}${ext}`;
  const filePath = path.join(assetsDir, filename);
  await fs.promises.writeFile(filePath, Buffer.from(parsed.data, 'base64'));
  return `/assets/${filename}`;
};
const normalizeAttachment = async (att, seed, index) => {
  if (!att) return null;
  const data = att.data || att.url || att.dataUrl;
  let finalPath = null;
  if (typeof data === 'string' && data.startsWith('data:')) {
    finalPath = await saveAttachmentDataUri(data, att.name, seed, index);
  } else if (att.path) {
    finalPath = att.path;
  }
  if (finalPath) {
    finalPath = finalPath.replace(/\\/g, '/');
    const marker = '/assets/';
    const idx = finalPath.lastIndexOf(marker);
    if (idx >= 0) finalPath = `/assets/${finalPath.slice(idx + marker.length)}`;
    const isVideo = (att.type && att.type.startsWith('video')) || finalPath.includes('video') || (att.name && att.name.includes('video')) || /\.(mp4|mov|mkv)$/i.test(finalPath);
    const isVoice = (att.type && att.type.startsWith('audio')) || finalPath.includes('voice') || (att.name && att.name.includes('voice'));
    const detectedType = att.type || (isVideo ? 'video/webm' : (isVoice ? 'audio/webm' : (finalPath.endsWith('.m4a') ? 'audio/mp4' : (finalPath.endsWith('.aac') ? 'audio/aac' : (finalPath.endsWith('.webm') ? 'video/webm' : (finalPath.endsWith('.wav') ? 'audio/wav' : (finalPath.endsWith('.mp3') ? 'audio/mp3' : undefined)))))));
    return {
      path: finalPath,
      name: att.name || finalPath.split('/').pop(),
      type: detectedType,
      size: att.size,
      ...(att.duration !== undefined ? { duration: att.duration } : {}),
      ...(att.transcript ? { transcript: att.transcript } : {}),
    };
  }
  return null;
};

/** Emit a DM socket event strictly to the conversation's participants (never globally). */
async function emitToParticipants(participants, event, payload) {
  const unique = new Set((participants || []).map(normalizeId).filter(Boolean));
  await Promise.all(Array.from(unique).map((pid) => emitToUser(pid, event, payload)));
}

// ─── Get server-authorized Messenger contacts for caller's role ──
export const getMessengerContacts = async (req, res) => {
  try {
    const actor = await resolveMessengerActor(req.user?.userId, req.user?.role);
    if (!actor) return res.status(401).json({ message: 'Unauthorized' });

    const contacts = await getAuthorizedContacts(actor, getOnlineUserIds());
    res.status(200).json(contacts);
  } catch (error) {
    console.error('[DM] getMessengerContacts error:', error);
    res.status(500).json({ message: error.message });
  }
};

// ─── Get or create a 1:1 conversation ───────────────────────────
export const getOrCreateConversation = async (req, res) => {
  try {
    const actor = await resolveMessengerActor(req.user?.userId, req.user?.role);
    if (!actor) return res.status(401).json({ message: 'Unauthorized' });

    const recipientId = normalizeId(req.body?.recipientId);
    if (!recipientId) return res.status(400).json({ message: 'recipientId is required' });
    if (recipientId === actor.userId) return res.status(400).json({ message: 'Cannot create conversation with yourself' });

    const target = await resolveMessengerActor(recipientId);
    const authCheck = canCommunicate(actor, target);
    if (!authCheck.allowed) {
      return res.status(403).json({ message: authCheck.reason || 'Communication not allowed' });
    }

    const participants = [actor.userId, target.userId].sort();
    const scope = authCheck.scope || 'company';
    const companyId = scope === 'company' ? (actor.companyId || target.companyId) : null;

    const query = {
      isGroup: { $ne: true },
      participants: { $all: participants, $size: 2 },
    };
    if (companyId) {
      query.companyId = companyId;
    } else if (scope === 'superadmin_owners') {
      query.scope = 'superadmin_owners';
    }

    let convo = await Conversation.findOne(query);

    if (!convo) {
      convo = new Conversation({
        ...(companyId ? { companyId } : {}),
        participants,
        isGroup: false,
        scope,
        createdBy: actor.userId,
      });
      await convo.save();
    }

    const convoObj = convo.toObject ? convo.toObject() : convo;
    if (convo.publicKeys) {
      convoObj.publicKeys = convo.publicKeys instanceof Map ? Object.fromEntries(convo.publicKeys) : convo.publicKeys;
    }

    res.status(200).json(convoObj);
  } catch (error) {
    console.error('[DM] getOrCreateConversation error:', error);
    res.status(500).json({ message: error.message });
  }
};

// ─── Create a multi-user Group conversation ─────────────────────
export const createGroupConversation = async (req, res) => {
  try {
    const actor = await resolveMessengerActor(req.user?.userId, req.user?.role);
    if (!actor) return res.status(401).json({ message: 'Unauthorized' });

    const name = String(req.body?.name || '').trim();
    const rawIds = Array.isArray(req.body?.participantIds) ? req.body.participantIds : [];
    if (!name) return res.status(400).json({ message: 'Group name is required' });

    const uniquePeerIds = Array.from(
      new Set(rawIds.map(normalizeId).filter((id) => id && id !== actor.userId))
    );
    if (uniquePeerIds.length < 1) {
      return res.status(400).json({ message: 'Select at least one participant for the group' });
    }

    const verifiedParticipantIds = [actor.userId];
    for (const pid of uniquePeerIds) {
      const target = await resolveMessengerActor(pid);
      const authCheck = canCommunicate(actor, target);
      if (!authCheck.allowed) {
        return res.status(403).json({
          message: `Cannot add user "${pid}": ${authCheck.reason || 'Unauthorized'}`,
        });
      }
      verifiedParticipantIds.push(target.userId);
    }

    const scope = actor.isSuperAdmin ? 'superadmin_owners' : 'company';
    const companyId = scope === 'company' ? actor.companyId : null;

    const convo = new Conversation({
      ...(companyId ? { companyId } : {}),
      participants: Array.from(new Set(verifiedParticipantIds)),
      isGroup: true,
      name: name.slice(0, 80),
      createdBy: actor.userId,
      scope,
      lastMessage: {
        content: `${actor.name} created group "${name.slice(0, 80)}"`,
        senderId: actor.userId,
        timestamp: new Date(),
      },
    });
    await convo.save();

    await emitToParticipants(convo.participants, 'dm:change', {
      action: 'group_create',
      conversationId: convo._id.toString(),
      senderId: actor.userId,
    });

    // Notify invited peers that they were added to a new group
    const groupTitle = convo.name;
    for (const pid of verifiedParticipantIds) {
      if (pid === actor.userId) continue;
      await createAndSendNotification({
        id: `grp-${convo._id.toString()}-${pid}`,
        companyId: convo.companyId || null,
        userId: pid,
        type: 'text_message',
        title: `New Group: ${groupTitle}`,
        message: `${actor.name || actor.username} added you to "${groupTitle}"`,
        senderId: actor.userId,
        senderName: actor.name || actor.username,
        conversationId: convo._id.toString(),
        metadata: { isGroup: true, groupName: groupTitle },
      });
    }

    res.status(201).json(convo);
  } catch (error) {
    console.error('[DM] createGroupConversation error:', error);
    res.status(500).json({ message: error.message });
  }
};

// ─── List all conversations (1:1 + groups) for the current user ─
export const getMyConversations = async (req, res) => {
  try {
    const actor = await resolveMessengerActor(req.user?.userId, req.user?.role);
    if (!actor) return res.status(401).json({ message: 'Unauthorized' });

    const myId = actor.userId;
    const onlineSet = getOnlineUserIds();

    let filter;
    if (actor.isSuperAdmin) {
      // Super Admin sees ONLY conversations they participate in with company owners/admins
      filter = {
        participants: myId,
        $or: [
          { scope: 'superadmin_owners' },
          { companyId: null },
          { companyId: { $exists: false } },
        ],
      };
    } else if (actor.companyId) {
      // Company owner/admin/employee sees own-company conversations PLUS any owner<->SuperAdmin convo they participate in
      filter = {
        participants: myId,
        $or: [
          { companyId: actor.companyId },
          ...(actor.isOwnerOrAdmin ? [{ scope: 'superadmin_owners' }] : []),
        ],
      };
    } else {
      filter = { participants: myId };
    }

    const convos = await Conversation.find(filter).sort({ updatedAt: -1 }).lean();

    // Resolve participant profiles & unread counts
    const allParticipantIds = new Set();
    for (const c of convos) {
      for (const pid of c.participants || []) allParticipantIds.add(normalizeId(pid));
    }

    const profileMap = new Map();
    await Promise.all(
      Array.from(allParticipantIds).map(async (pid) => {
        const resolved = await resolveMessengerActor(pid);
        if (resolved) {
          profileMap.set(pid, {
            userId: resolved.userId,
            username: resolved.username,
            name: resolved.name,
            role: resolved.role,
            company: resolved.company,
            avatar: resolved.avatar,
            online: onlineSet.has(resolved.userId),
            lastActive: resolved.lastActive ? new Date(resolved.lastActive).toISOString() : null,
          });
        }
      })
    );

    const result = await Promise.all(
      convos.map(async (c) => {
        const unread = await DirectMessage.countDocuments({
          conversationId: c._id,
          senderId: { $ne: myId },
          readBy: { $ne: myId },
        });
        const participantDetails = (c.participants || [])
          .map((pid) => profileMap.get(normalizeId(pid)) || { userId: pid, name: pid, role: '', online: onlineSet.has(pid) });
        const otherPeer = !c.isGroup
          ? participantDetails.find((p) => p.userId !== myId) || participantDetails[0] || null
          : null;
        const keysObj = c.publicKeys
          ? (c.publicKeys instanceof Map ? Object.fromEntries(c.publicKeys) : c.publicKeys)
          : {};
        return {
          ...c,
          publicKeys: keysObj,
          unreadCount: unread,
          otherUser: otherPeer,
          participantDetails,
        };
      })
    );

    res.status(200).json(result);
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
};

// ─── Get messages for a conversation ────────────────────────────
export const getConversationMessages = async (req, res) => {
  try {
    const { conversationId } = req.params;
    const actor = await resolveMessengerActor(req.user?.userId, req.user?.role);
    if (!actor) return res.status(401).json({ message: 'Unauthorized' });

    const convo = await Conversation.findById(conversationId);
    const access = canAccessConversation(actor, convo);
    if (!access.allowed) {
      return res.status(convo ? 403 : 404).json({ message: access.reason });
    }

    const limit = Math.min(parseInt(req.query.limit) || 100, 500);
    const before = req.query.before;

    const filter = { conversationId: convo._id, deletedFor: { $ne: actor.userId } };
    if (before) filter.createdAt = { $lt: new Date(before) };

    const msgs = await DirectMessage.find(filter)
      .sort({ createdAt: -1 })
      .limit(limit)
      .lean();

    const keysObj = convo.publicKeys
      ? (convo.publicKeys instanceof Map ? Object.fromEntries(convo.publicKeys) : convo.publicKeys)
      : {};
    try {
      res.setHeader('x-conversation-keys', JSON.stringify(keysObj));
      res.setHeader('Access-Control-Expose-Headers', 'x-conversation-keys');
    } catch (_) {}

    res.status(200).json(msgs.reverse());
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
};

// ─── Get E2E public keys for a conversation ─────────────────────
export const getConversationKeys = async (req, res) => {
  try {
    const { conversationId } = req.params;
    const actor = await resolveMessengerActor(req.user?.userId, req.user?.role);
    if (!actor) return res.status(401).json({ message: 'Unauthorized' });

    const convo = await Conversation.findById(conversationId);
    const access = canAccessConversation(actor, convo);
    if (!access.allowed) {
      return res.status(convo ? 403 : 404).json({ message: access.reason });
    }

    const keysObj = convo.publicKeys
      ? (convo.publicKeys instanceof Map ? Object.fromEntries(convo.publicKeys) : convo.publicKeys)
      : {};

    res.status(200).json({ conversationId, publicKeys: keysObj });
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
};

// ─── Get user's own persistent E2E keys for conversation ────────
export const getUserConversationKey = async (req, res) => {
  try {
    const { conversationId } = req.params;
    const actor = await resolveMessengerActor(req.user?.userId, req.user?.role);
    if (!actor) return res.status(401).json({ message: 'Unauthorized' });

    const convo = await Conversation.findById(conversationId);
    const access = canAccessConversation(actor, convo);
    if (!access.allowed) {
      return res.status(convo ? 403 : 404).json({ message: access.reason });
    }

    const myId = actor.userId;
    const privKey = convo.userKeys ? (convo.userKeys instanceof Map ? convo.userKeys.get(myId) : convo.userKeys[myId]) : null;
    const pubKey = convo.publicKeys ? (convo.publicKeys instanceof Map ? convo.publicKeys.get(myId) : convo.publicKeys[myId]) : null;

    res.status(200).json({
      conversationId,
      userId: myId,
      privateKey: privKey || null,
      publicKey: pubKey || null,
    });
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
};

// ─── Store user's persistent E2E keys for conversation ──────────
export const storeUserConversationKey = async (req, res) => {
  try {
    const { conversationId } = req.params;
    const actor = await resolveMessengerActor(req.user?.userId, req.user?.role);
    if (!actor) return res.status(401).json({ message: 'Unauthorized' });

    const { privateKey, publicKey } = req.body;
    if (!publicKey) return res.status(400).json({ message: 'publicKey is required' });

    const convo = await Conversation.findById(conversationId);
    const access = canAccessConversation(actor, convo);
    if (!access.allowed) {
      return res.status(convo ? 403 : 404).json({ message: access.reason });
    }

    const myId = actor.userId;
    if (!convo.publicKeys) convo.publicKeys = new Map();
    if (!convo.userKeys) convo.userKeys = new Map();

    const pubVal = typeof publicKey === 'string' ? publicKey : JSON.stringify(publicKey);
    if (convo.publicKeys instanceof Map) {
      convo.publicKeys.set(myId, pubVal);
    } else {
      convo.publicKeys[myId] = pubVal;
    }

    if (privateKey) {
      const privVal = typeof privateKey === 'string' ? privateKey : JSON.stringify(privateKey);
      if (convo.userKeys instanceof Map) {
        convo.userKeys.set(myId, privVal);
      } else {
        convo.userKeys[myId] = privVal;
      }
    }
    await convo.save();

    const activeKeys = convo.publicKeys
      ? (convo.publicKeys instanceof Map ? Object.fromEntries(convo.publicKeys) : convo.publicKeys)
      : {};

    await emitToParticipants(convo.participants, 'dm:key-exchange', {
      conversationId: convo._id.toString(),
      userId: myId,
      publicKey: pubVal,
      publicKeys: activeKeys,
    });

    res.status(200).json({ success: true, conversationId, publicKeys: activeKeys });
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
};

// ─── Multipart media / video / voice file upload ───────────────
export const uploadMediaAttachment = async (req, res) => {
  try {
    const actor = await resolveMessengerActor(req.user?.userId, req.user?.role);
    if (!actor) return res.status(401).json({ message: 'Unauthorized' });
    if (!req.file) return res.status(400).json({ message: 'No file uploaded' });

    const relPath = `/assets/${req.file.filename}`;
    const originalName = req.file.originalname || req.file.filename;
    const lower = originalName.toLowerCase();
    const mime =
      req.file.mimetype && req.file.mimetype !== 'application/octet-stream'
        ? req.file.mimetype
        : lower.endsWith('.mp4')
        ? 'video/mp4'
        : lower.endsWith('.mov')
        ? 'video/quicktime'
        : lower.endsWith('.webm')
        ? 'video/webm'
        : lower.endsWith('.m4a')
        ? 'audio/mp4'
        : lower.endsWith('.aac')
        ? 'audio/aac'
        : 'application/octet-stream';

    res.status(201).json({
      path: relPath,
      name: originalName,
      type: mime,
      size: req.file.size,
    });
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
};

function describeAttachmentsSummary(attachments, contentText, { isVoice, encrypted, senderName, isGroup }) {
  const list = Array.isArray(attachments) ? attachments : [];
  const trimmed = String(contentText || '').trim();
  const prefix = isGroup && senderName ? `${senderName}: ` : '';
  const verbPrefix = senderName ? `${senderName} ` : '';

  if (isVoice) {
    return trimmed && !encrypted ? `${verbPrefix}sent a voice message: ${trimmed}` : `${verbPrefix}sent a voice message`;
  }
  const hasVideo = list.some((a) => String(a?.type || '').startsWith('video') || /\.(mp4|mov|mkv|webm)$/i.test(String(a?.name || a?.path || '')));
  if (hasVideo) {
    return trimmed && !encrypted ? `${verbPrefix}sent a video: ${trimmed}` : `${verbPrefix}sent a video`;
  }
  const imageCount = list.filter((a) => String(a?.type || '').startsWith('image') || /\.(png|jpe?g|gif|webp)$/i.test(String(a?.name || a?.path || ''))).length;
  if (imageCount > 0) {
    const label = imageCount > 1 ? `${imageCount} photos` : 'a photo';
    return trimmed && !encrypted ? `${verbPrefix}sent ${label}: ${trimmed}` : `${verbPrefix}sent ${label}`;
  }
  if (list.length > 0) {
    const firstName = list[0]?.name || 'file';
    return trimmed && !encrypted
      ? `${verbPrefix}sent ${firstName}: ${trimmed}`
      : `${verbPrefix}sent an attachment: ${firstName}`;
  }
  if (encrypted) {
    return `${verbPrefix}sent an encrypted message`;
  }
  if (trimmed) {
    return `${prefix}${trimmed}`;
  }
  return `${verbPrefix}sent a message`;
}

// ─── Send a direct or group message ─────────────────────────────
export const sendDirectMessage = async (req, res) => {
  try {
    const { conversationId } = req.params;
    const actor = await resolveMessengerActor(req.user?.userId, req.user?.role);
    if (!actor) return res.status(401).json({ message: 'Unauthorized' });

    const convo = await Conversation.findById(conversationId);
    const access = canAccessConversation(actor, convo);
    if (!access.allowed) {
      return res.status(convo ? 403 : 404).json({ message: access.reason });
    }

    const myId = actor.userId;
    const body = { ...req.body };
    body.conversationId = convo._id;
    body.companyId = convo.companyId || undefined;
    body.senderId = myId;
    body.senderName = actor.name || actor.username || myId;

    // Detect if peer/recipients are actively viewing this conversation right now
    const recipients = (convo.participants || []).filter((p) => normalizeId(p) !== myId);
    const activeRecipients = [];
    const inactiveRecipients = [];
    for (const rId of recipients) {
      if (isUserActiveInConversation(rId, convo._id.toString())) {
        activeRecipients.push(rId);
      } else {
        inactiveRecipients.push(rId);
      }
    }

    // If recipient is already inside the conversation, automatically mark as read!
    if (activeRecipients.length > 0) {
      body.readBy = Array.from(new Set([myId, ...activeRecipients]));
    } else {
      body.readBy = [myId];
    }

    // Handle attachments (voice notes, images, videos, files)
    if (Array.isArray(body.attachments)) {
      const seed = `dm-${conversationId}-${myId}`;
      const normalized = [];
      for (let i = 0; i < body.attachments.length; i++) {
        const saved = await normalizeAttachment(body.attachments[i], seed, i);
        if (saved) normalized.push(saved);
      }
      body.attachments = normalized;
    }

    const msg = new DirectMessage(body);
    await msg.save();

    const isVoice =
      body.isVoice ||
      (Array.isArray(msg.attachments) &&
        msg.attachments.some((a) => a.type?.startsWith('audio') || a.isVoice));
    const hasVideo =
      Array.isArray(msg.attachments) &&
      msg.attachments.some((a) => a.type?.startsWith('video') || /\.(mp4|mov|mkv|webm)$/i.test(String(a.name || a.path || '')));
    const hasImage =
      Array.isArray(msg.attachments) &&
      msg.attachments.some((a) => a.type?.startsWith('image') || /\.(png|jpe?g|gif|webp)$/i.test(String(a.name || a.path || '')));

    const senderDisplay = actor.name || actor.username || 'Teammate';
    const preview = body.encrypted
      ? '🔒 Encrypted message'
      : isVoice
      ? '🎤 Voice message'
      : hasVideo
      ? (body.content ? `🎥 ${body.content}` : '🎥 Video')
      : hasImage
      ? (body.content ? `📷 ${body.content}` : '📷 Photo')
      : body.content || (msg.attachments?.[0]?.name ? `📎 ${msg.attachments[0].name}` : '[attachment]');
    convo.lastMessage = { content: preview, senderId: myId, timestamp: msg.createdAt };
    await convo.save();

    // Emit strictly to all participants (both website & Flutter receive instantly)
    const activeKeys = convo.publicKeys
      ? (convo.publicKeys instanceof Map ? Object.fromEntries(convo.publicKeys) : convo.publicKeys)
      : {};

    await emitToParticipants(convo.participants, 'dm:change', {
      action: 'create',
      conversationId: convo._id.toString(),
      senderId: myId,
      message: msg,
      publicKeys: activeKeys,
    });

    // If recipient was already in the chat, send immediate read receipt so sender gets 2 blue ticks without delay!
    if (activeRecipients.length > 0) {
      for (const rId of activeRecipients) {
        await emitToParticipants(convo.participants, 'dm:change', {
          action: 'read',
          conversationId: convo._id.toString(),
          userId: rId,
          readBy: msg.readBy,
        });
      }
    }

    const notificationMessage = describeAttachmentsSummary(msg.attachments, body.content, {
      isVoice,
      encrypted: !!body.encrypted,
      senderName: senderDisplay,
      isGroup: !!convo.isGroup,
    });

    // Notify ONLY inactive participants (suppresses redundant sound/vibration/notification when actively in conversation)
    for (const recipientId of inactiveRecipients) {
      await createAndSendNotification({
        id: `dm-${msg._id.toString()}-${recipientId}`,
        companyId: convo.companyId || null,
        userId: recipientId,
        type: isVoice ? 'voice_message' : 'text_message',
        title: convo.isGroup ? `${convo.name} • ${senderDisplay}` : senderDisplay,
        message: notificationMessage,
        senderId: myId,
        senderName: senderDisplay,
        conversationId: convo._id.toString(),
        metadata: {
          messageId: msg._id.toString(),
          isVoice: !!isVoice,
          hasVideo: !!hasVideo,
          hasImage: !!hasImage,
          encrypted: !!body.encrypted,
          isGroup: !!convo.isGroup,
          groupName: convo.isGroup ? convo.name : undefined,
        },
      });
    }

    res.status(201).json(msg);
  } catch (error) {
    res.status(400).json({ message: error.message });
  }
};

// ─── Mark messages as read ──────────────────────────────────────
export const markAsRead = async (req, res) => {
  try {
    const { conversationId } = req.params;
    const actor = await resolveMessengerActor(req.user?.userId, req.user?.role);
    if (!actor) return res.status(401).json({ message: 'Unauthorized' });

    const convo = await Conversation.findById(conversationId);
    const access = canAccessConversation(actor, convo);
    if (!access.allowed) {
      return res.status(convo ? 403 : 404).json({ message: access.reason });
    }

    await DirectMessage.updateMany(
      { conversationId: convo._id, readBy: { $ne: actor.userId } },
      { $addToSet: { readBy: actor.userId } }
    );

    await emitToParticipants(convo.participants, 'dm:change', {
      action: 'read',
      conversationId: convo._id.toString(),
      userId: actor.userId,
    });

    res.status(200).json({ success: true });
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
};

// ─── Store E2E public key ───────────────────────────────────────
export const storePublicKey = async (req, res) => {
  try {
    const { conversationId } = req.params;
    const actor = await resolveMessengerActor(req.user?.userId, req.user?.role);
    if (!actor) return res.status(401).json({ message: 'Unauthorized' });

    const { publicKey } = req.body;
    if (!publicKey) return res.status(400).json({ message: 'publicKey is required' });

    const convo = await Conversation.findById(conversationId);
    const access = canAccessConversation(actor, convo);
    if (!access.allowed) {
      return res.status(convo ? 403 : 404).json({ message: access.reason });
    }

    if (!convo.publicKeys) convo.publicKeys = new Map();
    const pubVal = typeof publicKey === 'string' ? publicKey : JSON.stringify(publicKey);
    if (convo.publicKeys instanceof Map) {
      convo.publicKeys.set(actor.userId, pubVal);
    } else {
      convo.publicKeys[actor.userId] = pubVal;
    }
    await convo.save();

    const activeKeys = convo.publicKeys
      ? (convo.publicKeys instanceof Map ? Object.fromEntries(convo.publicKeys) : convo.publicKeys)
      : {};

    await emitToParticipants(convo.participants, 'dm:key-exchange', {
      conversationId: convo._id.toString(),
      userId: actor.userId,
      publicKey: typeof publicKey === 'string' ? publicKey : JSON.stringify(publicKey),
      publicKeys: activeKeys,
    });

    res.status(200).json({ success: true, publicKeys: activeKeys });
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
};

// ─── Edit a direct message ──────────────────────────────────────
export const editDirectMessage = async (req, res) => {
  try {
    const { messageId } = req.params;
    const actor = await resolveMessengerActor(req.user?.userId, req.user?.role);
    if (!actor) return res.status(401).json({ message: 'Unauthorized' });

    const msg = await DirectMessage.findById(messageId);
    if (!msg) return res.status(404).json({ message: 'Message not found' });
    if (msg.senderId !== actor.userId) return res.status(403).json({ message: 'You can only edit your own messages' });

    const convo = await Conversation.findById(msg.conversationId);
    const access = canAccessConversation(actor, convo);
    if (!access.allowed) return res.status(403).json({ message: access.reason });

    const { content, iv, encrypted } = req.body;
    msg.content = content;
    if (iv !== undefined) msg.iv = iv;
    if (encrypted !== undefined) msg.encrypted = encrypted;
    msg.editedAt = new Date();
    await msg.save();

    if (convo) {
      await emitToParticipants(convo.participants, 'dm:change', {
        action: 'update',
        conversationId: msg.conversationId.toString(),
        messageId: msg._id.toString(),
      });
    }

    res.status(200).json(msg);
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
};

// ─── Delete a direct message ────────────────────────────────────
export const deleteDirectMessage = async (req, res) => {
  try {
    const { messageId } = req.params;
    const mode = (req.query.mode || req.body?.mode || 'for_everyone').toString();
    const actor = await resolveMessengerActor(req.user?.userId, req.user?.role);
    if (!actor) return res.status(401).json({ message: 'Unauthorized' });

    const msg = await DirectMessage.findById(messageId);
    if (!msg) return res.status(404).json({ message: 'Message not found' });

    const convo = await Conversation.findById(msg.conversationId);
    const access = canAccessConversation(actor, convo);
    if (!access.allowed) return res.status(403).json({ message: access.reason });

    if (mode === 'for_me') {
      // Delete for Me only: push actor.userId to deletedFor
      await DirectMessage.updateOne(
        { _id: msg._id },
        { $addToSet: { deletedFor: actor.userId } }
      );
      return res.status(200).json({ message: 'Message deleted for you', mode: 'for_me' });
    }

    // Delete for Everyone: only sender or owner/superadmin
    if (msg.senderId !== actor.userId && !['param', 'owner'].includes(actor.role)) {
      return res.status(403).json({ message: 'You can only delete your own messages for everyone' });
    }

    const convoId = msg.conversationId;
    await DirectMessage.deleteOne({ _id: msg._id });

    if (convo) {
      await emitToParticipants(convo.participants, 'dm:change', {
        action: 'delete',
        conversationId: convoId.toString(),
        messageId: msg._id.toString(),
        deletedForEveryone: true,
      });
    }

    res.status(200).json({ message: 'Message deleted for everyone', mode: 'for_everyone' });
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
};
