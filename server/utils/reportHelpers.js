import User from '../models/User.js';

const WEEKDAY_NAMES = [
  'Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday',
];

export const pad2 = (n) => String(n).padStart(2, '0');

export const getTodayDateStr = () => {
  const now = new Date();
  return `${now.getFullYear()}-${pad2(now.getMonth() + 1)}-${pad2(now.getDate())}`;
};

export const getCurrentMonthStr = () => {
  const now = new Date();
  return `${now.getFullYear()}-${pad2(now.getMonth() + 1)}`;
};

/**
 * Enforces strict tenant isolation and Company Admin role authorization
 * for company-wide historical report endpoints.
 */
export const assertCompanyReportAccess = (req, res) => {
  if (!req.companyId) {
    res.status(400).json({ message: 'Company context required' });
    return false;
  }
  const rawRole = req.user?.role;
  const role = typeof rawRole === 'object'
    ? Object.keys(rawRole)[0]
    : String(rawRole || '').toLowerCase().trim();
  if (!['owner', 'admin', 'param'].includes(role)) {
    res.status(403).json({ message: 'Company Administrator access required for company reports' });
    return false;
  }
  return true;
};

/**
 * Resolves a report date window supporting:
 * all | range | day | week | month | year
 */
export const resolveReportWindow = (query = {}, earliestDate = null) => {
  const now = new Date();
  const todayStr = getTodayDateStr();
  const rawPeriod = String(query.period || 'month').toLowerCase().trim();

  if (rawPeriod === 'all') {
    const start = earliestDate || null;
    return {
      period: 'all',
      periodLabel: start ? `All History (${start} to ${todayStr})` : 'All History',
      startDate: start,
      endDate: todayStr,
      monthPrefix: null,
      yearPrefix: null,
    };
  }

  if (rawPeriod === 'range') {
    const start = /^\d{4}-\d{2}-\d{2}$/.test(String(query.startDate || '').trim())
      ? String(query.startDate).trim()
      : (earliestDate || null);
    const end = /^\d{4}-\d{2}-\d{2}$/.test(String(query.endDate || '').trim())
      ? String(query.endDate).trim()
      : todayStr;
    return {
      period: 'range',
      periodLabel: start ? `${start} to ${end}` : `Up to ${end}`,
      startDate: start,
      endDate: end,
      monthPrefix: null,
      yearPrefix: null,
    };
  }

  if (rawPeriod === 'day') {
    const targetDate = /^\d{4}-\d{2}-\d{2}$/.test(String(query.date || '').trim())
      ? String(query.date).trim()
      : todayStr;
    return {
      period: 'day',
      periodLabel: `Day (${targetDate})`,
      startDate: targetDate,
      endDate: targetDate,
      monthPrefix: null,
      yearPrefix: null,
    };
  }

  if (rawPeriod === 'week') {
    let start = /^\d{4}-\d{2}-\d{2}$/.test(String(query.startDate || '').trim())
      ? String(query.startDate).trim()
      : null;
    let end = /^\d{4}-\d{2}-\d{2}$/.test(String(query.endDate || '').trim())
      ? String(query.endDate).trim()
      : null;
    if (!start || !end) {
      const anchor = /^\d{4}-\d{2}-\d{2}$/.test(String(query.date || '').trim())
        ? new Date(`${String(query.date).trim()}T00:00:00`)
        : new Date(now);
      const day = anchor.getDay();
      const diffToMon = anchor.getDate() - day + (day === 0 ? -6 : 1);
      const mon = new Date(anchor);
      mon.setDate(diffToMon);
      const sun = new Date(mon);
      sun.setDate(mon.getDate() + 6);
      start = `${mon.getFullYear()}-${pad2(mon.getMonth() + 1)}-${pad2(mon.getDate())}`;
      end = `${sun.getFullYear()}-${pad2(sun.getMonth() + 1)}-${pad2(sun.getDate())}`;
    }
    return {
      period: 'week',
      periodLabel: `Week (${start} to ${end})`,
      startDate: start,
      endDate: end,
      monthPrefix: null,
      yearPrefix: null,
    };
  }

  if (rawPeriod === 'year') {
    const targetYear = /^\d{4}$/.test(String(query.year || '').trim())
      ? String(query.year).trim()
      : String(now.getFullYear());
    return {
      period: 'year',
      periodLabel: `Year (${targetYear})`,
      startDate: `${targetYear}-01-01`,
      endDate: `${targetYear}-12-31`,
      monthPrefix: null,
      yearPrefix: targetYear,
    };
  }

  // Default: 'month'
  const targetMonth = /^\d{4}-\d{2}$/.test(String(query.month || '').trim())
    ? String(query.month).trim()
    : getCurrentMonthStr();
  const [yStr, mStr] = targetMonth.split('-');
  const y = Number(yStr);
  const m = Number(mStr);
  const lastDay = new Date(y, m, 0).getDate();
  return {
    period: 'month',
    periodLabel: `Month (${targetMonth})`,
    startDate: `${targetMonth}-01`,
    endDate: `${targetMonth}-${pad2(lastDay)}`,
    monthPrefix: targetMonth,
    yearPrefix: yStr,
  };
};

