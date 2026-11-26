import Task from '../models/Task.js';
import User from '../models/User.js';
import Company from '../models/Company.js';
import { resolveCompanyId } from '../utils/resolveCompanyId.js';
import { emitToCompany, emitToUser } from '../socket.js';
import { sendReportEmail } from '../utils/mailer.js';
import {
  assertCompanyReportAccess,
  resolveReportWindow,
  isDateInWindow,
  normalizeDateOnly,
  buildCompanyUserLookup,
  matchesEmployeeFilter,
  paginateItems,
  buildCsvDocument,
  getTodayDateStr,
} from '../utils/reportHelpers.js';

export const createTask = async (req, res) => {
  try {
    const body = { ...req.body };
    body.companyId = await resolveCompanyId(req, body);
    const task = new Task(body);
    await task.save();
    emitToCompany('task:change', task.companyId, { action: 'create', id: task.id });
    if (task.assignedTo) {
      try {
        const docCount = (task.attachments && task.attachments.length) || 0;
        const docMsg = docCount > 0 ? ` (with ${docCount} attached document${docCount > 1 ? 's' : ''})` : '';
        const notificationPayload = {
          id: `n-${Date.now()}-${Math.random().toString(36).slice(2, 7)}`,
          userId: task.assignedTo,
          companyId: task.companyId,
          title: 'New Task Assigned',
          message: `You have been assigned: ${task.title}${docMsg}`,
          type: 'project_task',
          metadata: { taskId: task.id, type: 'task_assigned' },
          createdAt: new Date().toISOString(),
          read: false
        };
        const { default: Notification } = await import('../models/Notification.js');
        const n = new Notification(notificationPayload);
        await n.save();
        // Emit exclusively to the assigned employee (never broadcast company-wide)
        await emitToUser(task.assignedTo, 'notification:new', n);
      } catch (e) {
        console.error(e);
      }
    }
    res.status(201).json(task);
  } catch (error) {
    res.status(400).json({ message: error.message });
  }
};

export const isTaskExpired = (task) => {
  if (!task) return false;
  if (task.status === 'done' || task.status === 'completed') return false;
  if (task.status === 'not_completed' || task.status === 'notCompleted') return true;

  const timeStr = task.dueTime || task.endTime;
  const endDateStr = task.endDate || task.dueDate;

  // 1. Explicit End Date + End Time
  if (endDateStr && timeStr) {
    const [hh, mm] = timeStr.split(':');
    const datePart = endDateStr.includes('T') ? endDateStr.split('T')[0] : endDateStr;
    const d = new Date(datePart + 'T00:00:00');
    d.setHours(parseInt(hh || 0, 10), parseInt(mm || 0, 10), 0, 0);
    if (!isNaN(d.getTime())) {
      return Date.now() > d.getTime();
    }
  }

  // 2. Duration in minutes
  if (task.durationUnit === 'minutes' && Number(task.durationValue) > 0) {
    const base = task.createdAt ? new Date(task.createdAt) : (task.startDate ? new Date(task.startDate) : null);
    if (base && !isNaN(base.getTime())) {
      const deadline = new Date(base.getTime() + Number(task.durationValue) * 60 * 1000);
      return Date.now() > deadline.getTime();
    }
  }

  // 3. Duration in hours
  if (task.durationUnit === 'hours' && Number(task.durationValue) > 0) {
    const base = task.createdAt ? new Date(task.createdAt) : (task.startDate ? new Date(task.startDate) : null);
    if (base && !isNaN(base.getTime())) {
      const deadline = new Date(base.getTime() + Number(task.durationValue) * 3600 * 1000);
      return Date.now() > deadline.getTime();
    }
  }

  // 4. End Date only (default end of day)
  if (endDateStr) {
    const datePart = endDateStr.includes('T') ? endDateStr.split('T')[0] : endDateStr;
    const parts = datePart.split('-');
    if (parts.length === 3) {
      const year = parseInt(parts[0], 10);
      const month = parseInt(parts[1], 10) - 1;
      const day = parseInt(parts[2], 10);
      const d = new Date(year, month, day, 23, 59, 59, 999);
      if (!isNaN(d.getTime())) {
        return Date.now() > d.getTime();
      }
    }
  }

  return false;
};

