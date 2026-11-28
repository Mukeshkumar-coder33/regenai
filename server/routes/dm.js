import express from 'express';
import multer from 'multer';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import {
  getMessengerContacts,
  getOrCreateConversation,
  createGroupConversation,
  getMyConversations,
  getConversationMessages,
  sendDirectMessage,
  uploadMediaAttachment,
  markAsRead,
  storePublicKey,
  getConversationKeys,
  getUserConversationKey,
  storeUserConversationKey,
  editDirectMessage,
  deleteDirectMessage
} from '../controllers/dmController.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const assetsDir = path.resolve(__dirname, '..', '..', 'assets');
fs.mkdirSync(assetsDir, { recursive: true });

const dmUpload = multer({
  storage: multer.diskStorage({
    destination: (_req, _file, cb) => cb(null, assetsDir),
    filename: (_req, file, cb) => {
      const safeName = String(file.originalname || 'file')
        .replace(/[^a-zA-Z0-9._-]/g, '_')
        .replace(/^_+|_+$/g, '')
        .slice(0, 64) || 'media';
      const ext = path.extname(safeName) || '.bin';
      const mime = String(file.mimetype || '').toLowerCase();
      const isVideo = mime.startsWith('video') || safeName.includes('video') || /\.(mp4|mov|mkv|webm)$/i.test(ext);
      const isVoice = mime.startsWith('audio') || safeName.includes('voice');
      const prefix = isVideo ? 'dm-video' : (isVoice ? 'dm-voice' : 'dm-media');
      cb(null, `${prefix}-${Date.now()}-${Math.random().toString(36).slice(2, 7)}${ext}`);
    },
  }),
  limits: { fileSize: 30 * 1024 * 1024 },
});

const router = express.Router();

// Authorized Contacts (server-enforced role & company scope)
router.get('/contacts', getMessengerContacts);

// Multipart media/video/voice upload
router.post('/upload', dmUpload.single('file'), uploadMediaAttachment);

// Conversations (1:1 & Group)
router.post('/conversations', getOrCreateConversation);
router.post('/groups', createGroupConversation);
router.get('/conversations', getMyConversations);

// Messages within a conversation
router.get('/conversations/:conversationId/messages', getConversationMessages);
router.post('/conversations/:conversationId/messages', sendDirectMessage);
router.put('/conversations/:conversationId/read', markAsRead);

// E2E key exchange
router.get('/conversations/:conversationId/keys', getConversationKeys);
router.post('/conversations/:conversationId/keys', storePublicKey);
router.get('/conversations/:conversationId/my-key', getUserConversationKey);
router.post('/conversations/:conversationId/my-key', storeUserConversationKey);

// Edit / Delete individual messages
router.put('/messages/:messageId', editDirectMessage);
router.delete('/messages/:messageId', deleteDirectMessage);

export default router;
