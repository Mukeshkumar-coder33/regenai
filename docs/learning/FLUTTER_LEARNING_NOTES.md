# Flutter Learning Notes — ReGen Mobile Architecture

## Milestone 1: Premium Celadon Theme & Splash Screen
- Created `CeladonColors` and `CeladonTheme`.
- Built reusable `CeladonButton` and `CeladonCard`.
- Created animated `SplashScreen` and `VirtualDeviceFrame` for Chrome preview.
- Configured glowing brand logo emblem matching the ReGen identity.

---

## Milestone 2: Authentication & Strict Role-Based Dashboards

### 1. Form Design & Website Parity
- **No Extraneous Elements:** Mobile login strictly mirrors the ReGen website: **Username / User ID**, **Password** (with visibility toggle), **Remember me** checkbox, and deep green **Login** button.
- Third-party social logins (Google, Apple, Microsoft) and public signup links are omitted to maintain enterprise security parity.
- **Port 3004 Synchronization:** When the PostgreSQL authentication service on port 3004 is active, the backend dual-authenticates credentials and returns `authSource: 'dual:synchronized'`.

### 2. Strict Role Separation (4 Situations)
Rather than displaying a generic dashboard with static placeholder metrics (such as hardcoded "128 employees" or "12 departments"), the app dynamically separates access into 4 distinct situations based on the user's role and portal:

- **Situation A: Employee / Staff (`EmployeeDashboardView`):**
  - Used for `staff`, `intern`, and `freelancer` accounts (e.g., `Ram`).
  - Displays personalized greeting, employee designation, and department.
  - Dynamic 2x2 metric grid: Today's attendance status ("Present", "Late", "Not Checked In"), live assigned tasks count, days attended, and approved leaves.
  - "Today's Tasks" section shows tasks assigned directly to this user with priority badges (High, Medium, Low).
  - No company admin controls or SuperAdmin tools are exposed.

- **Situation B: Regular Company Owner (`CompanyDashboardView`):**
  - Used for standard company owners and administrators (e.g., `zevoxmedice_8cb4` at `Zevox Medice`).
  - Displays company header with live company name and city/state from `GET /api/company`.
  - Dynamic overview statistics card showing actual registered employees count (`GET /api/users`) and distinct active departments.
  - Operations menu (Screen 8) with Employee Management (live roster bottom sheet), Attendance, Tasks, Leaves, Payroll, Reports, and Settings.
  - No SuperAdmin console switchers are visible.

- **Situation C: Super Admin in Company Mode (`CompanyDashboardView` + SuperAdmin Switcher):**
  - Used when `Vyshwa` logs in via normal company portal.
  - Default landing is their primary enterprise: `krish Tech Computer`, Coimbatore.
  - Displays live company metrics (3 employees, 1 task, 2 attendance records).
  - Includes a prominent **"Switch to Super Admin Console"** banner backed by `POST /api/auth/switch-to-superadmin`.

- **Situation D: Global Super Administrator Console (`SuperAdminDashboardView`):**
  - Used when `role == 'param'` (e.g., `Vyshwa` after switching or logging into superadmin view).
  - Global platform metrics: Total platform tenants (7 companies), global users (17 users), active tenants breakdown.
  - Includes a prominent **"Switch to Company Workspace"** banner backed by `POST /api/auth/switch-to-ems` to seamlessly return to `krish Tech Computer`.
  - Live Companies Directory showing all 7 platform companies with active status pills.

### 3. Flutter Best Practices Learned
1. **Material Ancestry with ListTiles:**
   - In Flutter, `ListTile` paints its background and ripple/ink splashes onto the nearest `Material` ancestor. Wrapping a `ListTile` directly inside a `DecoratedBox` with a background color obscures ink splashes and triggers framework warnings.
   - *Fix:* Wrap `ListTile` in a `Material` widget:
     ```dart
     Material(
       color: Colors.white,
       shape: RoundedRectangleBorder(
         borderRadius: BorderRadius.circular(16),
         side: const BorderSide(color: CeladonColors.borderLight),
       ),
       child: ListTile(...),
     )
     ```
