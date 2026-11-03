import express from 'express';
import { createLeave, getAllLeaves, getUserLeaves, updateLeaveStatus, deleteLeave } from '../controllers/leaveController.js';

const router = express.Router();

router.post('/', createLeave);
router.get('/', getAllLeaves);
router.get('/user/:userId', getUserLeaves);
router.put('/:id', updateLeaveStatus);
router.delete('/:id', deleteLeave);

export default router;
