# Flutter Learning Notes

## Milestone 1: Premium Celadon Theme & Splash Screen
- Created `CeladonColors` and `CeladonTheme`.
- Built reusable `CeladonButton` and `CeladonCard`.
- Created animated `SplashScreen` and `VirtualDeviceFrame` for Chrome preview.

---

## Milestone 2: Login and Authentication

### What We Built
1. **Config Layer (`lib/app/app_config.dart`)**:
   - Centralized server configuration. Differentiates between Web/Chrome (`http://127.0.0.1:5006`), Android Emulator (`http://10.0.2.2:5006`), and Physical LAN devices.
2. **Domain/Data Model (`lib/features/auth/data/user_model.dart`)**:
   - Represents the authenticated user. Parses backend fields (`_id`, `userId`, `username`, `name`, `role`, `companyId`, `company`, `avatar`, `token`, `authSource`).
   - Helper getters: `isSuperAdmin` (`param`), `isCompanyAdmin` (`owner` / `admin`), and `isEmployee` (`staff` / `intern`).
3. **Session Storage (`lib/core/storage/session_storage.dart`)**:
   - Persists JWT tokens and user session data cross-platform using `SharedPreferences`.
   - Never stores plaintext passwords.
4. **Authentication Service (`lib/features/auth/data/auth_service.dart`)**:
   - Communicates with `POST /api/auth/login`.
   - Dispatches payload: `{ "identifier": username, "password": password, "portal": "company" }`.
   - Maps backend HTTP status codes:
     - `200`: Success (saves session, returns `UserModel`).
     - `401`: "Invalid credentials".
     - `403`: "Your account has been suspended" or "Your company has been blocked".
     - `503`: "Maintenance Process Ongoing".
     - Connection failure: User-friendly message explaining backend reachability on port 5006.
5. **State Management (`lib/features/auth/presentation/auth_controller.dart`)**:
   - Manages `isLoading`, `errorMessage`, and `currentUser` via `ChangeNotifier`.
6. **Login Screen UI (`lib/features/auth/presentation/login_screen.dart`)**:
   - Minimalist form containing only:
     - **Username** field (with person icon and validation).
     - **Password** field (with lock icon, obscure toggle, and validation).
     - **Sign In** button (with loading spinner).
   - Error feedback banner for server errors.
7. **Role-Based Landing Dashboard (`lib/features/dashboard/presentation/dashboard_screen.dart`)**:
   - Displays user initials, full name, company, role badge, and database sync status (`dual:synchronized`, `mongodb:primary`).
   - Includes logout confirmation dialog that purges session and returns to login.