2. **Standard Dart Date Formatting:**
   - Avoid pulling heavy internationalization dependencies (`intl`) when simple date formatting suffices:
     ```dart
     const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
     const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
     final now = DateTime.now();
     final dateStr = '${weekdays[now.weekday - 1]}, ${now.day} ${months[now.month - 1]} ${now.year}';
     ```
3. **Reactive User State via Callbacks:**
   - Passing `onUserUpdated: (updatedUser) => setState(() => _currentUser = updatedUser)` from child dashboard views up to `DashboardScreen` allows smooth, in-place switching between Company Workspace and SuperAdmin Console without requiring a full logout or app restart.

---

## Milestone 3: Attendance, 5m Geofencing, Breaks, Schedules & Calendar

### 1. High-Accuracy Hardware GPS & Permission Lifecycle (`LocationService`)
- On Android, location permissions require entries in `AndroidManifest.xml`:
  ```xml
  <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
  <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
  ```
- Before requesting GPS coordinates, Flutter must sequentially verify:
  1. `Geolocator.isLocationServiceEnabled()`: If false, prompts user to turn on GPS hardware.
  2. `Geolocator.checkPermission()`: If `denied`, triggers `Geolocator.requestPermission()`. If `deniedForever`, guides user to app settings.
  3. `Geolocator.getCurrentPosition(locationSettings: LocationSettings(accuracy: LocationAccuracy.best))`: Queries GPS satellites and Wi-Fi trilateration for highest possible precision.
- **Geofence Distance:** In addition to backend validation, client-side distance is computed via `Geolocator.distanceBetween(lat1, lon1, lat2, lon2)` using the geodesic Haversine formula.

### 2. Strict 5-Metre Backend Geofence Rule
- The ReGen backend enforces `GEOFENCE_RADIUS_METRES = 5`.
- If an employee is outside the 5-metre radius, the API responds with HTTP 403 and payload:
  ```json
  {
    "message": "You must be within 5 metres of your registered office to perform this action.",
    "code": "OUTSIDE_GEOFENCE",
    "distance": 42.5,
    "maxAllowedDistance": 5
  }
  ```
- We created `GeofenceException` to preserve these error properties so the Flutter UI informs the employee of their exact distance and radius requirement.
- When `OFFICE_LOCATION_NOT_SET` is returned, company owners are immediately prompted with a dialog to set the office pin using current GPS coordinates (`PUT /api/company/:id/office-location`).

### 3. State Management for Active Breaks & Live Timers
- Attendance documents track `activeBreakType`: `'official'` (lunch) or `'casual'` (tea/coffee).
- When a break is active, `AttendanceView` initializes a 1-second periodic `Timer`:
  ```dart
  _breakTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
    setState(() => _breakSecondsElapsed++);
  });
  ```
- This powers the live counter displayed in the UI (e.g. `Active: 12:45`), letting employees monitor their allowed allowance before deductions occur.
- Calling `_breakTimer?.cancel()` inside `dispose()` prevents memory leaks when the view is unmounted.

### 4. Asynchronous BuildContext Safety (`use_build_context_synchronously`)
- Flutter's linter flags using `BuildContext` across `await` boundaries because the enclosing widget may unmount before the future completes.
- *Best Practice Solution:* Cache references to `ScaffoldMessenger.of(context)` or `Navigator.of(context)` before the `await` call:
  ```dart
  final messenger = ScaffoldMessenger.of(context);
  final nav = Navigator.of(context);
  await _service.performAction();
  nav.pop();
  messenger.showSnackBar(...);
  ```

### 5. Multi-Source Dynamic Calendar Integration
- Rather than displaying static mock events, the calendar unifies four distinct live MongoDB collections:
  - `GET /api/holidays`: Company holidays (marked in Amber/Festive badge).
  - `GET /api/attendance`: Past check-in/out logs (marked in Green).
  - `GET /api/tasks`: Scheduled tasks matching due dates (marked in Purple).
  - `GET /api/leaves`: Approved leaves spanning date ranges (marked in Red).
- This creates an informative, real-time schedule without inventing duplicate schemas.
