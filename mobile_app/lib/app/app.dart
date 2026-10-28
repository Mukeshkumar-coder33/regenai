import 'package:flutter/material.dart';
import '../core/theme/celadon_theme.dart';
import '../core/widgets/virtual_device_frame.dart';
import '../features/splash/presentation/splash_screen.dart';

/// ReGenApp Root Widget
///
/// Sets up global MaterialApp configuration, Celadon theme,
/// and wraps the screens in a Virtual Device Simulator for web/desktop.
class ReGenApp extends StatelessWidget {
  const ReGenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ReGen',
      debugShowCheckedModeBanner: false,
      theme: CeladonTheme.lightTheme,
      home: const VirtualDeviceFrame(
        child: SplashScreen(),
      ),
    );
  }
}
