import 'package:flutter/foundation.dart';

/// Central API Configuration for ReGen Mobile
///
/// Configures backend host URLs and routes. Automatically differentiates
/// between Web/Chrome (localhost), the Android Emulator (10.0.2.2),
/// and physical mobile devices over local WiFi.
abstract final class AppConfig {
  /// The default development server port where ReGen Node.js server runs.
  static const int backendPort = 5006;

  /// The PostgreSQL Auth Service port.
  /// When this port is reachable on the server, logins and accounts are
  /// synchronized across MongoDB and PostgreSQL automatically.
  static const int authServicePort = 3004;

  /// Dynamically resolves the base URL based on platform.
  ///
  /// - Web / Chrome: `http://localhost:5006` or `http://127.0.0.1:5006`
  /// - Android Emulator: `http://10.0.2.2:5006` (Android's alias to host PC loopback)
  /// - iOS Simulator: `http://localhost:5006`
  /// - Physical Phone: Configure with your machine's LAN IP (e.g. `http://192.168.1.x:5006`)
  static String get defaultBaseUrl {
    if (kIsWeb) {
      return 'http://127.0.0.1:$backendPort';
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        // Android Emulator routes 10.0.2.2 to the development machine's 127.0.0.1
        return 'http://10.0.2.2:$backendPort';
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      default:
        return 'http://127.0.0.1:$backendPort';
    }
  }

  /// Active base URL (can be customized at runtime during development if testing on LAN)
  static String activeBaseUrl = defaultBaseUrl;

  // Endpoint routes
  static String get loginUrl => '$activeBaseUrl/api/auth/login';
  static String get healthUrl => '$activeBaseUrl/api/health';
  static String get profileUrl => '$activeBaseUrl/api/users/profile';
}

