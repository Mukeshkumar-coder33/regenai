# ReGen Mobile & Multiplatform Engineering Guide

## 1. Protected Branch Rules
- **DO NOT** commit, push, merge into, or rebase `mukesh` or `friend-work`. These are dedicated website production/staging branches.
- Flutter mobile development is strictly isolated on:
  - `mukesh-app` (Mukesh's mobile development branch)
  - `friend-app` (Friend's mobile development branch)
- Never force push or delete remote mobile branches.
- Common baseline: `005b264933cbb92b7beb4b8f9f0fd95058f80bd9`.

## 2. Repository & Workspace Conventions
- All mobile code resides under `reGen/mobile_app/`.
- Backend (`reGen/server/`) and React frontend (`reGen/frontend/`) must remain untouched unless an explicit mobile API extension is proposed and approved.
- Use only remote `origin` (`https://github.com/Mukeshkumar-coder33/regenai.git`). Do not push to `krishub`.

## 3. Architecture & Standards
- Feature-based clean architecture:
  - `lib/app/`: App entry, theme setup, routing.
  - `lib/core/`: Network client, secure storage, theme tokens, reusable widgets.
  - `lib/features/`: Isolated feature modules (`splash`, `auth`, `dashboard`, `attendance`, etc.).
- Material 3 with the **Premium Celadon** design system:
  - Mint & pale celadon backgrounds (`#F4F8F5`).
  - Deep forest green buttons & active accents (`#1B5E4B`).
  - Rounded cards, subtle border borders (`#D3E6DC`), and accessible contrast.

## 4. Dual Database & Port 3004 Rules
- Backend operates on `PORT 5006`.
- PostgreSQL Auth Service operates on `PORT 3004`.
- The mobile app interacts with the ReGen backend API (`POST /api/auth/login`). The backend automatically handles two-way user synchronization and verification with PostgreSQL when port 3004 is active.
- Mobile client never connects directly to MongoDB or PostgreSQL.

## 5. Verification Protocol
- Run `flutter analyze` and `flutter test` after every feature milestone.
- Verify Git branch references and `git status` before committing.
