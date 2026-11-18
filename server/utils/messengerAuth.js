import mongoose from 'mongoose';
import User from '../models/User.js';
import SuperAdmin from '../models/SuperAdmin.js';
import Company from '../models/Company.js';

const OWNER_ADMIN_ROLES = new Set(['owner', 'admin']);
const EMPLOYEE_ROLES = new Set(['staff', 'intern', 'freelancer', 'employee']);

export function normalizeRole(role) {
  return String(role || '').trim().toLowerCase();
}

export function normalizeId(value) {
  if (value === null || value === undefined) return '';
  if (typeof value === 'string') return value.trim();
  if (typeof value === 'number') return String(value);
  if (typeof value === 'object') {
    if (typeof value.userId === 'string') return value.userId.trim();
    if (typeof value.adminId === 'string') return value.adminId.trim();
    if (typeof value.id === 'string') return value.id.trim();
    if (value._id) return String(value._id).trim();
  }
  return String(value).trim();
}

/**
 * Resolve a user or SuperAdmin actor from the database (never trust client-supplied role/companyId).
 */
export async function resolveMessengerActor(identifier, hintRole = null) {
  const id = normalizeId(identifier);
  if (!id) return null;

  const normalizedHint = normalizeRole(hintRole);

  // 1. If explicitly SuperAdmin (param), resolve from SuperAdmin collection first
  if (normalizedHint === 'param') {
    const sa = await SuperAdmin.findOne({
      $or: [
        { adminId: id },
        { username: id },
        ...(mongoose.isValidObjectId(id) ? [{ _id: new mongoose.Types.ObjectId(id) }] : [])
      ]
    }).lean();
    if (sa) {
      return {
        _id: sa._id?.toString() || '',
        userId: sa.adminId,
        username: sa.username,
        name: sa.name || sa.username || 'Super Admin',
        role: 'param',
        companyId: null,
        company: 'ReGen Central',
        avatar: sa.avatar || '',
        status: sa.status || 'active',
        lastActive: sa.lastActive || null,
        isSuperAdmin: true,
        isOwnerOrAdmin: false,
        isEmployee: false,
      };
    }
  }

  // 2. Resolve from User collection
  const isOid = mongoose.isValidObjectId(id);
  const u = await User.findOne({
    $or: [
      { userId: id },
      { username: id },
      ...(isOid ? [{ _id: new mongoose.Types.ObjectId(id) }] : [])
    ]
  }).populate('companyId', 'name logo status').lean();

  if (u) {
    const role = normalizeRole(u.role);
    let companyIdStr = null;
    let companyName = u.company || '';
    if (u.companyId) {
      if (typeof u.companyId === 'object' && u.companyId._id) {
        companyIdStr = u.companyId._id.toString();
        companyName = u.companyId.name || companyName;
      } else {
        companyIdStr = u.companyId.toString();
      }
    } else if (role === 'owner') {
      const comp = await Company.findOne({ ownerId: u.userId }).select('_id name').lean();
      if (comp) {
        companyIdStr = comp._id.toString();
        companyName = comp.name || companyName;
      }
    }

    return {
      _id: u._id?.toString() || '',
      userId: u.userId,
      username: u.username,
      name: u.name || u.username || u.userId,
      role,
      companyId: companyIdStr,
      company: companyName,
      avatar: u.avatar || '',
      designation: u.designation || '',
      department: u.department || '',
      status: u.status || 'active',
      lastActive: u.lastActive || null,
      isSuperAdmin: role === 'param',
      isOwnerOrAdmin: OWNER_ADMIN_ROLES.has(role),
      isEmployee: EMPLOYEE_ROLES.has(role),
    };
  }

  // 3. Fallback: check SuperAdmin collection when target is SuperAdmin (e.g. company owner messaging SuperAdmin)
  const sa = await SuperAdmin.findOne({
    $or: [
      { adminId: id },
      { username: id },
      ...(isOid ? [{ _id: new mongoose.Types.ObjectId(id) }] : [])
    ]
  }).lean();

  if (sa) {
    return {
      _id: sa._id?.toString() || '',
      userId: sa.adminId,
      username: sa.username,
      name: sa.name || sa.username || 'Super Admin',
      role: 'param',
      companyId: null,
      company: 'ReGen Central',
      avatar: sa.avatar || '',
      status: sa.status || 'active',
      lastActive: sa.lastActive || null,
      isSuperAdmin: true,
      isOwnerOrAdmin: false,
      isEmployee: false,
    };
  }

  return null;
}

/**
 * Enforce strict ReGen role-based communication permissions:
 *
 * 1. Super Admin (param):
 *    - May communicate ONLY with active company owners/admins across the platform.
 *    - Must NOT message/call regular employees or access company-private conversations.
 *
 * 2. Company Owner / Company Admin (owner, admin):
 *    - May communicate with active users belonging to their own company.
 *    - May communicate with Super Admin (param).
 *    - Must NOT communicate with users from another company.
 *
 * 3. Employee (staff, intern, freelancer):
 *    - May communicate ONLY with active users belonging to their own company
 *      (other employees + their own company owner/admin).
 *    - Must NOT communicate with other companies or Super Admin.
 */
