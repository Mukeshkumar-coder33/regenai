import express from 'express';
import { 
  createNotification, 
  getUserNotifications, 
  deleteNotification, 
  runBirthdayReminders,
  markNotificationRead,
  markAllNotificationsRead,
  updateNotificationAction,
  clearAllNotifications,
  registerDeviceToken,
  unregisterDeviceToken,
  getCommunicationDiagnostics
} from '../controllers/notificationController.js';

const router = express.Router();

router.get('/diagnostics', getCommunicationDiagnostics);
router.post('/', createNotification);
router.post('/device-token', registerDeviceToken);
router.delete('/device-token', unregisterDeviceToken);
router.post('/birthday-reminders/run', runBirthdayReminders);
router.get('/user/:userId', getUserNotifications);
router.put('/:id/read', markNotificationRead);
router.put('/user/:userId/read-all', markAllNotificationsRead);
router.put('/:id/action', updateNotificationAction);
router.delete('/user/:userId/clear-all', clearAllNotifications);
router.delete('/clear-all', clearAllNotifications);
router.delete('/:id', deleteNotification);

export default router;

