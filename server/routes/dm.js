import express from 'express';
import {
  getMessengerContacts,
  getOrCreateConversation,
  createGroupConversation,
  getMyConversations,
  getConversationMessages,
  sendDirectMessage,
  markAsRead,
  storePublicKey,
  getConversationKeys,
  getUserConversationKey,
  storeUserConversationKey,
  editDirectMessage,
  deleteDirectMessage
} from '../controllers/dmController.js';

const router = express.Router();

// Authorized Contacts (server-enforced role & company scope)
router.get('/contacts', getMessengerContacts);

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
