import Project from '../models/Project.js';
import Task from '../models/Task.js';
import User from '../models/User.js';
import Company from '../models/Company.js';
import Notification from '../models/Notification.js';
import { safeRandomUUID } from '../utils/safeRandomUUID.js';
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

/**
 * Controller: Get all projects for current company
 */
export const getProjects = async (req, res) => {
  try {
    const isEmsView = req.headers['x-portal-view'] === 'ems' || req.query.portalView === 'ems';
    const isSuperAdmin = req.user?.role === 'param' || req.user?.role === 'admin';
    const companyId = req.query.companyId || req.companyId;

    if (!companyId && (!isSuperAdmin || isEmsView)) {
      return res.status(400).json({ message: 'Company context required' });
    }

    const filter = companyId ? { companyId } : {};
    const projects = await Project.find(filter).sort({ createdAt: -1 }).lean();

    // Enrich each project with task counts
    const projectIds = projects.map(p => p.id);
    const taskFilter = { projectId: { $in: projectIds } };
    if (companyId) taskFilter.companyId = companyId;

    const tasks = await Task.find(taskFilter).lean();

    const taskMap = new Map();
    tasks.forEach(t => {
      const pId = t.projectId;
      if (!taskMap.has(pId)) {
        taskMap.set(pId, { total: 0, completed: 0, inProgress: 0 });
      }
      const entry = taskMap.get(pId);
      entry.total += 1;
      const status = typeof t.status === 'string' ? t.status : Object.keys(t.status || {})[0];
      if (status === 'done' || status === 'completed') entry.completed += 1;
      else if (status === 'in_progress') entry.inProgress += 1;
    });

    const enriched = projects.map(p => ({
      ...p,
      taskMetrics: taskMap.get(p.id) || { total: 0, completed: 0, inProgress: 0 }
    }));

    res.status(200).json(enriched);
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
};

/**
 * Controller: Create Project
 */
export const createProject = async (req, res) => {
  try {
    const companyId = req.companyId;
    const { name, description, assignedEmployees = [], priority = 'medium', startDate, dueDate } = req.body;

    if (!name || !name.trim()) {
      return res.status(400).json({ message: 'Project name is required' });
    }

    if (!companyId) {
      return res.status(400).json({ message: 'Company context required' });
    }

    const projectId = safeRandomUUID();
    const creator = req.user?.name || req.user?.username || 'Company Admin';

    const project = new Project({
      id: projectId,
      companyId,
      name: name.trim(),
      description: description ? description.trim() : '',
      assignedEmployees,
      priority,
      startDate: startDate || '',
      dueDate: dueDate || '',
      createdBy: creator
    });

    await project.save();

    // Send notifications to all assigned employees
    for (const emp of assignedEmployees) {
      const uId = emp.userId;
      if (!uId) continue;

      await Notification.create({
        id: safeRandomUUID(),
        companyId,
        userId: uId,
        title: `Added to Project: ${project.name}`,
        message: `You have been assigned as a team member on project "${project.name}".`,
        type: 'general',
        senderName: creator,
        createdAt: new Date().toISOString(),
        metadata: { projectId: project.id, projectName: project.name }
      });
    }

    const io = req.app.get('io');
    if (io) {
      io.to(`company:${companyId}`).emit('project:created', project);
    }

    res.status(201).json(project);
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
};

/**
 * Controller: Update Project
 */
export const updateProject = async (req, res) => {
  try {
    const companyId = req.companyId;
    const { id } = req.params;
    const updates = { ...req.body };

    const project = await Project.findOneAndUpdate(
      { id, companyId },
      updates,
      { new: true }
    );

    if (!project) return res.status(404).json({ message: 'Project not found' });

    // Update projectName on all existing tasks if name changed
    if (updates.name) {
      await Task.updateMany(
        { projectId: id, companyId },
        { $set: { projectName: updates.name.trim() } }
      );
    }

    const io = req.app.get('io');
    if (io) {
      io.to(`company:${companyId}`).emit('project:updated', project);
    }

    res.status(200).json(project);
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
};

/**
 * Controller: Delete Project
 */
export const deleteProject = async (req, res) => {
  try {
    const companyId = req.companyId;
    const { id } = req.params;

    const project = await Project.findOneAndDelete({ id, companyId });
    if (!project) return res.status(404).json({ message: 'Project not found' });

    // Unlink tasks
    await Task.updateMany(
      { projectId: id, companyId },
      { $unset: { projectId: 1, projectName: 1 }, $set: { isProjectTask: false } }
    );

    const io = req.app.get('io');
    if (io) {
      io.to(`company:${companyId}`).emit('project:deleted', { id });
    }

    res.status(200).json({ message: 'Project deleted successfully' });
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
};

/**
 * Controller: Create Task(s) inside a Project
 * Supports assigning to an individual project member OR assigning to ALL employees in the project!
 */
export const createProjectTask = async (req, res) => {
  try {
    const companyId = req.companyId;
    const { id } = req.params; // projectId
    const {
      title,
      description,
      priority = 'medium',
      durationValue,
      durationUnit = 'days',
      startDate,
      endDate,
      dueTime,
      assignToAll = false,
      assignedTo // userId if individual
    } = req.body;

    if (!title || !title.trim()) {
      return res.status(400).json({ message: 'Task title is required' });
    }

    const project = await Project.findOne({ id, companyId });
    if (!project) return res.status(404).json({ message: 'Project not found' });

    const assignor = req.user?.name || req.user?.username || 'Project Lead';
    const durVal = parseFloat(durationValue);
    const validDuration = !isNaN(durVal) && durVal > 0 ? durVal : undefined;

    // Determine target assignees
    let targetAssignees = [];
    if (assignToAll) {
      if (!project.assignedEmployees || project.assignedEmployees.length === 0) {
        return res.status(400).json({ message: 'Project has no assigned team members to assign task to' });
      }
      targetAssignees = project.assignedEmployees.map(e => ({
        userId: e.userId,
        name: e.name || e.username || e.userId
      }));
    } else {
      if (!assignedTo) {
        return res.status(400).json({ message: 'Please select an employee for this project task' });
      }
      const member = (project.assignedEmployees || []).find(e => e.userId === assignedTo);
      targetAssignees = [{
        userId: assignedTo,
        name: member?.name || member?.username || assignedTo
      }];
    }

    const createdTasks = [];
    const io = req.app.get('io');

    for (const assignee of targetAssignees) {
      const taskId = safeRandomUUID();
      const newTask = new Task({
        id: taskId,
        companyId,
        title: title.trim(),
        description: description ? description.trim() : '',
        assignedTo: assignee.userId,
        assignorName: assignor,
        priority,
        durationValue: validDuration,
        durationUnit,
        startDate: startDate || new Date().toISOString().split('T')[0],
        endDate: endDate || '',
        dueTime: dueTime || '',
        endTime: dueTime || '',
        status: 'todo',
        projectId: project.id,
        projectName: project.name,
        isProjectTask: true
      });

      await newTask.save();
      createdTasks.push(newTask);

      // Send project_task notification to employee
      await Notification.create({
        id: safeRandomUUID(),
        companyId,
        userId: assignee.userId,
        title: `Project Task: ${title.trim()}`,
        message: `You have been assigned "${title.trim()}" in project "${project.name}".`,
        type: 'project_task',
        senderName: assignor,
        createdAt: new Date().toISOString(),
        metadata: {
          taskId,
          projectId: project.id,
          projectName: project.name,
          title: title.trim(),
          dueDate: endDate || ''
        }
      });

      if (io) {
        io.to(`company:${companyId}`).emit('task:created', newTask);
      }
    }

    res.status(201).json({
      message: `Created ${createdTasks.length} task(s) under project "${project.name}"`,
      tasks: createdTasks
    });
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
};

/**
 * Builds complete historical Project Report data across all company projects and associated tasks.
 */
export const buildProjectReportData = async (companyId, query = {}) => {
  const projectFilterId = String(query.projectId || 'all').trim();
  const employeeFilter = query.userId || query.employeeId || 'all';
  const departmentFilter = String(query.department || 'all').trim();
  const statusFilter = String(query.status || 'all').toLowerCase().trim();
  const priorityFilter = String(query.priority || 'all').toLowerCase().trim();
  const searchQuery = String(query.search || '').trim().toLowerCase();

  const [company, allProjects, allProjectTasks, userLookup] = await Promise.all([
    Company.findById(companyId).select('name createdAt').lean(),
    Project.find({ companyId }).sort({ createdAt: -1 }).lean(),
    Task.find({
      companyId,
      $or: [{ isProjectTask: true }, { projectId: { $nin: [null, ''] } }],
    }).sort({ createdAt: -1 }).lean(),
    buildCompanyUserLookup(companyId),
  ]);

  const companyName = company?.name || 'Company';
  const todayStr = getTodayDateStr();
  const earliestProjectDate = allProjects.reduce((min, p) => {
    const d = normalizeDateOnly(p.startDate || p.createdAt);
    return d && (!min || d < min) ? d : min;
  }, '') || normalizeDateOnly(company?.createdAt);
  const window = resolveReportWindow(query, earliestProjectDate);

  // Index tasks by projectId
  const tasksByProject = new Map();
  for (const t of allProjectTasks) {
    if (!t.projectId) continue;
    if (!tasksByProject.has(t.projectId)) tasksByProject.set(t.projectId, []);
    tasksByProject.get(t.projectId).push(t);
  }

  let projectEntries = allProjects
    .filter((p) => {
      if (projectFilterId !== 'all' && p.id !== projectFilterId) return false;
      if (priorityFilter !== 'all' && String(p.priority || 'medium').toLowerCase() !== priorityFilter) return false;
      if (window.period !== 'all') {
        const s = normalizeDateOnly(p.startDate || p.createdAt);
        const e = normalizeDateOnly(p.dueDate);
        const c = normalizeDateOnly(p.createdAt);
        const spanMatch = window.startDate && window.endDate && s && (e || s) &&
          s <= window.endDate && (e || s) >= window.startDate;
        const pointMatch = [s, e, c].some((d) => d && isDateInWindow(d, window));
        const projectTasks = tasksByProject.get(p.id) || [];
        const hasTaskInWindow = projectTasks.some((t) => {
          const ts = normalizeDateOnly(t.startDate || t.createdAt);
          const te = normalizeDateOnly(t.endDate || t.dueDate || t.completedAt);
          return [ts, te].some((d) => d && isDateInWindow(d, window));
        });
        if (!spanMatch && !pointMatch && !hasTaskInWindow) return false;
      }
      return true;
    })
    .map((p) => {
      const rawTasks = tasksByProject.get(p.id) || [];
      const memberMap = new Map();

      for (const m of (p.assignedEmployees || [])) {
        const emp = userLookup.resolveUser(m.userId, m.name || m.username);
        memberMap.set(emp.userId, emp);
      }

      const enrichedTasks = rawTasks.map((t) => {
        const emp = userLookup.resolveUser(t.assignedTo, t.completionReport?.employeeName);
        if (!memberMap.has(emp.userId)) memberMap.set(emp.userId, emp);

        const rawStatus = typeof t.status === 'string' ? t.status : 'todo';
        const isCompleted = rawStatus === 'done' || rawStatus === 'completed';
        const dueStr = t.endDate || t.dueDate || '';
        const isOverdue = !isCompleted && dueStr && dueStr < todayStr;

        return {
          id: t.id,
          title: t.title,
          description: t.description || '',
          assignedTo: emp.userId,
          employeeId: emp.staffId,
          employeeName: emp.name,
          department: emp.department,
          designation: emp.designation,
          employeeStatus: emp.employeeStatus,
          assignorName: t.assignorName || p.createdBy || 'Project Lead',
          status: rawStatus,
          priority: t.priority || 'medium',
          progressPercentage: Number(t.progressPercentage) || (isCompleted ? 100 : 0),
          startDate: t.startDate || '',
          dueDate: dueStr,
          dueTime: t.dueTime || t.endTime || '',
          startedAt: t.startedAt || '',
          completedAt: t.completedAt || '',
          workingTime: t.workingTime || t.completionTime || '',
          isCompleted,
          isOverdue,
          progressUpdates: Array.isArray(t.progressUpdates) ? t.progressUpdates : [],
          completionReport: t.completionReport || null,
          extensionRequest: t.extensionRequest || null,
          createdAt: t.createdAt || null,
          updatedAt: t.updatedAt || null,
        };
      });

      // Compute employee contribution matrix strictly from project tasks & assignments
      const contribMap = new Map();
      for (const emp of memberMap.values()) {
        contribMap.set(emp.userId, {
          userId: emp.userId,
          staffId: emp.staffId,
          name: emp.name,
          department: emp.department,
          designation: emp.designation,
          joiningDate: emp.joiningDate,
          employeeStatus: emp.employeeStatus,
          assignedTasks: 0,
          completedTasks: 0,
          inProgressTasks: 0,
          pendingTasks: 0,
          overdueTasks: 0,
          avgProgress: 0,
          _progressSum: 0,
        });
      }
      for (const t of enrichedTasks) {
        const entry = contribMap.get(t.assignedTo);
        if (!entry) continue;
        entry.assignedTasks += 1;
        entry._progressSum += t.progressPercentage;
        if (t.isCompleted) entry.completedTasks += 1;
        else if (t.status === 'in_progress' || t.status === 'paused') entry.inProgressTasks += 1;
        else entry.pendingTasks += 1;
        if (t.isOverdue) entry.overdueTasks += 1;
      }
      const employeeContributions = Array.from(contribMap.values()).map(({ _progressSum, ...c }) => ({
        ...c,
        avgProgress: c.assignedTasks > 0 ? Math.round(_progressSum / c.assignedTasks) : 0,
      }));

      const totalTasks = enrichedTasks.length;
      const completedTasks = enrichedTasks.filter((t) => t.isCompleted).length;
      const inProgressTasks = enrichedTasks.filter((t) => t.status === 'in_progress' || t.status === 'paused').length;
      const pendingTasks = totalTasks - completedTasks - inProgressTasks;
      const overdueTasks = enrichedTasks.filter((t) => t.isOverdue).length;
      const averageProgress = totalTasks > 0
        ? Math.round(enrichedTasks.reduce((sum, t) => sum + t.progressPercentage, 0) / totalTasks)
        : (p.status === 'completed' ? 100 : 0);
      const completionRate = totalTasks > 0
        ? Math.round((completedTasks / totalTasks) * 100)
        : (p.status === 'completed' ? 100 : 0);

      const isDelayed = p.status !== 'completed' && p.dueDate && p.dueDate < todayStr;
      let overdueDays = 0;
      if (isDelayed) {
        const dDue = new Date(`${p.dueDate}T00:00:00`);
        const dNow = new Date(`${todayStr}T00:00:00`);
        if (!isNaN(dDue.getTime()) && !isNaN(dNow.getTime())) {
          overdueDays = Math.max(0, Math.round((dNow.getTime() - dDue.getTime()) / 86400000));
        }
      }

      // Chronological activity history strictly from real stored project & task records
      const activityHistory = [];
      if (p.createdAt) {
        activityHistory.push({
          type: 'project_created',
          timestamp: new Date(p.createdAt).toISOString(),
          actor: p.createdBy || 'Company Admin',
          detail: `Project "${p.name}" created (${memberMap.size} members)`,
        });
      }
      for (const t of enrichedTasks) {
        if (t.createdAt) {
          activityHistory.push({
            type: 'task_created',
            timestamp: new Date(t.createdAt).toISOString(),
            actor: t.assignorName,
            detail: `Task "${t.title}" assigned to ${t.employeeName}`,
          });
        }
        for (const pu of t.progressUpdates) {
          activityHistory.push({
            type: 'task_progress',
            timestamp: pu.date || '',
            actor: pu.employeeName || t.employeeName,
            detail: `"${t.title}" ${pu.percentage ?? 0}% — ${pu.updateText || 'Update'}`,
          });
        }
        if (t.completedAt) {
          activityHistory.push({
            type: 'task_completed',
            timestamp: String(t.completedAt),
            actor: t.completionReport?.employeeName || t.employeeName,
            detail: `Task "${t.title}" completed`,
          });
        }
      }
      activityHistory.sort((a, b) => String(a.timestamp || '').localeCompare(String(b.timestamp || '')));

      const deptList = Array.from(
        new Set(Array.from(memberMap.values()).map((m) => m.department).filter(Boolean)),
      ).sort();

      return {
        id: p.id,
        name: p.name,
        description: p.description || '',
        projectManager: p.createdBy || 'Company Admin',
        status: p.status || 'active',
        priority: p.priority || 'medium',
        startDate: p.startDate || normalizeDateOnly(p.createdAt),
        dueDate: p.dueDate || '',
        createdAt: p.createdAt || null,
        updatedAt: p.updatedAt || null,
        isDelayed,
        overdueDays,
        departments: deptList,
        assignedEmployees: Array.from(memberMap.values()).map((m) => ({
          userId: m.userId,
          staffId: m.staffId,
          name: m.name,
          department: m.department,
          designation: m.designation,
          joiningDate: m.joiningDate,
          employeeStatus: m.employeeStatus,
        })),
        taskMetrics: {
          total: totalTasks,
          completed: completedTasks,
          inProgress: inProgressTasks,
          pending: pendingTasks,
          overdue: overdueTasks,
          completionRate,
          averageProgress,
        },
        tasks: enrichedTasks,
        employeeContributions,
        activityHistory,
        _memberMap: memberMap,
      };
    });

  // Apply employee, department, status, and search filters
  if (employeeFilter && employeeFilter !== 'all') {
    projectEntries = projectEntries.filter((p) =>
      Array.from(p._memberMap.values()).some((m) => matchesEmployeeFilter(m, employeeFilter)),
    );
  }
  if (departmentFilter && departmentFilter !== 'all') {
    projectEntries = projectEntries.filter((p) =>
      p.departments.some((d) => d.toLowerCase() === departmentFilter.toLowerCase()),
    );
  }
  if (statusFilter !== 'all') {
    if (statusFilter === 'delayed') {
      projectEntries = projectEntries.filter((p) => p.isDelayed);
    } else {
      projectEntries = projectEntries.filter((p) => (p.status || '').toLowerCase() === statusFilter);
    }
  }
  if (searchQuery) {
    projectEntries = projectEntries.filter((p) =>
      (p.name || '').toLowerCase().includes(searchQuery) ||
      (p.description || '').toLowerCase().includes(searchQuery) ||
      (p.projectManager || '').toLowerCase().includes(searchQuery) ||
      p.departments.some((d) => d.toLowerCase().includes(searchQuery)) ||
      p.assignedEmployees.some((e) => (e.name || '').toLowerCase().includes(searchQuery)) ||
      p.tasks.some((t) => (t.title || '').toLowerCase().includes(searchQuery)),
    );
  }

  const cleanProjects = projectEntries.map(({ _memberMap, ...rest }) => rest);

  const totalProjects = cleanProjects.length;
  const activeProjects = cleanProjects.filter((p) => p.status === 'active').length;
  const completedProjects = cleanProjects.filter((p) => p.status === 'completed').length;
  const planningProjects = cleanProjects.filter((p) => p.status === 'planning').length;
  const onHoldProjects = cleanProjects.filter((p) => p.status === 'on_hold').length;
  const delayedProjects = cleanProjects.filter((p) => p.isDelayed).length;
  const totalProjectTasks = cleanProjects.reduce((sum, p) => sum + p.taskMetrics.total, 0);
  const completedProjectTasks = cleanProjects.reduce((sum, p) => sum + p.taskMetrics.completed, 0);
  const overallCompletionRate = totalProjectTasks > 0
    ? Math.round((completedProjectTasks / totalProjectTasks) * 100)
    : (totalProjects > 0 ? Math.round((completedProjects / totalProjects) * 100) : 0);

  const flatRecords = cleanProjects.map((p) => ({
    id: p.id,
    name: p.name,
    description: p.description,
    projectManager: p.projectManager,
    departments: p.departments.join(', '),
    teamCount: p.assignedEmployees.length,
    startDate: p.startDate,
    dueDate: p.dueDate,
    status: p.status,
    priority: p.priority,
    isDelayed: p.isDelayed,
    overdueDays: p.overdueDays,
    totalTasks: p.taskMetrics.total,
    completedTasks: p.taskMetrics.completed,
    pendingTasks: p.taskMetrics.pending,
    overdueTasks: p.taskMetrics.overdue,
    completionRate: p.taskMetrics.completionRate,
  }));

  const csvHeaders = [
    'Project ID', 'Project Name', 'Project Manager', 'Departments', 'Team Size',
    'Start Date', 'Due Date', 'Status', 'Priority', 'Delayed', 'Overdue Days',
    'Total Tasks', 'Completed Tasks', 'Pending Tasks', 'Completion (%)',
  ];
  const csvRows = flatRecords.map((r) => [
    r.id,
    r.name,
    r.projectManager,
    r.departments || 'General',
    r.teamCount,
    r.startDate,
    r.dueDate,
    r.status,
    r.priority,
    r.isDelayed ? 'Yes' : 'No',
    r.overdueDays,
    r.totalTasks,
    r.completedTasks,
    r.pendingTasks,
    `${r.completionRate}%`,
  ]);

  const csvContent = buildCsvDocument(
    [
      `# ${companyName} - Historical Project Report`,
      `# Period: ${window.periodLabel}`,
      `# Generated: ${new Date().toLocaleString()}`,
      `# Summary: Projects: ${totalProjects} | Active: ${activeProjects} | Completed: ${completedProjects} | Delayed: ${delayedProjects} | Tasks Completed: ${completedProjectTasks}/${totalProjectTasks}`,
    ],
    csvHeaders,
    csvRows,
  );

  const paged = paginateItems(cleanProjects, query);
  const projectOptions = allProjects
    .map((p) => ({ id: p.id, name: p.name, status: p.status }))
    .sort((a, b) => (a.name || '').localeCompare(b.name || ''));

  return {
    companyName,
    period: window.period,
    periodLabel: window.periodLabel,
    startDate: window.startDate,
    endDate: window.endDate,
    totalProjects,
    activeProjects,
    completedProjects,
    planningProjects,
    onHoldProjects,
    delayedProjects,
    totalProjectTasks,
    completedProjectTasks,
    overallCompletionRate,
    projects: paged.items,
    records: flatRecords,
    pagination: paged.pagination,
    projectOptions,
    employees: userLookup.employeeOptions,
    departments: userLookup.departments,
    csvContent,
  };
};

/**
 * Controller: Get Historical Project Report (JSON + CSV)
 */
export const getProjectReport = async (req, res) => {
  try {
    if (!assertCompanyReportAccess(req, res)) return;
    const report = await buildProjectReportData(req.companyId, req.query);
    res.status(200).json(report);
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
};

/**
 * Controller: Send Project Report via Email
 */
export const sendProjectReport = async (req, res) => {
  try {
    if (!assertCompanyReportAccess(req, res)) return;
    const { recipientEmail, notes, ...filterParams } = req.body;
    if (!recipientEmail || !recipientEmail.trim()) {
      return res.status(400).json({ message: 'Recipient email is required' });
    }
    const report = await buildProjectReportData(req.companyId, { ...filterParams, limit: 'all' });
    const summaryMetrics = [
      { label: 'Total Projects', value: `${report.totalProjects}` },
      { label: 'Active Projects', value: `${report.activeProjects}` },
      { label: 'Completed Projects', value: `${report.completedProjects}` },
      { label: 'Delayed Projects', value: `${report.delayedProjects}` },
      { label: 'Project Tasks Completed', value: `${report.completedProjectTasks} / ${report.totalProjectTasks}` },
      { label: 'Overall Progress', value: `${report.overallCompletionRate}%` },
    ];
    const filename = `Project_Report_${report.companyName.replace(/[^a-zA-Z0-9]/g, '_')}_${report.periodLabel.replace(/[^a-zA-Z0-9]/g, '_')}.csv`;
    const mailResult = await sendReportEmail({
      to: recipientEmail.trim(),
      subject: `Project Report - ${report.companyName} (${report.periodLabel})`,
      companyName: report.companyName,
      reportType: 'Historical Project Report',
      periodLabel: report.periodLabel,
      summaryMetrics,
      notes: notes ? String(notes).trim() : '',
      csvContent: report.csvContent,
      filename,
    });
    res.status(200).json({
      message: mailResult.simulated
        ? `Project report prepared for ${recipientEmail} (Simulated send: SMTP not configured)`
        : `Project report successfully sent to ${recipientEmail}`,
      mailResult,
    });
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
};
