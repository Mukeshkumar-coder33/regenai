# ReGen Mobile Application

A cross-platform Flutter application for Android and iOS built for the ReGen Workforce & Office Management System, adopting the **Premium Celadon UI** design system.

---

## 1. Quick Start

### Prerequisites
- Flutter SDK 3.47.7+ (Channel stable)
- Dart SDK 3.13.5+
- Google Chrome (for rapid web & virtual device testing)
- Node.js & npm (for the ReGen backend)

### Run the App on Chrome (with Built-In Smartphone Simulator)
```bash
cd mobile_app
flutter run -d chrome
```
*Tip:* When running on Chrome, the app automatically renders inside an authentic **390 × 844 px Smartphone Frame** with mobile status bar, curved corners, and dynamic island!

### Terminal Interactive Commands:
- **`r`** : Hot Reload (sub-second code updates)
- **`R`** : Hot Restart (re-runs `main()`)
- **`q`** : Quit the running app session

---

## 2. Connecting to the ReGen Backend

1. Start the Node.js backend server:
   ```bash
   cd server
   npm run dev
   ```
   *(Backend listens on port `5006`)*

2. Start the PostgreSQL Auth Service (optional, on port `3004`):
   - When port 3004 is active, the backend automatically validates and synchronizes company and employee accounts with the PostgreSQL `auth_service` database!
   - When port 3004 is offline, the backend gracefully falls back to MongoDB.

3. Log in through the app:
   - Use any existing company owner, employee, or superadmin credentials.
   - The app securely stores JWT tokens via `SessionStorage` and navigates to the role-based dashboard.

---

## 3. Testing and Static Analysis

### Static Code Analysis:
```bash
flutter analyze
```

### Run Automated Unit & Widget Tests:
```bash
flutter test
```

---

## 4. Architecture Overview

```text
lib/
├── app/
│   ├── app.dart              # Root MaterialApp with Celadon theme & VirtualDeviceFrame
│   └── app_config.dart       # Dynamic backend URLs (127.0.0.1 for Web, 10.0.2.2 for Android Emulator)
├── core/
│   ├── storage/
│   │   └── session_storage.dart  # Secure JWT & session persistence
│   ├── theme/
│   │   ├── celadon_colors.dart   # Mint & Forest Green design tokens
│   │   └── celadon_theme.dart    # Material 3 ThemeData
│   └── widgets/
│       ├── celadon_button.dart   # Reusable button with loading spinner
│       ├── celadon_card.dart     # Rounded enterprise card
│       └── virtual_device_frame.dart # Instant in-Chrome phone chassis
└── features/
    ├── splash/
    │   └── presentation/     # Animated brand splash screen with session routing
    ├── auth/
    │   ├── data/             # UserModel, AuthService (POST /api/auth/login)
    │   └── presentation/     # AuthController, LoginScreen (Username, Password, Sign In)
    └── dashboard/
        └── presentation/     # Role-based landing views & Super Admin dual-mode switching
```

---

## 5. Dual-Mode Super Admin Switching

For users with Super Admin privileges (`param` or owner username matching `SUPER_ADMIN_USERNAME`), the dashboard presents a dual-mode switcher:
- **Switch to Company Workspace:** calls `POST /api/auth/switch-to-ems` and switches token to `role: 'owner'`.
- **Switch to Super Admin Console:** calls `POST /api/auth/switch-to-superadmin` and switches token to `role: 'param'`.
