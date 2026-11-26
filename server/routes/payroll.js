import express from 'express';
import {
  getPayrollSettings,
  updatePayrollSettings,
  getPayrollSummary,
  getEmployeePayrollPreview,
  finalizePayroll,
  finalizeMonthPayroll,
  processPayment,
  processBulkPayment,
  getPendingPayrolls,
  getRecentTransactions,
  getEmployeeMyPayroll,
  getEmployeePayslip,
  addPayrollAdjustment,
  getPayrollAdjustments,
  deletePayrollAdjustment,
  getPayrollReport,
  sendPayrollReport,
} from '../controllers/payrollController.js';

const router = express.Router();

// Company Payroll Report endpoints
router.get('/report', getPayrollReport);
router.post('/send-report', sendPayrollReport);

// Company Payroll Configuration
router.get('/settings', getPayrollSettings);
router.put('/settings', updatePayrollSettings);

// Company Payroll Management
router.get('/summary', getPayrollSummary);
router.get('/preview', getEmployeePayrollPreview);
router.get('/pending', getPendingPayrolls);
router.post('/finalize', finalizePayroll);
router.post('/finalize-month', finalizeMonthPayroll);
router.post('/pay', processPayment);
router.post('/pay-bulk', processBulkPayment);
router.get('/transactions', getRecentTransactions);

// Payslip Generation & Download
router.get('/payslip', getEmployeePayslip);
router.get('/:id/payslip', getEmployeePayslip);

// Bonus & Deduction Adjustments
router.post('/adjustment', addPayrollAdjustment);
router.get('/adjustments', getPayrollAdjustments);
router.delete('/adjustment/:id', deletePayrollAdjustment);

// Employee-Side Records (strictly scoped to caller)
router.get('/my-records', getEmployeeMyPayroll);

export default router;
