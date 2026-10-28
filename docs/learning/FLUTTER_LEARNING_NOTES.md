# Flutter Learning Notes — Milestone 1

## Milestone 1: Premium Celadon Theme & Splash Screen

### What We Built
In this milestone, we set up the foundation of the ReGen mobile app:
1. Created the Flutter application inside `mobile_app/` with package ID `com.mukeshkumar_coder33.regen_mobile`.
2. Created `lib/core/theme/celadon_colors.dart` to establish our corporate color palette.
3. Created `lib/core/theme/celadon_theme.dart` configuring Material 3 with custom colors, button styles, card shapes, and typography.
4. Created reusable UI components: `CeladonButton` and `CeladonCard`.
5. Created an animated `SplashScreen` in `lib/features/splash/presentation/splash_screen.dart` with logo display, scale/fade animation, and status indicators.
6. Created automated unit/widget smoke tests in `test/widget_test.dart` and verified with `flutter analyze` and `flutter test`.

---

### Key Takeaways for Beginners
1. **Dart is strongly typed**: Every variable, function return, and widget property has a type (or inferred type).
2. **Flutter is declarative**: You don't mutate HTML elements; you describe what the UI should look like for a given state.
3. **The widget tree is composed of small building blocks**: A button is an `ElevatedButton` wrapping a `Row` wrapping an `Icon` and `Text`.
4. **ThemeData controls global look-and-feel**: By configuring `ThemeData` once in `MaterialApp`, every button, card, and text field across the entire app automatically conforms to the Premium Celadon design system.