/**
 * Checks whether a YYYY-MM-DD date falls inside the resolved window.
 */
export const isDateInWindow = (dateStr, window) => {
  if (!dateStr) return window.period === 'all';
  const normalized = String(dateStr).slice(0, 10);
  if (window.startDate && normalized < window.startDate) return false;
  if (window.endDate && normalized > window.endDate) return false;
  return true;
};

/**
 * Extracts weekday, YYYY-MM month, and YYYY year from an ISO date string.
 */
export const parseDateBreakdown = (dateStr) => {
  const s = String(dateStr || '').slice(0, 10);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(s)) {
    return { date: s, weekday: '', month: '', year: '' };
  }
  const d = new Date(`${s}T00:00:00`);
  const weekday = !isNaN(d.getTime()) ? WEEKDAY_NAMES[d.getDay()] : '';
  return {
    date: s,
    weekday,
    month: s.slice(0, 7),
    year: s.slice(0, 4),
  };
};

/**
 * Normalizes employee joining date into YYYY-MM-DD when valid.
 */
export const normalizeDateOnly = (rawDate) => {
  if (!rawDate) return '';
  if (rawDate instanceof Date && !isNaN(rawDate.getTime())) {
    return rawDate.toISOString().slice(0, 10);
  }
  const s = String(rawDate).trim();
  if (/^\d{4}-\d{2}-\d{2}/.test(s)) return s.slice(0, 10);
  const parsed = new Date(s);
  if (!isNaN(parsed.getTime())) {
    return parsed.toISOString().slice(0, 10);
  }
  return '';
};

/**
 * Builds complete company user lookup (including inactive/former employees)
 * so historical records are never lost when someone leaves the company.
 */