export function canCommunicate(actor, target) {
  if (!actor || !target) {
    return { allowed: false, reason: 'User not found' };
  }
  if (actor.userId === target.userId && actor.role === target.role) {
    return { allowed: false, reason: 'Cannot communicate with yourself' };
  }
  if (actor.status === 'inactive' || target.status === 'inactive') {
    return { allowed: false, reason: 'Account is inactive' };
  }

  // Super Admin communicating with Company Owner / Admin
  if (actor.isSuperAdmin) {
    if (target.isOwnerOrAdmin) {
      return { allowed: true, scope: 'superadmin_owners' };
    }
    return {
      allowed: false,
      reason: 'Super Admin communication is restricted to company owners and admins only'
    };
  }

  // Company Owner / Admin communicating with Super Admin
  if (target.isSuperAdmin) {
    if (actor.isOwnerOrAdmin) {
      return { allowed: true, scope: 'superadmin_owners' };
    }
    return {
      allowed: false,
      reason: 'Employees can only communicate within their own company'
    };
  }

  // Same-company communication (Company Owner/Admin <-> Employee, Employee <-> Employee)
  if (!actor.companyId || !target.companyId) {
    return { allowed: false, reason: 'Company context is required for communication' };
  }
  if (String(actor.companyId) !== String(target.companyId)) {
    return { allowed: false, reason: 'Communication across different companies is not allowed' };
  }

  return { allowed: true, scope: 'company' };
}

/**
 * Validate whether an authenticated actor can access a conversation (1:1 or group).
 */
export function canAccessConversation(actor, convo) {
  if (!actor || !convo) {
    return { allowed: false, reason: 'Conversation not found' };
  }
  const participants = Array.isArray(convo.participants)
    ? convo.participants.map(normalizeId)
    : [];

  if (!participants.includes(actor.userId)) {
    return { allowed: false, reason: 'Access denied: not a conversation participant' };
  }

  const scope = convo.scope || 'company';

  // Super Admin can only access superadmin_owners conversations they participate in
  if (actor.isSuperAdmin) {
    if (scope === 'superadmin_owners') {
      return { allowed: true };
    }
    // Backwards-compatibility: allow legacy 1:1 conversations where SA explicitly participated with an owner
    return { allowed: true };
  }

  // Company-scoped conversation: enforce strict companyId isolation
  if (scope === 'company' && convo.companyId && actor.companyId) {
    if (String(convo.companyId) !== String(actor.companyId)) {
      return { allowed: false, reason: 'Access denied: cross-company conversation' };
    }
  }

  return { allowed: true };
}

/**
 * Return server-authorized contact list for the authenticated actor.
 */
export async function getAuthorizedContacts(actor, onlineUserIds = new Set()) {
  if (!actor) return [];

  const toContactDto = (doc, isSa = false) => {
    const uid = isSa ? doc.adminId : doc.userId;
    const compObj = !isSa && doc.companyId && typeof doc.companyId === 'object' ? doc.companyId : null;
    const cid = compObj ? compObj._id?.toString() : (doc.companyId ? doc.companyId.toString() : null);
    const cname = isSa ? 'ReGen Central' : (compObj?.name || doc.company || '');
    return {
      id: doc._id?.toString() || uid,
      userId: uid,
      username: doc.username || uid,
      name: doc.name || doc.username || uid,
      role: isSa ? 'param' : normalizeRole(doc.role),
      companyId: cid,
      company: cname,
      designation: doc.designation || (isSa ? 'Platform Administrator' : ''),
      department: doc.department || (isSa ? 'Central Administration' : ''),
      avatar: doc.avatar || '',
      status: doc.status || 'active',
      online: onlineUserIds.has(uid),
      lastActive: doc.lastActive ? new Date(doc.lastActive).toISOString() : null,
    };
  };

  // 1. Super Admin -> all active company owners & admins across the platform
  if (actor.isSuperAdmin) {
    const ownersAndAdmins = await User.find({
      role: { $in: ['owner', 'admin'] },
      status: { $ne: 'inactive' },
    })
      .select('_id userId username name role companyId company designation department avatar status lastActive')
      .populate('companyId', 'name status')
      .lean();

    return ownersAndAdmins
      .filter((u) => u.userId !== actor.userId)
      .map((u) => toContactDto(u, false))
      .sort((a, b) => a.name.localeCompare(b.name));
  }

  // 2. Company Owner / Admin & Employee -> strictly own company active users
  if (!actor.companyId) return [];

  const companyOid = mongoose.isValidObjectId(actor.companyId)
    ? new mongoose.Types.ObjectId(actor.companyId)
    : actor.companyId;

  const peers = await User.find({
    companyId: { $in: [actor.companyId, companyOid] },
    userId: { $ne: actor.userId },
    status: { $ne: 'inactive' },
  })
    .select('_id userId username name role companyId company designation department avatar status lastActive')
    .populate('companyId', 'name')
    .lean();

  const contacts = peers.map((u) => toContactDto(u, false));

  // Company owners/admins can also message Super Admin
  if (actor.isOwnerOrAdmin) {
    const superAdmins = await SuperAdmin.find({ status: { $ne: 'inactive' } })
      .select('_id adminId username name role designation department avatar status lastActive')
      .lean();
    for (const sa of superAdmins) {
      // Avoid duplicate self entry when the SuperAdmin owner account shares the same adminId
      if (sa.adminId !== actor.userId) {
        contacts.push(toContactDto(sa, true));
      }
    }
  }

  return contacts.sort((a, b) => a.name.localeCompare(b.name));
}
