# ReGen Mobile Architectural Decisions Record (ADR)

## ADR-001: Common Git Baseline Selection
- **Decision:** Use commit `005b264933cbb92b7beb4b8f9f0fd95058f80bd9` (`origin/mukesh`) as the single baseline for both `mukesh-app` and `friend-app`.
- **Reason:** `005b264` incorporates the latest merged work from `friend-work` and contains essential mobile attendance backend updates (`server/utils/geofence.js` and updated attendance controllers).
- **Protected Branches:** Website branches `mukesh` and `friend-work` remain read-only and will never be touched by mobile workflows.

## ADR-002: Flutter Package Identifier & Git ID
- **Decision:** Use `com.mukeshkumar_coder33.regen_mobile` as the application package identifier.
- **Reason:** Directly aligned with GitHub identity `Mukeshkumar-coder33` and project `regenai` as instructed.

## ADR-003: Design System — Premium Celadon UI
- **Decision:** Built a custom Flutter Material 3 design system using soft celadon canvas backgrounds (`#F4F8F5`), forest-green action controls (`#1B5E4B`), and rounded enterprise card styling.
- **Reason:** Provides a refined, modern mobile-first identity that distinguishes the mobile application while honoring corporate brand aesthetics.

## ADR-004: Native Flutter Typography vs External Font CDN
- **Decision:** Use native Flutter `TextTheme` configured with high-contrast weights instead of dynamic CDN font fetchers during development.
- **Reason:** Eliminates Windows symlink developer mode requirements, avoids third-party package conflicts, ensures offline testing reliability, and compiles cleanly across Web, Android, and iOS.
