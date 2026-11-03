import Leave from '../models/Leave.js';
import Company from '../models/Company.js';
import User from '../models/User.js';
import Notification from '../models/Notification.js';
import mongoose from 'mongoose';
import { resolveCompanyId } from '../utils/resolveCompanyId.js';
import { emitToCompany, emitToUser } from '../socket.js';

export const createLeave = async (req, res) => {
  try {
    const body = { ...req.body };
    if (!body.id) body.id = new mongoose.Types.ObjectId().toString();
    if (!body.createdAt) body.createdAt = new Date().toISOString();
    if (!body.status) body.status = 'pending';
    body.companyId = await resolveCompanyId(req, body);
    const leave = new Leave(body);
    await leave.save();
    emitToCompany('payroll:change', leave.companyId, { action: 'leave_created', userId: leave.userId });

    // Send notification to Company Owner
    try {
      if (leave.companyId) {
        const comp = await Company.findById(leave.companyId).lean();
        if (comp && comp.ownerId) {
          const ownerUser = await User.findOne({
            $or: [
              { userId: comp.ownerId },
              { username: comp.ownerId },
              { _id: mongoose.isValidObjectId(comp.ownerId) ? comp.ownerId : null }
            ]
          }).select('userId username').lean();

          const targetOwnerId = ownerUser?.userId || comp.ownerId;
          const notif = new Notification({
            id: `leave-apply-${leave.id}`,
            companyId: leave.companyId,
            userId: targetOwnerId,
            title: 'Leave Application',
            message: `${leave.employeeName || 'An employee'} applied for ${leave.type || 'leave'} from ${leave.startDate} to ${leave.endDate}.`,
            type: 'leave',
            createdAt: new Date().toISOString(),
            read: false,
          });
          await notif.save();
          emitToUser(targetOwnerId, 'notification:new', notif);
        }
      }
    } catch (e) {
      console.error('Leave creation notification error:', e.message);
    }

    res.status(201).json(leave);
  } catch (error) {
    res.status(400).json({ message: error.message });
  }
};

export const getAllLeaves = async (req, res) => {
  try {
    const isSuperAdminView = req.headers['x-portal-view'] === 'superadmin' || req.query.portalView === 'superadmin';
    const isEmsView = req.headers['x-portal-view'] === 'ems' || req.query.portalView === 'ems';
    const isSuperAdmin = req.user?.role === 'param' || req.user?.role === 'admin' || isSuperAdminView;
    const filter = (isSuperAdmin && !isEmsView) ? {} : (req.companyId ? { companyId: req.companyId } : {});
    const leaves = await Leave.find(filter);
    res.status(200).json(leaves);
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
};

export const getUserLeaves = async (req, res) => {
  try {
    const filter = { userId: req.params.userId };
    if (req.companyId) filter.companyId = req.companyId;
    const leaves = await Leave.find(filter);
    res.status(200).json(leaves);
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
};

export const updateLeaveStatus = async (req, res) => {
  try {
    const id = req.params.id;
    const filter = mongoose.isValidObjectId(id) ? { $or: [{ id }, { _id: id }] } : { id };
    if (req.companyId) filter.companyId = req.companyId;
    const leave = await Leave.findOneAndUpdate(filter, { status: req.body.status }, { new: true });
    if (!leave) return res.status(404).json({ message: 'Leave not found' });
    emitToCompany('payroll:change', leave.companyId, { action: 'leave_updated', userId: leave.userId });

    // Send notification to employee
    try {
      if (leave.userId) {
        const notif = new Notification({
          id: `leave-status-${leave.id}-${Date.now()}`,
          companyId: leave.companyId,
          userId: leave.userId,
          title: `Leave Application ${req.body.status === 'approved' ? 'Approved' : 'Rejected'}`,
          message: `Your leave request for ${leave.startDate} to ${leave.endDate} has been ${req.body.status}.`,
          type: 'leave',
          createdAt: new Date().toISOString(),
          read: false,
        });
        await notif.save();
        emitToUser(leave.userId, 'notification:new', notif);
      }
    } catch (e) {
      console.error('Leave update notification error:', e.message);
    }

    res.status(200).json(leave);
  } catch (error) {
    res.status(400).json({ message: error.message });
  }
};

export const deleteLeave = async (req, res) => {
  try {
    const id = req.params.id;
    const filter = mongoose.isValidObjectId(id) ? { $or: [{ id }, { _id: id }] } : { id };
    if (req.companyId) filter.companyId = req.companyId;
    const leave = await Leave.findOneAndDelete(filter);
    if (!leave) return res.status(404).json({ message: 'Leave not found' });
    emitToCompany('payroll:change', leave.companyId, { action: 'leave_deleted', userId: leave.userId });
    res.status(200).json({ success: true, message: 'Leave removed successfully' });
  } catch (error) {
    res.status(400).json({ message: error.message });
  }
};
