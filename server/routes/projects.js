import express from 'express';
import {
  getProjects,
  createProject,
  updateProject,
  deleteProject,
  createProjectTask,
  getProjectReport,
  sendProjectReport,
} from '../controllers/projectController.js';

const router = express.Router();

// Historical Project Report endpoints (must be before /:id)
router.get('/report', getProjectReport);
router.post('/send-report', sendProjectReport);

router.get('/', getProjects);
router.post('/', createProject);
router.put('/:id', updateProject);
router.delete('/:id', deleteProject);
router.post('/:id/tasks', createProjectTask);

export default router;
