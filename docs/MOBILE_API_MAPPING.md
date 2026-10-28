# ReGen Mobile API Mapping

This document tracks all backend REST endpoints and Socket.IO events verified from `reGen/server/` source code.

| Feature | Method | Endpoint | Auth | Request Payload | Response Summary | Status |
|---|---|---|---|---|---|---|
| **Health Check** | GET | `/api/health` | None | None | `{ status: "ok", mongo: true }` | Verified |
| **User Login** | POST | `/api/auth/login` | None | `{ identifier, password, portal }` | `{ _id, userId, username, name, role, companyId, company, avatar, token, authSource }` | Verified |
| **Change Password** | POST | `/api/auth/change-password` | Bearer JWT | `{ oldPassword, newPassword }` | `{ message: "Password updated successfully" }` | Verified |
| **Current User Profile** | GET | `/api/users/profile` | Bearer JWT | None | User model JSON | Verified |
| **Avatar Upload** | POST | `/api/users/:userId/avatar` | Bearer JWT | Multipart `avatar` | `{ message, avatarUrl }` | Verified |
| **Attendance Status** | GET | `/api/attendance/today` | Bearer JWT | None | Today's clock-in/out record | Verified |
| **Clock In** | POST | `/api/attendance/clock-in` | Bearer JWT | `{ latitude, longitude }` | Attendance record + geofence verification | Verified |
| **Clock Out** | POST | `/api/attendance/clock-out` | Bearer JWT | `{ latitude, longitude }` | Attendance record updated | Verified |
| **Company Geofence** | GET | `/api/company/:id/geofence` | Bearer JWT | None | `{ officeLat, officeLng, radiusMeters }` | Verified |
| **User Tasks** | GET | `/api/tasks/my` | Bearer JWT | None | Array of assigned Task models | Verified |
| **Notifications** | GET | `/api/notifications` | Bearer JWT | None | Array of notifications | Verified |

## Port 3004 PostgreSQL Authentication Note
When the PostgreSQL Auth Service on port 3004 is active, `POST /api/auth/login` automatically synchronizes and validates against PostgreSQL (`auth_service` database). No direct PostgreSQL client configuration is needed on mobile.

