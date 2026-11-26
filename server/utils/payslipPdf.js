/**
 * Zero-dependency Pure Node.js PDF Payslip Generator (PDF 1.4)
 * Produces a clean, printable A4 payslip buffer for download endpoints.
 */

const sanitizeAscii = (val) => String(val ?? '')
  .replace(/₹/g, 'INR ')
  .replace(/[^\x20-\x7E]/g, ' ')
  .replace(/\\/g, '\\\\')
  .replace(/\(/g, '\\(')
  .replace(/\)/g, '\\)');

const formatMoney = (val) => {
  const num = Number(val) || 0;
  return `INR ${num.toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
};

export function generatePayslipPdfBuffer(payslip) {
  const lines = [];
  const addLine = (text, size = 10, bold = false, gap = 14) => {
    lines.push({ text: sanitizeAscii(text), size, bold, gap });
  };

  addLine(`${payslip.companyName || 'ReGen Workspace'} - OFFICIAL PAYSLIP`, 14, true, 20);
  addLine(`Payslip No: ${payslip.payslipNumber || '-'}   |   Pay Period: ${payslip.month || '-'}`, 9, false, 14);
  addLine(`Generated At: ${new Date(payslip.generatedAt || Date.now()).toISOString().slice(0, 10)}   |   Status: ${String(payslip.paymentStatus || 'unpaid').toUpperCase()}`, 9, false, 18);

  addLine('--------------------------------------------------------------------------', 9, false, 12);
  addLine(`Employee: ${payslip.employee?.name || '-'} (${payslip.employee?.staffId || payslip.employee?.userId || '-'})`, 10, true, 14);
  addLine(`Department: ${payslip.employee?.department || '-'}   |   Designation: ${payslip.employee?.designation || '-'}`, 9, false, 16);

  addLine('--------------------------------------------------------------------------', 9, false, 12);
  addLine('ATTENDANCE & LEAVE SUMMARY', 10, true, 14);
  const att = payslip.attendanceSummary || {};
  addLine(`Present Days: ${att.presentDays || 0} / ${att.scheduledWorkingDays || 0}   |   Actual Hours: ${att.actualWorkingHours || 0}h / ${att.scheduledWorkingHours || 0}h`, 9, false, 13);
  addLine(`Approved Leaves: ${att.approvedLeaveDays || 0}d   |   Unapproved Leaves: ${att.unapprovedLeaveDays || 0}d   |   Holidays: ${att.holidayDays || 0}d`, 9, false, 13);
  addLine(`Overtime Hours: ${att.overtimeHours || 0}h   |   Shortfall Hours: ${att.shortfallHours || 0}h   |   Break Delay: ${att.totalBreakDelayMinutes || 0}m`, 9, false, 16);

  addLine('--------------------------------------------------------------------------', 9, false, 12);
  addLine('EARNINGS & DEDUCTIONS', 10, true, 14);
  const e = payslip.earnings || {};
  const d = payslip.deductions || {};
  addLine(`Base Monthly Salary:                 ${formatMoney(e.baseSalary)}`, 9.5, false, 13);
  addLine(`Overtime Earnings:                 + ${formatMoney(e.overtimeAddition)}`, 9.5, false, 13);
  addLine(`Bonuses:                           + ${formatMoney(e.bonus)}`, 9.5, false, 13);
  addLine(`Shortfall Deduction:               - ${formatMoney(d.shortfallDeduction)}`, 9.5, false, 13);
  addLine(`Late Arrival Deduction:            - ${formatMoney(d.lateDeduction)}`, 9.5, false, 13);
  addLine(`Break Delay Deduction:             - ${formatMoney(d.breakDeduction)}`, 9.5, false, 13);
  addLine(`Approved Leave Deduction:          - ${formatMoney(d.approvedLeaveDeduction)}`, 9.5, false, 13);
  addLine(`Unapproved Leave Deduction:        - ${formatMoney(d.unapprovedLeaveDeduction)}`, 9.5, false, 13);
  addLine(`Manual Deductions:                 - ${formatMoney(d.manualDeduction)}`, 9.5, false, 15);

  addLine('--------------------------------------------------------------------------', 9, false, 12);
  const p = payslip.paymentSummary || {};
  addLine(`NET PAYABLE SALARY:                  ${formatMoney(p.netPayable)}`, 10.5, true, 15);
  addLine(`TOTAL AMOUNT PAID:                   ${formatMoney(p.amountPaid)}`, 10, false, 14);
  addLine(`REMAINING PENDING BALANCE:           ${formatMoney(p.pendingAmount)}`, 10.5, true, 18);

  if (Array.isArray(payslip.adjustments) && payslip.adjustments.length > 0) {
    addLine('ADJUSTMENTS (BONUSES / MANUAL DEDUCTIONS)', 10, true, 14);
    for (const adj of payslip.adjustments.slice(0, 8)) {
      const sign = adj.type === 'bonus' ? '+' : '-';
      addLine(`- ${String(adj.type || '').toUpperCase()}: ${sign}${formatMoney(adj.amount)} (${adj.reason || 'Adjustment'})`, 8.5, false, 12);
    }
    addLine('', 9, false, 6);
  }

  if (Array.isArray(payslip.transactions) && payslip.transactions.length > 0) {
    addLine('PAYMENT TRANSACTIONS', 10, true, 14);
    for (const tx of payslip.transactions.slice(0, 10)) {
      const dt = tx.paidAt ? new Date(tx.paidAt).toISOString().slice(0, 10) : '-';
      addLine(`- ${dt} | ${String(tx.paymentMethod || 'bank').toUpperCase()} | Ref: ${tx.referenceId || '-'} | ${formatMoney(tx.amount)}`, 8.5, false, 12);
    }
    addLine('', 9, false, 6);
  }

  if (Array.isArray(payslip.dailyBreakdown) && payslip.dailyBreakdown.length > 0) {
    addLine('DAILY ATTENDANCE & PAYROLL LOG (HIGHLIGHTS)', 10, true, 14);
    const nonTrivial = payslip.dailyBreakdown.filter(day =>
      day.explanation && !day.isFuture && (!day.isWeeklyOff || (day.dailyAdjustments && day.dailyAdjustments.length > 0))
    );
    for (const day of nonTrivial.slice(0, 22)) {
      addLine(day.explanation.slice(0, 96), 8, false, 11);
    }
  }

  // Build PDF page stream
  const ops = ['BT'];
  let y = 805;
  let currentFont = '';
  for (const line of lines) {
    if (y < 42) break;
    const fontName = line.bold ? '/F2' : '/F1';
    if (fontName !== currentFont || true) {
      ops.push(`${fontName} ${line.size} Tf`);
      currentFont = fontName;
    }
    ops.push(`1 0 0 1 40 ${y} Tm`);
    ops.push(`(${line.text}) Tj`);
    y -= line.gap;
  }
  ops.push('ET');
  const streamContent = ops.join('\n');

  const objects = [
    '1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n',
    '2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n',
    '3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Contents 4 0 R /Resources << /Font << /F1 5 0 R /F2 6 0 R >> >> >>\nendobj\n',
    `4 0 obj\n<< /Length ${Buffer.byteLength(streamContent, 'utf8')} >>\nstream\n${streamContent}\nendstream\nendobj\n`,
    '5 0 obj\n<< /Type /Font /Subtype /Type1 /BaseFont /Courier >>\nendobj\n',
    '6 0 obj\n<< /Type /Font /Subtype /Type1 /BaseFont /Courier-Bold >>\nendobj\n',
  ];

  let pdf = '%PDF-1.4\n';
  const offsets = [0];
  for (const obj of objects) {
    offsets.push(Buffer.byteLength(pdf, 'utf8'));
    pdf += obj;
  }
  const xrefPos = Buffer.byteLength(pdf, 'utf8');
  pdf += `xref\n0 ${objects.length + 1}\n`;
  pdf += '0000000000 65535 f \n';
  for (let i = 1; i <= objects.length; i++) {
    pdf += `${String(offsets[i]).padStart(10, '0')} 00000 n \n`;
  }
  pdf += `trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n${xrefPos}\n%%EOF\n`;
  return Buffer.from(pdf, 'utf8');
}
