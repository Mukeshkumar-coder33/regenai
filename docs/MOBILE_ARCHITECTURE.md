# ReGen Mobile Architecture Specification

## 1. High-Level Architecture
ReGen Mobile is built with Flutter (Dart) using a modular, feature-driven Clean Architecture pattern.

```text
mobile_app/
├── lib/
│   ├── main.dart             # App entry point
│   ├── app/                  # Application-wide configuration and routing
│   │   ├── app.dart          # Root MaterialApp
│   │   ├── app_config.dart   # Server endpoints & port configuration
│   │   └── router.dart       # Screen routing & route guards
│   ├── core/                 # Shared foundations
│   │   ├── api/              # API contracts & constants
│   │   ├── network/          # HTTP client, token interceptors, error handling
│   │   ├── storage/          # Secure JWT & user session persistence
│   │   ├── theme/            # Celadon colors, typography, theme data
│   │   └── widgets/          # Reusable buttons, cards, text fields, loaders
│   └── features/             # Business modules
│       ├── splash/           # Splash animation & startup checks
│       ├── auth/             # Login, forgot password, role detection
│       ├── dashboard/        # Role-based dashboard (Employee, Company, SuperAdmin)
│       ├── attendance/       # Clock in/out, geofencing, history
│       ├── tasks/            # Task lists, delegation, deadlines
│       └── messenger/        # Direct messages, Socket.IO, WebRTC calls
```

## 2. Design System: Premium Celadon UI
- **Canvas / Background:** Soft Mint Celadon (`#F4F8F5`)
- **Primary Brand / Action:** Deep Forest Green (`#1B5E4B`)
- **Containers & Badges:** Pale Mint (`#E4F3EC`)
- **Surfaces & Cards:** Crisp White (`#FFFFFF`) with thin Celadon border (`#D3E6DC`) and subtle shadow
- **Typography:** High-contrast slate forest typography with structured weights (`w400`, `w500`, `w600`, `w700`).

## 3. Dual Database Integration
- The ReGen backend runs on `PORT 5006`.
- The PostgreSQL Auth Service runs on `PORT 3004`.
- When port 3004 is active, the backend automatically performs dual authentication and synchronizes company owner and employee credentials between MongoDB and PostgreSQL (`auth_service` database, `public."User"` table).
- The Flutter mobile client connects exclusively through the backend REST API (`POST /api/auth/login`) and Socket.IO gateway on port 5006, ensuring client simplicity and backend security.