export const buildCompanyUserLookup = async (companyId) => {
  const users = await User.find({ companyId })
    .select('userId StaffId name username email phone department designation role status salary joiningDate createdAt updatedAt')
    .lean();

  const exactMap = new Map();
  const lowerMap = new Map();
  const staffUsers = [];

  for (const u of users) {
    const keys = [
      u.userId,
      u.StaffId,
      String(u._id),
      u.username,
      u.name,
    ].filter(Boolean);

    for (const k of keys) {
      const s = String(k).trim();
      if (!exactMap.has(s)) exactMap.set(s, u);
      const low = s.toLowerCase();
      if (!lowerMap.has(low)) lowerMap.set(low, u);
    }

    if (['staff', 'employee', 'intern', 'freelancer', 'admin'].includes(String(u.role || '').toLowerCase())) {
      staffUsers.push(u);
    }
  }

  const resolveUser = (identifier, fallbackName = '') => {
    const key = identifier ? String(identifier).trim() : '';
    const found = (key && (exactMap.get(key) || lowerMap.get(key.toLowerCase()))) ||
      (fallbackName && lowerMap.get(String(fallbackName).trim().toLowerCase())) ||
      null;

    if (found) {
      return {
        user: found,
        userId: found.userId || String(found._id),
        staffId: found.StaffId || found.userId || String(found._id),
        name: found.name || found.username || found.userId || fallbackName || 'Employee',
        department: found.department || 'General',
        designation: found.designation || 'Staff',
        joiningDate: normalizeDateOnly(found.joiningDate || found.createdAt),
        employeeStatus: found.status || 'active',
        role: found.role || 'staff',
        salary: Number(found.salary) || 0,
      };
    }

    return {
      user: null,
      userId: key || fallbackName || 'former_employee',
      staffId: key || '--',
      name: fallbackName || key || 'Former Employee',
      department: 'General',
      designation: 'Former Staff',
      joiningDate: '',
      employeeStatus: 'former',
      role: 'staff',
      salary: 0,
    };
  };

  const employeeOptions = staffUsers
    .map((u) => ({
      userId: u.userId || String(u._id),
      staffId: u.StaffId || u.userId || String(u._id),
      name: u.name || u.username || u.userId,
      department: u.department || 'General',
      designation: u.designation || 'Staff',
      joiningDate: normalizeDateOnly(u.joiningDate || u.createdAt),
      status: u.status || 'active',
    }))
    .sort((a, b) => (a.name || '').localeCompare(b.name || ''));

  const departmentSet = new Set(employeeOptions.map((e) => e.department).filter(Boolean));
  const departments = Array.from(departmentSet).sort((a, b) => a.localeCompare(b));

  return {
    allUsers: users,
    staffUsers,
    resolveUser,
    employeeOptions,
    departments,
  };
};

export const matchesEmployeeFilter = (resolvedMeta, queryEmployeeId) => {
  if (!queryEmployeeId || queryEmployeeId === 'all') return true;
  const target = String(queryEmployeeId).trim().toLowerCase();
  const candidates = [
    resolvedMeta.userId,
    resolvedMeta.staffId,
    resolvedMeta.user?._id ? String(resolvedMeta.user._id) : null,
    resolvedMeta.user?.username,
  ].filter(Boolean);
  return candidates.some((c) => String(c).trim().toLowerCase() === target);
};

/**
 * Slices items cleanly when `limit` is provided (preserves full list when omitted or `limit=all`).
 */
export const paginateItems = (items, query = {}) => {
  const total = items.length;
  const rawLimit = String(query.limit || '').trim().toLowerCase();
  if (!rawLimit || rawLimit === 'all') {
    return {
      items,
      pagination: {
        page: 1,
        limit: total || 1,
        total,
        totalPages: 1,
        hasMore: false,
      },
    };
  }

  const limit = Math.max(1, Math.min(500, parseInt(rawLimit, 10) || 25));
  const totalPages = Math.max(1, Math.ceil(total / limit));
  const page = Math.max(1, Math.min(totalPages, parseInt(String(query.page || '1'), 10) || 1));
  const start = (page - 1) * limit;
  const sliced = items.slice(start, start + limit);

  return {
    items: sliced,
    pagination: {
      page,
      limit,
      total,
      totalPages,
      hasMore: page < totalPages,
    },
  };
};

export const escapeCsvCell = (value) => {
  const str = value === null || value === undefined ? '' : String(value);
  return `"${str.replace(/"/g, '""')}"`;
};

export const buildCsvDocument = (commentLines, headers, rows) => {
  return [
    ...commentLines,
    '',
    headers.map(escapeCsvCell).join(','),
    ...rows.map((row) => row.map(escapeCsvCell).join(',')),
  ].join('\n');
};
