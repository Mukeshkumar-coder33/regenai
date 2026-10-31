# ReGen Mobile App — Progress Tracker

## Project Overview
- **Repository:** https://github.com/Mukeshkumar-coder33/regenai/
- **Mobile Branches:**
  - `mukesh-app` (active development branch)
  - `friend-app` (friend development branch)
- **Baseline Commit:** `005b264933cbb92b7beb4b8f9f0fd95058f80bd9` (origin/mukesh, incorporating origin/friend-work and backend geofence updates)
- **Application ID / Package:** `com.mukeshkumar_coder33.regen_mobile`
- **Design System:** Premium Celadon UI (Mint canvas `#F4F8F5`, Forest Green `#1B5E4B`, crisp typography, rounded enterprise cards, glowing ReGen emblem)

---

## Progress Dashboard

| Phase / Milestone | Status | Description |
|---|---|---|
| **Phase 1: Git & Baseline Setup** | COMPLETED | Verified baseline `005b264`, created & pushed `mukesh-app` and `friend-app`, preserved website branches. |
| **Phase 2: Project Init & Architecture** | COMPLETED | Initialized Flutter project under `reGen/mobile_app/` with package ID `com.mukeshkumar_coder33.regen_mobile`. |
| **Phase 3: Premium Celadon Design & Splash** | COMPLETED | Created `CeladonColors`, `CeladonTheme`, `BrandLogo`, and animated `SplashScreen` (Screen 1). |
| **Phase 4: Authentication & Login** | COMPLETED | Full reproduction of Website Login: ReGen emblem badge, Username / User ID, Password with visibility toggle, Remember me checkbox, deep green Login button. Zero external SSO, zero signup links. |
| **Phase 5: Role-Based Dashboard Architecture** | COMPLETED | Implemented strict role separation across 4 distinct situations (A: Employee, B: Regular Owner, C: SuperAdmin in Company Mode, D: Global SuperAdmin Console) with 100% dynamic business data. All tests passing (9/9), 0 analyzer issues. |
| **Phase 6: Attendance, Geofencing, Schedules & Calendar (Milestone 3)** | COMPLETED | Implemented real device GPS acquisition with high accuracy, strict 5-metre backend geofence verification, check-in, check-out, official (lunch) & casual (tea) break tracking with active timers, Company Attendance Roster, PayrollSettings shift & break schedule configuration, Attendance Reports, and dynamic Calendar integration. All tests passing (14/14), 0 analyzer issues. |
| **Phase 7: Real Company Executive UI Overhaul** | COMPLETED | Implemented high-end dark glassmorphic UI exclusively for Company workspace matching provided design references: 5-tab bottom nav (Home, Employees, Attendance, Leave, Profile), Weekly Attendance Bar Chart, Employee Management with status pills, Month Calendar Tracker, Leave Approvals, Company Profile (5m GPS geofence), and Notifications center. Preserved common Login screen and role functionality. All 18 tests passing, 0 analyzer issues. |
| **Phase 8: High-Contrast Bokeh Blur & Company Operations Navigation** | COMPLETED | Applied Gaussian bokeh blur (`sigmaX: 20, sigmaY: 20`) to dark office background across Company screens and notifications sheet for razor-sharp typography readability. Implemented dedicated dark glassmorphic Company Drawer opened by top hamburger icon (`☰`) and Company Operations section on Dashboard containing the 7 operations modules: Employee Management, Attendance, Tasks, Leaves & Holidays, Payroll, Reports, and Settings with live dynamic badges and navigation. All 18 tests passing, 0 analyzer issues. |

---

## Strict 4-Situation Role Separation Architecture

1. **Situation A — Employee / User Dashboard (`EmployeeDashboardView`):**
   - **Target Roles:** `staff`, `intern`, `freelancer` (e.g., `Ram`).
   - **Personalized Header:** Employee name, designation, department, and company badge.
   - **Dynamic 2x2 Metric Grid:** Today's attendance status ("Present", "Late", "Not Checked In"), live assigned tasks count, days attended, and approved leaves.
   - **Today's Tasks:** Filtered by logged-in user with priority badges (High, Medium, Low), due dates, and empty state.
   - **Security:** Zero company management or SuperAdmin controls exposed.

