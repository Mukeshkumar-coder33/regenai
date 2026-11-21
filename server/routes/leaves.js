import express from 'express';
import { 
  createLeave, 
  getAllLeaves, 
  getUserLeaves, 
  updateLeaveStatus, 
  deleteLeave,
  getLeavePolicy,
  updateLeavePolicy,
  getLeaveBalance
} from '../controllers/leaveController.js';

const router = express.Router();

router.get('/policy', getLeavePolicy);
router.put('/policy', updateLeavePolicy);
router.get('/balance', getLeaveBalance);
router.get('/balance/:userId', getLeaveBalance);

router.post('/', createLeave);
router.get('/', getAllLeaves);
router.get('/user/:userId', getUserLeaves);
router.put('/:id', updateLeaveStatus);
router.delete('/:id', deleteLeave);

export default router;
