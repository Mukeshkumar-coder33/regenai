# ReGen Mobile API Mapping

This document tracks all backend REST endpoints and data contracts verified from `reGen/server/` source code and integrated into the Flutter mobile application.

| Feature | Method | Endpoint | Auth | Request Payload / Headers | Response Summary | Status |
|---|---|---|---|---|---|---|
| **Health Check** | GET | `/api/health` | None | None | `{ status: "ok", mongo: true }` | Verified |
| **User Login** | POST | `/api/auth/login` | None | `{ identifier, password, portal: 'company' }` | `{ _id, userId, username, name, role, companyId, company, avatar, token, authSource }` | Implemented & Verified |
| **Switch to SuperAdmin** | POST | `/api/auth/switch-to-superadmin` | Bearer JWT | None (authorized for `param` or username `vyshwa`) | `{ _id, userId, role: 'param', company: 'ReGen Central', token }` | Implemented & Verified |
| **Switch to EMS Mode** | POST | `/api/auth/switch-to-ems` | Bearer JWT (`param`) | None | `{ _id, userId, role: 'owner', company: 'krish Tech Computer', token }` | Implemented & Verified |
| **Current User Profile** | GET | `/api/users/me` or `/api/users/profile` | Bearer JWT | None | User model JSON | Implemented & Verified |
| **Company Details (Normal)** | GET | `/api/company` | Bearer JWT | None | Array containing caller's company (`CompanyModel`) | Implemented & Verified |
| **All Platform Companies** | GET | `/api/company` | Bearer JWT (`param`) | Header `x-portal-view: superadmin` | Array of all 7 platform companies | Implemented & Verified |
| **Company Users (Roster)** | GET | `/api/users` | Bearer JWT | None | Array of caller's company members | Implemented & Verified |
| **Global Platform Users** | GET | `/api/users` | Bearer JWT (`param`) | Header `x-portal-view: superadmin` | Array of all 17 platform users | Implemented & Verified |
| **Company & User Tasks** | GET | `/api/tasks` | Bearer JWT | None | Array of `TaskModel` documents | Implemented & Verified |
| **Attendance Records** | GET | `/api/attendance` | Bearer JWT | None | Array of `AttendanceModel` logs | Implemented & Verified |
| **Leave Requests** | GET | `/api/leaves` | Bearer JWT | None | Array of `LeaveModel` requests | Implemented & Verified |
| **Attendance Status** | GET | `/api/attendance/today` | Bearer JWT | None | Today's clock-in/out record | Milestone 3 |
| **Clock In** | POST | `/api/attendance/clock-in` | Bearer JWT | `{ latitude, longitude }` | Attendance record + geofence verification | Milestone 3 |
| **Clock Out** | POST | `/api/attendance/clock-out` | Bearer JWT | `{ latitude, longitude }` | Attendance record updated | Milestone 3 |
| **Company Geofence** | GET | `/api/company/:id/geofence` | Bearer JWT | None | `{ officeLat, officeLng, radiusMeters }` | Milestone 3 |

---

## Dual Authentication & Synchronization Architecture
1. **Port 5006 (`server/index.js`):** The primary Node.js/Express API gateway.
2. **Port 3004 PostgreSQL Auth Service:** Dual-authenticates employee credentials across PostgreSQL and MongoDB. When reachable, authentications return with `authSource: "dual:synchronized"`.
3. **Role Context Switching:**
   - When Super Admin logs in via normal login (`portal: 'company'`), they start in **Situation C** (`krish Tech Computer`, `role: 'owner'`).
   - When they tap **"Switch to Super Admin Console"**, `POST /api/auth/switch-to-superadmin` mints a new session token with `role: 'param'`.
   - In **Situation D**, adding `x-portal-view: 'superadmin'` grants access to global cluster tables (all 7 companies and all 17 platform users).
   - Tapping **"Switch to Company Workspace"** (`POST /api/auth/switch-to-ems`) smoothly mints a company owner token and returns them to `krish Tech Computer`.