export const getAllTasks = async (req, res) => {
  try {
    const isEmsView = req.headers['x-portal-view'] === 'ems' || req.query.portalView === 'ems';
    const isSuperAdmin = req.user?.role === 'param' || req.user?.role === 'admin';
    const filter = (isSuperAdmin && !isEmsView) ? {} : (req.companyId ? { companyId: req.companyId } : {});
    const tasks = await Task.find(filter);

    // Auto-update any expired incomplete tasks to not_completed
    const processedTasks = await Promise.all(tasks.map(async (task) => {
      if (isTaskExpired(task) && task.status !== 'not_completed') {
        task.status = 'not_completed';
        await Task.updateOne({ _id: task._id }, { status: 'not_completed' });
      }
      return task;
    }));

    res.status(200).json(processedTasks);
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
};

export const updateTask = async (req, res) => {
  try {
    const id = req.body.id || req.params.id;
    const findFilter = { id };
    if (req.companyId) findFilter.companyId = req.companyId;
    const previous = await Task.findOne(findFilter);
    if (!previous) return res.status(404).json({ message: 'Task not found' });

    // If task was expired and incomplete, prevent marking it completed
    let reqStatus = req.body.status;
    if (reqStatus && typeof reqStatus === 'object') {
      if ('inProgress' in reqStatus || 'in_progress' in reqStatus) reqStatus = 'in_progress';
      else if ('completed' in reqStatus || 'done' in reqStatus) reqStatus = 'done';
      else if ('paused' in reqStatus) reqStatus = 'paused';
      else if ('blocked' in reqStatus) reqStatus = 'blocked';
      else if ('todo' in reqStatus) reqStatus = 'todo';
      req.body.status = reqStatus;
    }
    const isTryingToComplete = reqStatus === 'done' || reqStatus === 'completed';
    if (isTaskExpired(previous) && isTryingToComplete) {
      return res.status(400).json({ message: 'The assigned time for this task has ended. This task is marked as Not Completed and cannot be completed.' });
    }

    // Exclusivity: Only one task can be in_progress at a time per user.
    // If this task is starting (in_progress), pause all other running tasks and scrum notes for the same user.
    if (reqStatus === 'in_progress') {
      const targetUser = req.body.assignedTo || previous.assignedTo || req.body.assignee || previous.assignee;
      if (targetUser) {
        const pauseFilter = {
          id: { $ne: previous.id },
          $or: [
            { assignedTo: targetUser },
            { assignee: targetUser }
          ],
          status: 'in_progress'
        };
        if (req.companyId) pauseFilter.companyId = req.companyId;
        const runningOtherTasks = await Task.find(pauseFilter);
        if (runningOtherTasks.length > 0) {
          await Task.updateMany(pauseFilter, { status: 'paused' });
          runningOtherTasks.forEach(pt => {
            emitToCompany('task:change', pt.companyId || req.companyId, { action: 'update', id: pt.id, status: 'paused' });
          });
        }

        // Also pause other in_progress ScrumNotes for targetUser
        try {
          const { default: ScrumNote } = await import('../models/ScrumNote.js');
          const scrumPauseFilter = {
            userId: targetUser,
            status: 'in_progress',
            taskDetails: { $ne: previous.title }
          };
          if (req.companyId) scrumPauseFilter.companyId = req.companyId;
          await ScrumNote.updateMany(scrumPauseFilter, { status: 'paused', pausedAt: new Date().toISOString() });
        } catch (e) {}
      }
    }

    // Handle extension request approval
    if (req.body.extensionRequest && req.body.extensionRequest.status === 'accepted') {
      if (req.body.extensionRequest.requestedDueDate) {
        req.body.dueDate = req.body.extensionRequest.requestedDueDate;
        req.body.endDate = req.body.extensionRequest.requestedDueDate;
      }
      if (req.body.extensionRequest.requestedDueTime) {
        req.body.dueTime = req.body.extensionRequest.requestedDueTime;
      }
      if (previous.status === 'not_completed') {
        req.body.status = 'in_progress';
      }
    }

    if (req.body.progressPercentage !== undefined && req.body.progressPercentage !== null) {
      req.body.progressPercentage = Number(req.body.progressPercentage);
    }

    const task = await Task.findOneAndUpdate(findFilter, req.body, { new: true });
    if (!task) return res.status(404).json({ message: 'Task not found' });
    const { default: Notification } = await import('../models/Notification.js');

    // ------------------------------------------------------------------------
    // NOTIFICATIONS: Company Owner, Admins & Task Assignee
    // ------------------------------------------------------------------------
    try {
      const recipientUserIds = new Set();
      let notifTitle = '';
      let notifMessage = '';
      let notifMeta = {};
      let isForEmployee = false;
      let isForManagement = false;

      // 1. Employee requested deadline extension -> ONLY management receives
      if (task.extensionRequest?.status === 'pending' && previous.extensionRequest?.status !== 'pending') {
        notifTitle = 'Deadline Extension Requested';
        notifMessage = `Extra time requested for "${task.title}": ${task.extensionRequest.requestedDueDate || ''}. Reason: ${task.extensionRequest.reason || 'None provided'}`;
        notifMeta = {
          taskId: task.id,
          type: 'extension_request',
          requestedDueDate: task.extensionRequest.requestedDueDate,
          requestedDueTime: task.extensionRequest.requestedDueTime,
          reason: task.extensionRequest.reason,
          employeeName: task.extensionRequest.employeeName || ''
        };
        isForManagement = true;
      }
      // 2. Employee submitted completion report -> ONLY management receives
      else if (task.completionReport?.submittedAt && !previous.completionReport?.submittedAt) {
        const rep = task.completionReport;
        const repTime = rep.workingTime ? ` (Working Time: ${rep.workingTime})` : '';
        const repNotes = rep.reportText ? ` • Note: "${rep.reportText}"` : '';
        notifTitle = 'Task Completion Report';
        notifMessage = `Task "${task.title}" was completed by ${rep.employeeName || 'employee'}${repTime}${repNotes}`;
        notifMeta = {
          taskId: task.id,
          completionReport: rep,
          type: 'completion_report',
          workingTime: rep.workingTime,
          reportText: rep.reportText,
          employeeName: rep.employeeName
        };
        isForManagement = true;
      }
      // 3. Employee submitted daily progress -> ONLY management receives
      else if (
        (task.progressPercentage !== undefined && task.progressPercentage !== previous.progressPercentage) ||
        (task.progressUpdates?.length > (previous.progressUpdates?.length || 0))
      ) {
        const latestProg = task.progressUpdates && task.progressUpdates.length > 0
          ? task.progressUpdates[task.progressUpdates.length - 1]
          : null;
        const noteSnippet = latestProg?.updateText ? ` • Note: "${latestProg.updateText}"` : '';
        notifTitle = 'Task Progress Updated';
        notifMessage = `Task "${task.title}" progress updated to ${task.progressPercentage}% by ${latestProg?.employeeName || 'employee'}${noteSnippet}`;
        notifMeta = {
          taskId: task.id,
          progressPercentage: task.progressPercentage,
          latestProgress: latestProg,
          type: 'daily_progress',
          updateText: latestProg?.updateText,
          employeeName: latestProg?.employeeName
        };
        isForManagement = true;
      }
      // 4. Company Owner accepted deadline extension -> ONLY assigned employee receives
      else if (previous.extensionRequest?.status === 'pending' && task.extensionRequest?.status === 'accepted') {
        notifTitle = 'Extension Request Accepted';
        notifMessage = `Deadline extension for "${task.title}" was accepted. New deadline: ${task.dueDate || ''}`;
        notifMeta = { taskId: task.id, type: 'extension_accepted' };
        isForEmployee = true;
      }
      // 5. Company Owner rejected deadline extension -> ONLY assigned employee receives
      else if (previous.extensionRequest?.status === 'pending' && task.extensionRequest?.status === 'rejected') {
        notifTitle = 'Extension Request Rejected';
        notifMessage = `Deadline extension for "${task.title}" was rejected.`;
        notifMeta = { taskId: task.id, type: 'extension_rejected' };
        isForEmployee = true;
      }
      // 6. Generic task update from company
      else if (task.assignedTo && !req.body.extensionRequest && !req.body.progressPercentage && !req.body.completionReport) {
        notifTitle = 'Task Updated';
        notifMessage = `Your task was updated: ${task.title}`;
        notifMeta = { taskId: task.id, type: 'task_update' };
        isForEmployee = true;
      }

      const assignedEmployeeId = task.assignedTo ? String(task.assignedTo) : null;

      if (isForEmployee) {
        // ONLY the assigned employee receives task assignment / extension accept or decline!
        if (assignedEmployeeId) {
          recipientUserIds.add(assignedEmployeeId);
        }
      } else if (isForManagement) {
        // Company Owner & Admins receive daily, extra, completion notes!
        // Strictly exclude the employee who submitted them!
        if (task.companyId) {
          const adminUsers = await User.find({
            companyId: task.companyId,
            role: { $in: ['admin', 'owner', 'company_admin', 'superadmin', 'param'] }
          }).select('userId StaffId').lean();

          adminUsers.forEach(u => {
            const uid = u.userId || u.StaffId;
            if (uid && String(uid) !== assignedEmployeeId) {
              recipientUserIds.add(String(uid));
            }
          });

          const compDoc = await Company.findById(task.companyId).select('ownerId').lean();
          if (compDoc?.ownerId && String(compDoc.ownerId) !== assignedEmployeeId) {
            recipientUserIds.add(String(compDoc.ownerId));
          }
        }

        // Task Assignor (if distinct from assigned employee)
        if (task.assignorName) {
          const assignor = await User.findOne({
            $or: [{ username: task.assignorName }, { name: task.assignorName }]
          }).select('userId StaffId').lean();
          const aId = assignor?.userId || assignor?.StaffId;
          if (aId && String(aId) !== assignedEmployeeId) {
            recipientUserIds.add(String(aId));
          }
        }
      }

      if (notifTitle && notifMessage && recipientUserIds.size > 0) {
        for (const recipientId of recipientUserIds) {
          const nDoc = new Notification({
            id: `n-${Date.now()}-${Math.random().toString(36).slice(2, 7)}`,
            userId: recipientId,
            companyId: task.companyId,
            title: notifTitle,
            message: notifMessage,
            type: 'project_task',
            metadata: notifMeta,
            createdAt: new Date().toISOString(),
            read: false
          });
          await nDoc.save();
          // Emit strictly to the target recipient user — NOT broadcast to the whole company!
          await emitToUser(recipientId, 'notification:new', nDoc);
        }
      }
    } catch (notifErr) {
      console.error('[taskController] notification dispatch error:', notifErr);
    }
    emitToCompany('task:change', task.companyId, { action: 'update', id: task.id });
    res.status(200).json(task);
  } catch (error) {
    res.status(400).json({ message: error.message });
  }
};

export const deleteTask = async (req, res) => {
  try {
    const filter = { id: req.params.id };
    if (req.companyId) filter.companyId = req.companyId;
    const task = await Task.findOneAndDelete(filter);
    if (!task) return res.status(404).json({ message: 'Task not found' });
    emitToCompany('task:change', task.companyId, { action: 'delete', id: task.id });
    res.status(200).json({ message: 'Task deleted successfully' });
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
};

/**
 * Computes overdue hours cleanly against dueDate/endDate + dueTime/endTime.
 */
const computeTaskDelayInfo = (task, isCompleted) => {
  const dueDateStr = task.endDate || task.dueDate || '';
  if (!dueDateStr) return { isOverdue: false, overdueHours: 0, overdueLabel: '' };

  const dueTimeStr = task.dueTime || task.endTime || '23:59';
  const dueDateObj = new Date(`${dueDateStr}T${dueTimeStr.length === 5 ? `${dueTimeStr}:00` : '23:59:59'}`);
  if (isNaN(dueDateObj.getTime())) return { isOverdue: false, overdueHours: 0, overdueLabel: '' };

  const compareTime = isCompleted && task.completedAt
    ? new Date(task.completedAt)
    : new Date();
  if (isNaN(compareTime.getTime())) return { isOverdue: false, overdueHours: 0, overdueLabel: '' };

  const diffMs = compareTime.getTime() - dueDateObj.getTime();
  if (diffMs <= 0) return { isOverdue: false, overdueHours: 0, overdueLabel: '' };

  const overdueHours = Math.round((diffMs / 3600000) * 10) / 10;
  const days = Math.floor(overdueHours / 24);
  const remHours = Math.round(overdueHours % 24);
  const overdueLabel = days > 0 ? `${days}d ${remHours}h overdue` : `${overdueHours}h overdue`;
  return { isOverdue: true, overdueHours, overdueLabel };
};

/**
 * Derives chronological activity history strictly from real stored task fields.
 */
const buildTaskActivityHistory = (task) => {
  const events = [];
  if (task.createdAt) {
    events.push({
      type: 'created',
      timestamp: new Date(task.createdAt).toISOString(),
      actor: task.assignorName || 'Company',
      detail: `Task created and assigned to ${task.assignedTo || 'Unassigned'}`,
    });
  }
  if (task.startedAt) {
    events.push({
      type: 'started',
      timestamp: String(task.startedAt),
      actor: task.assignedTo || 'Employee',
      detail: 'Started working on task',
    });
  }
  if (Array.isArray(task.progressUpdates)) {
    for (const pu of task.progressUpdates) {
      events.push({
        type: 'progress_update',
        timestamp: pu.date || '',
        actor: pu.employeeName || pu.employeeId || 'Employee',
        detail: `${pu.percentage ?? 0}% — ${pu.updateText || 'Progress logged'}`,
      });
    }
  }
  if (task.extensionRequest && task.extensionRequest.status && task.extensionRequest.status !== 'none') {
    if (task.extensionRequest.requestedAt) {
      events.push({
        type: 'extension_requested',
        timestamp: task.extensionRequest.requestedAt,
        actor: task.assignedTo || 'Employee',
        detail: `Requested deadline ${task.extensionRequest.requestedDueDate || ''}: ${task.extensionRequest.reason || ''}`,
      });
    }
    if (task.extensionRequest.reviewedAt) {
      events.push({
        type: `extension_${task.extensionRequest.status}`,
        timestamp: task.extensionRequest.reviewedAt,
        actor: task.assignorName || 'Management',
        detail: `Extension ${task.extensionRequest.status}${task.extensionRequest.companyResponse ? `: ${task.extensionRequest.companyResponse}` : ''}`,
      });
    }
  }
  if (task.completionReport?.submittedAt) {
    events.push({
      type: 'completion_report',
      timestamp: task.completionReport.submittedAt,
      actor: task.completionReport.employeeName || task.assignedTo || 'Employee',
      detail: task.completionReport.reportText || 'Submitted completion report',
    });
  }
  if (task.completedAt) {
    events.push({
      type: 'completed',
      timestamp: String(task.completedAt),
      actor: task.completionReport?.employeeName || task.assignedTo || 'Employee',
      detail: `Task completed${task.workingTime ? ` (${task.workingTime})` : ''}`,
    });
  }
  return events.sort((a, b) => String(a.timestamp || '').localeCompare(String(b.timestamp || '')));
};

/**
 * Build Schedules & General/Project Tasks Report Data
 * Supports all historical timeframes (all | range | day | week | month | year),
 * employee/department/priority/status/scope filters, inactive employees, and pagination.
 */
export const buildSchedulesReportData = async (companyId, query = {}) => {
  const departmentFilter = query.department;
  const statusFilter = String(query.status || 'all').toLowerCase().trim();
  const priorityFilter = String(query.priority || 'all').toLowerCase().trim();
  const employeeFilter = query.userId || query.employeeId || 'all';
  const scopeFilter = String(query.scope || 'all').toLowerCase().trim(); // 'general' excludes project tasks
  const searchQuery = String(query.search || '').trim().toLowerCase();

  const [company, earliestTask, userLookup] = await Promise.all([
    Company.findById(companyId).select('name createdAt').lean(),
    Task.findOne({ companyId }).sort({ createdAt: 1 }).select('startDate createdAt').lean(),
    buildCompanyUserLookup(companyId),
  ]);

  const companyName = company?.name || 'Company';
  const earliestDate = earliestTask?.startDate || normalizeDateOnly(earliestTask?.createdAt || company?.createdAt);
  const window = resolveReportWindow(query, earliestDate);

  // Fetch all tasks for this company (strictly isolated by companyId)
  const taskFilter = { companyId };
  if (scopeFilter === 'general') {
    taskFilter.isProjectTask = { $ne: true };
    taskFilter.$or = [{ projectId: null }, { projectId: '' }, { projectId: { $exists: false } }];
  }
  let tasks = await Task.find(taskFilter).sort({ createdAt: -1 }).lean();

  const matchesPeriod = (t) => {
    if (window.period === 'all') return true;
    const sDate = normalizeDateOnly(t.startDate);
    const eDate = normalizeDateOnly(t.endDate || t.dueDate);
    const cDate = normalizeDateOnly(t.createdAt);
    const compDate = normalizeDateOnly(t.completedAt);

    if (window.startDate && window.endDate && sDate && (eDate || sDate)) {
      const spanEnd = eDate || sDate;
      if (sDate <= window.endDate && spanEnd >= window.startDate) return true;
    }
    return [sDate, eDate, cDate, compDate].some((d) => d && isDateInWindow(d, window));
  };

  let periodTasks = tasks.filter(matchesPeriod).map((t) => {
    const expired = isTaskExpired(t) && t.status !== 'not_completed' && t.status !== 'done' && t.status !== 'completed';
    const effectiveStatus = expired ? 'not_completed' : (t.status || 'todo');
    const isCompleted = effectiveStatus === 'done' || effectiveStatus === 'completed';
    const emp = userLookup.resolveUser(t.assignedTo, t.completionReport?.employeeName);
    const delay = computeTaskDelayInfo({ ...t, status: effectiveStatus }, isCompleted);

    let statusLabel = 'To Do';
    if (isCompleted) statusLabel = 'Completed';
    else if (effectiveStatus === 'not_completed') statusLabel = 'Not Completed';
    else if (effectiveStatus === 'in_progress') statusLabel = 'In Progress';
    else if (effectiveStatus === 'paused') statusLabel = 'Paused';
    else if (effectiveStatus === 'blocked') statusLabel = 'Blocked';
    else if (effectiveStatus === 'review') statusLabel = 'In Review';

    return {
      ...t,
      effectiveStatus,
      statusLabel,
      isCompleted,
      delay,
      emp,
    };
  });

  // Apply task-level filters
  if (employeeFilter && employeeFilter !== 'all') {
    periodTasks = periodTasks.filter((t) => matchesEmployeeFilter(t.emp, employeeFilter));
  }
  if (departmentFilter && departmentFilter !== 'all') {
    periodTasks = periodTasks.filter(
      (t) => (t.emp.department || '').toLowerCase() === String(departmentFilter).toLowerCase(),
    );
  }
  if (priorityFilter !== 'all') {
    periodTasks = periodTasks.filter((t) => String(t.priority || 'medium').toLowerCase() === priorityFilter);
  }
  if (statusFilter !== 'all') {
    periodTasks = periodTasks.filter((t) => {
      if (statusFilter === 'completed' || statusFilter === 'done') return t.isCompleted;
      if (statusFilter === 'overdue') return t.delay.isOverdue;
      if (statusFilter === 'in_progress') return t.effectiveStatus === 'in_progress' || t.effectiveStatus === 'paused';
      return t.effectiveStatus === statusFilter;
    });
  }
  if (searchQuery) {
    periodTasks = periodTasks.filter((t) =>
      (t.title || '').toLowerCase().includes(searchQuery) ||
      (t.description || '').toLowerCase().includes(searchQuery) ||
      (t.assignorName || '').toLowerCase().includes(searchQuery) ||
      (t.emp.name || '').toLowerCase().includes(searchQuery) ||
      (t.emp.staffId || '').toLowerCase().includes(searchQuery) ||
      (t.emp.department || '').toLowerCase().includes(searchQuery) ||
      (t.projectName || '').toLowerCase().includes(searchQuery),
    );
  }

  // Group enriched task metrics by employee (including former/inactive assignees)
  const groupedByEmp = new Map();
  const flatRecords = [];

  for (const t of periodTasks) {
    const empKey = t.emp.userId || String(t.assignedTo || 'unassigned');
    if (!groupedByEmp.has(empKey)) {
      groupedByEmp.set(empKey, {
        userId: empKey,
        staffId: t.emp.staffId,
        name: t.emp.name,
        email: t.emp.user?.email || '',
        department: t.emp.department,
        designation: t.emp.designation,
        joiningDate: t.emp.joiningDate,
        employeeStatus: t.emp.employeeStatus,
        avatar: t.emp.user?.avatar || '',
        totalTasks: 0,
        completedTasks: 0,
        inProgressTasks: 0,
        pausedTasks: 0,
        todoTasks: 0,
        notCompletedTasks: 0,
        overdueTasks: 0,
        completionRate: 0,
        tasks: [],
      });
    }

    const bucket = groupedByEmp.get(empKey);
    const createdDateStr = normalizeDateOnly(t.createdAt);
    const completedDateStr = normalizeDateOnly(t.completedAt || t.completionReport?.submittedAt);
    const dueDateStr = t.endDate || t.dueDate || '';
    const activityHistory = buildTaskActivityHistory(t);

    const taskDetail = {
      id: t.id,
      title: t.title,
      description: t.description || '',
      projectId: t.projectId || null,
      projectName: t.projectName || 'General',
      isProjectTask: !!t.isProjectTask,
      priority: t.priority || 'medium',
      createdAt: t.createdAt || null,
      createdDate: createdDateStr,
      startDate: t.startDate || '',
      endDate: dueDateStr,
      dueDate: dueDateStr,
      dueTime: t.dueTime || t.endTime || '',
      startedAt: t.startedAt || '',
      completedAt: t.completedAt || '',
      completedDate: completedDateStr,
      completionTime: t.completionTime || t.workingTime || '',
      workingTime: t.workingTime || t.completionTime || '',
      status: t.effectiveStatus,
      statusLabel: t.statusLabel,
      isCompleted: t.isCompleted,
      isOverdue: t.delay.isOverdue,
      overdueHours: t.delay.overdueHours,
      overdueLabel: t.delay.overdueLabel,
      progressPercentage: Number(t.progressPercentage) || (t.isCompleted ? 100 : 0),
      assignorName: t.assignorName || 'Company',
      progressUpdates: Array.isArray(t.progressUpdates) ? t.progressUpdates : [],
      completionReport: t.completionReport || null,
      extensionRequest: t.extensionRequest || null,
      activityHistory,
    };

    bucket.totalTasks += 1;
    if (t.isCompleted) bucket.completedTasks += 1;
    else if (t.effectiveStatus === 'in_progress') bucket.inProgressTasks += 1;
    else if (t.effectiveStatus === 'paused') bucket.pausedTasks += 1;
    else if (t.effectiveStatus === 'todo') bucket.todoTasks += 1;
    else if (t.effectiveStatus === 'not_completed') bucket.notCompletedTasks += 1;
    if (t.delay.isOverdue) bucket.overdueTasks += 1;
    bucket.tasks.push(taskDetail);

    flatRecords.push({
      id: t.id,
      date: t.startDate || createdDateStr || dueDateStr || '',
      createdDate: createdDateStr,
      employeeId: t.emp.staffId,
      userId: empKey,
      employeeName: t.emp.name,
      department: t.emp.department,
      designation: t.emp.designation,
      joiningDate: t.emp.joiningDate,
      employeeStatus: t.emp.employeeStatus,
      assignorName: t.assignorName || 'Company',
      taskTitle: t.title,
      description: t.description || '',
      project: t.projectName || 'General',
      isProjectTask: !!t.isProjectTask,
      priority: t.priority || 'medium',
      startDate: t.startDate || '',
      dueDate: dueDateStr,
      completedAt: t.completedAt || '',
      completedDate: completedDateStr,
      workingTime: t.workingTime || t.completionTime || '',
      progressPercentage: taskDetail.progressPercentage,
      status: t.statusLabel,
      rawStatus: t.effectiveStatus,
      isCompleted: t.isCompleted ? 'Completed' : (t.effectiveStatus === 'not_completed' ? 'Not Completed' : 'Pending'),
      isOverdue: t.delay.isOverdue,
      overdueHours: t.delay.overdueHours,
      overdueLabel: t.delay.overdueLabel,
      progressUpdates: taskDetail.progressUpdates,
      completionReport: taskDetail.completionReport,
      extensionRequest: taskDetail.extensionRequest,
      activityHistory,
    });
  }

  const employeeStats = Array.from(groupedByEmp.values()).map((e) => ({
    ...e,
    completionRate: e.totalTasks > 0 ? Math.round((e.completedTasks / e.totalTasks) * 100) : 0,
  }));

  const totalTasks = flatRecords.length;
  const totalCompleted = periodTasks.filter((t) => t.isCompleted).length;
  const totalInProgress = periodTasks.filter((t) => t.effectiveStatus === 'in_progress' || t.effectiveStatus === 'paused').length;
  const totalTodo = periodTasks.filter((t) => t.effectiveStatus === 'todo').length;
  const totalNotCompleted = periodTasks.filter((t) => t.effectiveStatus === 'not_completed').length;
  const totalOverdue = periodTasks.filter((t) => t.delay.isOverdue).length;
  const overallCompletionRate = totalTasks > 0 ? Math.round((totalCompleted / totalTasks) * 100) : 0;
  const employeesWithTasks = employeeStats.filter((e) => e.totalTasks > 0).length;

  const csvHeaders = [
    'Task ID', 'Task Name', 'Description', 'Assigned To', 'Employee ID', 'Department',
    'Assigned By', 'Scope', 'Priority', 'Progress (%)', 'Created Date', 'Start Date',
    'Due Date', 'Completed Date', 'Working Time', 'Status', 'Overdue', 'Completion Notes',
  ];
  const csvRows = flatRecords.map((r) => [
    r.id,
    r.taskTitle,
    r.description,
    r.employeeName,
    r.employeeId,
    r.department,
    r.assignorName,
    r.isProjectTask ? `Project (${r.project})` : 'General',
    r.priority,
    `${r.progressPercentage}%`,
    r.createdDate,
    r.startDate,
    r.dueDate,
    r.completedDate,
    r.workingTime,
    r.status,
    r.overdueLabel || 'On Time',
    r.completionReport?.reportText || '',
  ]);

  const csvContent = buildCsvDocument(
    [
      `# ${companyName} - Historical ${scopeFilter === 'general' ? 'General Tasks' : 'Schedules & Tasks'} Report`,
      `# Period: ${window.periodLabel}`,
      `# Generated: ${new Date().toLocaleString()}`,
      `# Summary: Total Tasks: ${totalTasks} | Completed: ${totalCompleted} (${overallCompletionRate}%) | In Progress: ${totalInProgress} | Overdue: ${totalOverdue} | Not Completed: ${totalNotCompleted}`,
    ],
    csvHeaders,
    csvRows,
  );

  const paged = paginateItems(flatRecords, query);

  return {
    companyName,
    period: window.period,
    periodLabel: window.periodLabel,
    startDate: window.startDate,
    endDate: window.endDate,
    scope: scopeFilter,
    totalTasks,
    totalCompleted,
    totalInProgress,
    totalTodo,
    totalNotCompleted,
    totalOverdue,
    overallCompletionRate,
    totalEmployees: userLookup.staffUsers.length,
    employeesWithTasks,
    employees: employeeStats,
    employeeOptions: userLookup.employeeOptions,
    departments: userLookup.departments,
    records: paged.items,
    pagination: paged.pagination,
    csvContent,
  };
};

/**
 * Controller: Get Schedules & Tasks Report (JSON + CSV)
 */
export const getSchedulesReport = async (req, res) => {
  try {
    if (!assertCompanyReportAccess(req, res)) return;

    const report = await buildSchedulesReportData(req.companyId, req.query);
    res.status(200).json(report);
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
};

/**
 * Controller: Send Schedules Report via Email
 */
export const sendSchedulesReport = async (req, res) => {
  try {
    if (!assertCompanyReportAccess(req, res)) return;

    const { recipientEmail, notes, ...filterParams } = req.body;
    if (!recipientEmail || !recipientEmail.trim()) {
      return res.status(400).json({ message: 'Recipient email is required' });
    }

    const report = await buildSchedulesReportData(req.companyId, { ...filterParams, limit: 'all' });

    const summaryMetrics = [
      { label: 'Total Tasks Assigned', value: `${report.totalTasks}` },
      { label: 'Completed Tasks', value: `${report.totalCompleted} (${report.overallCompletionRate}%)` },
      { label: 'In Progress / Running', value: `${report.totalInProgress}` },
      { label: 'Pending / To Do', value: `${report.totalTodo}` },
      { label: 'Not Completed / Expired', value: `${report.totalNotCompleted}` },
      { label: 'Employees with Tasks', value: `${report.employeesWithTasks} / ${report.totalEmployees}` },
    ];

    const filename = `Schedules_Report_${report.companyName.replace(/[^a-zA-Z0-9]/g, '_')}_${report.periodLabel.replace(/[^a-zA-Z0-9]/g, '_')}.csv`;

    const mailResult = await sendReportEmail({
      to: recipientEmail.trim(),
      subject: `Schedules & Tasks Report - ${report.companyName} (${report.periodLabel})`,
      companyName: report.companyName,
      reportType: 'Schedules & Tasks Performance Report',
      periodLabel: report.periodLabel,
      summaryMetrics,
      notes: notes ? String(notes).trim() : '',
      csvContent: report.csvContent,
      filename,
    });

    res.status(200).json({
      message: mailResult.simulated
        ? `Schedules report prepared for ${recipientEmail} (Simulated send: SMTP not configured)`
        : `Schedules report successfully sent to ${recipientEmail}`,
      mailResult,
      summary: {
        totalTasks: report.totalTasks,
        totalCompleted: report.totalCompleted,
        overallCompletionRate: report.overallCompletionRate,
        periodLabel: report.periodLabel,
      }
    });
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
};