2. **Situation B — Company Owner / Admin Dashboard (`CompanyDashboardView`):**
   - **Target Roles:** `owner`, `admin` of a regular enterprise (e.g., `zevoxmedice_8cb4` at `Zevox Medice`).
   - **Dynamic Header:** Live company name, city, and state fetched from `/api/company`.
   - **Dynamic Metrics Card:** Live registered employees count and distinct departments count.
   - **Operations Quick Glance:** Live attendance count today and active tasks count.
   - **Operations Menu (Screen 8):** Employee Management (with live roster bottom sheet), Attendance, Tasks, Leaves, Payroll, Reports, Settings.
   - **Security:** No SuperAdmin controls or switcher shown.

3. **Situation C — Super Admin in Company Mode (`CompanyDashboardView` with Switcher):**
   - **Target Role:** `Vyshwa` (`role: 'owner'`, company: `krish Tech Computer`).
   - **Primary Environment:** Standard company dashboard for `krish Tech Computer`, Coimbatore with 3 employees, 1 task, and 2 attendance records.
   - **SuperAdmin Quick Action:** High-visibility banner allowing instant switch to ReGen Central Console via `POST /api/auth/switch-to-superadmin`.

4. **Situation D — Global Super Admin Dashboard (`SuperAdminDashboardView`):**
   - **Target Role:** `role == 'param'` (e.g., `Vyshwa` switched to `ReGen Central`).
   - **Global Platform Metrics:** Total Tenants (7 companies), Global Users (17 users), active tenants breakdown, role distribution.
   - **EMS Switcher:** Action banner allowing instant return to primary company workspace (`krish Tech Computer`) via `POST /api/auth/switch-to-ems`.
   - **Platform Directories:** Live Directory of all 7 companies with status pills and full platform user directory.

---

## Milestone 3 Architecture & Capabilities
1. **Real Device GPS Geofencing (Strict 5-Metre Radius):**
   - Built `LocationService` with high-accuracy GPS fix via `geolocator`.
   - Sends real device coordinates (`latitude`, `longitude`, `accuracy`) to backend endpoints (`POST /api/attendance` and `PUT /api/attendance/:id`).
   - Strict 5m rule enforced: if > 5m, server returns 403 `OUTSIDE_GEOFENCE` with exact distance. UI displays detailed proximity feedback.
   - If company office location is missing (`OFFICE_LOCATION_NOT_SET`), UI alerts the user, and empowers company owners to configure it on the fly.
2. **Break Management & Over-Break Tracking:**
   - Official Break (Lunch): start/end transitions with elapsed live counter and 60-minute threshold.
   - Casual Break (Tea/Coffee): start/end transitions with 15-minute threshold.
   - All break transitions verified against the 5-metre geofence.
   - Server calculates break duration, delays beyond allowance, and automated salary deductions.
3. **Company Work Schedules & Shift Rules:**
   - Maps to MongoDB `PayrollSetting` (`GET/PUT /api/payroll/settings`).
   - Configures check-in targets (`09:30`), check-out targets (`18:30`), daily working hours (`8h`), weekly off days (`Sun, Sat`), and break allowances.
4. **Company Attendance Roster & Reports:**
   - Live roster bottom sheet for owners displaying present, late, half-day, and absent employees with check-in/out times.
   - Attendance report dialog powered by `/api/attendance/report` with period filter (day, week, month, year) and metrics (Total Working Hours, Average Daily Hours, Present, Late).
5. **Dynamic Calendar Integration (Screen 5):**
   - Connected to live MongoDB collections: `Holiday` (`/api/holidays`), `Attendance` (`/api/attendance`), `Task` (`/api/tasks`), and `Leave` (`/api/leaves`).
   - Color-coded date indicators and categorized daily events list.

---

## Verification & Automated Testing
- `flutter analyze`: **0 issues found** (Clean code, zero warnings or deprecated methods).
- `flutter test`: **14/14 tests passed** (Role architecture, Login validation, Dashboard situations, Attendance break/GPS parsing, Work schedule calculations, Holiday/Report models, AttendanceView, CalendarView).
- **Live Backend Verification:** Running Node.js server on port 5006, dual auth listener on port 3004, MongoDB on port 27017, and PostgreSQL on port 5432.
- **Android APK Build:** Successfully compiled `app-debug.apk` and installed onto `emulator-5554`.
