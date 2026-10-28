import 'package:flutter/material.dart';
import '../core/theme/celadon_theme.dart';
import '../features/splash/presentation/splash_screen.dart';

/// ReGenApp Root Widget
///
/// Sets up global MaterialApp configuration, Celadon theme,
/// and sets the initial entry route.
class ReGenApp extends StatelessWidget {
  const ReGenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ReGen',
      debugShowCheckedModeBanner: false,
      theme: CeladonTheme.lightTheme,
      home: const SplashScreen(),
    );
  }
}
