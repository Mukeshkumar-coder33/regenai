import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Target backend environment mode for ReGen Mobile.
enum ServerEnvironment {
  auto,
  company,
  local,
}

/// Central API, Media & Socket.IO Configuration for ReGen Mobile.
///
/// Supports automatic dual-environment resolution without reinstalling or
/// manually toggling settings:
/// - In [ServerEnvironment.auto] (default), probes local backend `/api/health`
///   (`http://192.168.1.38:5006` on mobile; also `127.0.0.1:5006` on PC dev).
/// - Uses the local backend when reachable on Wi-Fi, and automatically falls back
///   to `https://regen.krishub.in` on mobile data / external networks / server offline.
abstract final class AppConfig {
  /// Port where the local Node.js/Express backend runs.
  static const int backendPort = 5006;

  /// Legacy PostgreSQL Auth Service port reference.
  static const int authServicePort = 3004;

  /// Production Company Server domain (never appends `:5006`).
  static const String companyServerUrl = 'https://regen.krishub.in';
  static const String companyServerHost = 'regen.krishub.in';
  static const String companyPublicIp = '103.186.230.7';

  /// Default reachable Wi-Fi LAN IP for the local Node.js backend on Windows.
  /// Physical mobile devices must NOT use `localhost`.
  static const String defaultLocalIp = '192.168.1.38';
  static const String defaultLocalServerUrl = 'http://$defaultLocalIp:$backendPort';

  static const String _prefServerModeKey = 'regen_server_mode';
  static const String _prefLocalServerUrlKey = 'regen_local_server_url';
  static const String _prefLegacyCustomUrlKey = 'regen_custom_backend_url';

  static const Duration _healthProbeTimeout = Duration(milliseconds: 800);
  static const Duration _probeCooldown = Duration(seconds: 15);

  /// Default base URL resolved at startup before async preferences / health probe finish.
  static String get defaultBaseUrl {
    const customUrl = String.fromEnvironment('BACKEND_URL');
    if (customUrl.isNotEmpty) {
      return normalizeServerUrl(customUrl);
    }
    return companyServerUrl;
  }

  static ServerEnvironment _serverEnvironment = _initialEnvironment();
  static String _localServerUrl = _initialLocalUrl();
  static String activeBaseUrl = defaultBaseUrl;
  static DateTime? _lastProbeAt;
  static Future<String>? _inFlightProbe;
  static http.Client? _probeClientOverride;

  /// Observable notifier so Socket.IO & UI stay synced when backend auto-switches.
  static final ValueNotifier<String> baseUrlNotifier = ValueNotifier<String>(activeBaseUrl);

  static ServerEnvironment _initialEnvironment() {
    const customUrl = String.fromEnvironment('BACKEND_URL');
    if (customUrl.isNotEmpty) {
      return isCompanyHostUrl(customUrl)
          ? ServerEnvironment.company
          : ServerEnvironment.local;
    }
    return ServerEnvironment.auto;
  }

  static String _initialLocalUrl() {
    const customUrl = String.fromEnvironment('BACKEND_URL');
    if (customUrl.isNotEmpty && !isCompanyHostUrl(customUrl)) {
      return normalizeLocalUrl(customUrl);
    }
    return defaultLocalServerUrl;
  }

  static ServerEnvironment get serverEnvironment => _serverEnvironment;
  static bool get isAutoMode => _serverEnvironment == ServerEnvironment.auto;
  static bool get isCompanyServer => _serverEnvironment == ServerEnvironment.company;
  static bool get isLocalServer => _serverEnvironment == ServerEnvironment.local;
  static bool get isCurrentlyUsingLocal => !isCompanyHostUrl(activeBaseUrl);
  static String get localServerUrl => _localServerUrl;
  static String get socketBaseUrl => activeBaseUrl;

  static String get serverDisplayName {
    switch (_serverEnvironment) {
      case ServerEnvironment.auto:
        return isCurrentlyUsingLocal ? 'Auto (Local Wi-Fi)' : 'Auto (Public Server)';
      case ServerEnvironment.company:
        return 'Company Server';
      case ServerEnvironment.local:
        return 'Local Server';
    }
  }

  /// Returns only the host/IP segment of the saved local server URL for editing.
  static String get localHostOrIp {
    final uri = Uri.tryParse(_localServerUrl);
    if (uri != null && uri.host.isNotEmpty) {
      return uri.host;
    }
    return defaultLocalIp;
  }

  /// True when [rawUrl] points to the deployed Company Server domain/IP.
  static bool isCompanyHostUrl(String rawUrl) {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) return false;
    final candidate = trimmed.contains('://') ? trimmed : 'https://$trimmed';
    final uri = Uri.tryParse(candidate);
    if (uri == null) return false;
    final host = uri.host.toLowerCase();
    return host == companyServerHost || host == companyPublicIp;
  }

  /// Normalizes any server URL according to Company vs Local rules:
  /// - Company domain always resolves to `https://regen.krishub.in` (never `:5006`).
  /// - Local host/IP resolves to `http://<host>:<port>` (defaults to port `5006`).
  static String normalizeServerUrl(String rawInput) {
    if (isCompanyHostUrl(rawInput)) {
      return companyServerUrl;
    }
    return normalizeLocalUrl(rawInput);
  }

  /// Normalizes a local LAN server IP or URL and guarantees no trailing slash.
  static String normalizeLocalUrl(String rawInput) {
    var cleaned = rawInput.trim();
    while (cleaned.endsWith('/')) {
      cleaned = cleaned.substring(0, cleaned.length - 1);
    }
    if (cleaned.isEmpty) {
      return defaultLocalServerUrl;
    }
    if (isCompanyHostUrl(cleaned)) {
      return companyServerUrl;
    }

    final withScheme =
        cleaned.startsWith('http://') || cleaned.startsWith('https://')
            ? cleaned
            : 'http://$cleaned';
    final uri = Uri.tryParse(withScheme);
    if (uri == null || uri.host.isEmpty) {
      return defaultLocalServerUrl;
    }

    final scheme = uri.scheme.isEmpty ? 'http' : uri.scheme.toLowerCase();
    final port = uri.hasPort ? uri.port : backendPort;
    return '$scheme://${uri.host}:$port';
  }

  /// Resolves relative media/file/avatar paths AND rewrites stale ReGen local/public
  /// media URLs onto the currently selected [activeBaseUrl] so images, uploads, and
  /// downloads work seamlessly after automatic local <-> public switching.
  static String resolveMediaUrl(String? rawUrl) {
    if (rawUrl == null) return '';
    var s = rawUrl.trim();
    if (s.isEmpty) return '';
    if (s.startsWith('data:') || s.startsWith('blob:')) return s;

    if (s.startsWith('http://') || s.startsWith('https://')) {
      final uri = Uri.tryParse(s);
      if (uri != null && _isKnownReGenMediaUri(uri)) {
        final normalizedPath = uri.path.replaceFirst('/uploads/assets/', '/assets/');
        final query = uri.hasQuery ? '?${uri.query}' : '';
        return '$activeBaseUrl$normalizedPath$query';
      }
      return s;
    }

    s = s.replaceFirst('/uploads/assets/', '/assets/');
    final normalized = s.startsWith('/') ? s : '/$s';
    return '$activeBaseUrl$normalized';
  }

  static bool _isKnownReGenMediaUri(Uri uri) {
    final pathLower = uri.path.toLowerCase();
    final isMediaPath = pathLower.startsWith('/uploads/') ||
        pathLower.startsWith('/assets/') ||
        pathLower.startsWith('/profiles/') ||
        pathLower.startsWith('/api/');
    if (!isMediaPath) return false;

    final host = uri.host.toLowerCase();
    return host == companyServerHost ||
        host == companyPublicIp ||
        host == 'localhost' ||
        host == '127.0.0.1' ||
        host.startsWith('192.168.') ||
        host.startsWith('10.') ||
        RegExp(r'^172\.(1[6-9]|2\d|3[0-1])\.').hasMatch(host);
  }

  static List<String> _localProbeCandidates() {
    final list = <String>[];
    final normalizedLocal = normalizeLocalUrl(_localServerUrl);
    if (!isCompanyHostUrl(normalizedLocal) && !_isLoopbackUrl(normalizedLocal)) {
      list.add(normalizedLocal);
    }
    if (!list.contains(defaultLocalServerUrl)) {
      list.add(defaultLocalServerUrl);
    }
    return list;
  }

  static bool _isLoopbackUrl(String url) {
    final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
    return host == 'localhost' || host == '127.0.0.1' || host == '::1';
  }

  /// Checks `<baseUrl>/api/health` with a short timeout to confirm live backend reachability.
  static Future<bool> isBackendHealthy(
    String baseUrl, {
    http.Client? client,
    Duration timeout = _healthProbeTimeout,
  }) async {
    final normalized = normalizeServerUrl(baseUrl);
    final c = client ?? _probeClientOverride ?? http.Client();
    final shouldClose = client == null && _probeClientOverride == null;
    try {
      final res = await c
          .get(
            Uri.parse('$normalized/api/health'),
            headers: const {'Accept': 'application/json'},
          )
          .timeout(timeout);
      if (res.statusCode != 200) return false;
      final decoded = jsonDecode(res.body);
      return decoded is Map && decoded['status'] == 'ok';
    } catch (_) {
      return false;
    } finally {
      if (shouldClose) c.close();
    }
  }

  /// In [ServerEnvironment.auto] mode, probes local LAN backend health and
  /// selects local when reachable or falls back automatically to `https://regen.krishub.in`.
  static Future<String> resolveBestBackend({
    bool forceProbe = false,
    http.Client? client,
  }) async {
    if (_serverEnvironment == ServerEnvironment.company) {
      _applyState(mode: ServerEnvironment.company);
      return activeBaseUrl;
    }
    if (_serverEnvironment == ServerEnvironment.local) {
      _applyState(mode: ServerEnvironment.local, localUrl: _localServerUrl);
      return activeBaseUrl;
    }

    if (_inFlightProbe != null) return _inFlightProbe!;
    final now = DateTime.now();
    if (!forceProbe &&
        _lastProbeAt != null &&
        now.difference(_lastProbeAt!) < _probeCooldown) {
      return activeBaseUrl;
    }

    _inFlightProbe = () async {
      try {
        final candidates = _localProbeCandidates();
        if (candidates.isNotEmpty) {
          final results = await Future.wait(
            candidates.map((candidate) async {
              final ok = await isBackendHealthy(candidate, client: client);
              return ok ? candidate : null;
            }),
          );
          final reachable = results.whereType<String>().firstOrNull;
          if (reachable != null) {
            _lastProbeAt = DateTime.now();
            _setResolvedUrl(reachable);
            return activeBaseUrl;
          }
        }
        _lastProbeAt = DateTime.now();
        _setResolvedUrl(companyServerUrl);
        return activeBaseUrl;
      } finally {
        _inFlightProbe = null;
      }
    }();

    return _inFlightProbe!;
  }

  /// Called when an active API/Socket request encounters connectivity failure while
  /// in [ServerEnvironment.auto] mode; gracefully fails over to public server.
  static Future<bool> handleConnectionErrorFailover({http.Client? client}) async {
    if (_serverEnvironment != ServerEnvironment.auto) return false;
    final previous = activeBaseUrl;
    await resolveBestBackend(forceProbe: true, client: client);
    return activeBaseUrl != previous;
  }

  static void _setResolvedUrl(String url) {
    final normalized = normalizeServerUrl(url);
    if (activeBaseUrl != normalized) {
      activeBaseUrl = normalized;
      baseUrlNotifier.value = normalized;
    }
  }

  static void _applyState({
    required ServerEnvironment mode,
    String? localUrl,
    String? resolvedOverride,
  }) {
    if (localUrl != null && localUrl.trim().isNotEmpty && !isCompanyHostUrl(localUrl)) {
      _localServerUrl = normalizeLocalUrl(localUrl);
    }
    _serverEnvironment = mode;
    final nextUrl = mode == ServerEnvironment.company
        ? companyServerUrl
        : (mode == ServerEnvironment.local
            ? _localServerUrl
            : (resolvedOverride ?? activeBaseUrl));
    _setResolvedUrl(nextUrl);
  }

  /// Load persisted server preference and optionally probe live backend endpoint in auto mode.
  static Future<void> init({
    bool autoProbe = true,
    bool forceProbe = false,
    http.Client? probeClient,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedLocal = prefs.getString(_prefLocalServerUrlKey);
      if (savedLocal != null && savedLocal.trim().isNotEmpty && !isCompanyHostUrl(savedLocal)) {
        _localServerUrl = normalizeLocalUrl(savedLocal);
      }

      final savedMode = prefs.getString(_prefServerModeKey);
      if (savedMode == 'company') {
        _applyState(mode: ServerEnvironment.company);
        return;
      }
      if (savedMode == 'local') {
        _applyState(mode: ServerEnvironment.local);
        return;
      }
      if (savedMode == 'auto') {
        _applyState(mode: ServerEnvironment.auto, resolvedOverride: activeBaseUrl);
        if (autoProbe) {
          await resolveBestBackend(forceProbe: forceProbe, client: probeClient);
        }
        return;
      }

      // Migrate legacy `regen_custom_backend_url` if explicitly set by user previously
      final legacy = prefs.getString(_prefLegacyCustomUrlKey);
      if (legacy != null && legacy.trim().isNotEmpty) {
        if (isCompanyHostUrl(legacy)) {
          _applyState(mode: ServerEnvironment.company);
        } else {
          _applyState(mode: ServerEnvironment.local, localUrl: legacy);
        }
        return;
      }
    } catch (_) {}

    _applyState(mode: _initialEnvironment(), localUrl: _initialLocalUrl());
    if (_serverEnvironment == ServerEnvironment.auto && autoProbe) {
      await resolveBestBackend(forceProbe: forceProbe, client: probeClient);
    }
  }

  /// Backward-compatible alias for [init].
  static Future<void> initCustomUrl({
    bool autoProbe = true,
    bool forceProbe = false,
    http.Client? probeClient,
  }) =>
      init(autoProbe: autoProbe, forceProbe: forceProbe, probeClient: probeClient);

  /// Ensures any initial/in-flight backend reachability probe in auto mode has
  /// settled before sending an authenticated or login request.
  static Future<String> ensureReadyForRequest({http.Client? client}) async {
    if (_serverEnvironment != ServerEnvironment.auto) {
      return activeBaseUrl;
    }
    if (_inFlightProbe != null) {
      return _inFlightProbe!;
    }
    if (_lastProbeAt == null) {
      return resolveBestBackend(forceProbe: false, client: client);
    }
    return activeBaseUrl;
  }

  /// Enable Automatic switching (probes local backend first, falls back to public domain).
  static Future<void> useAutoMode({String? localUrlOrIp, http.Client? probeClient}) async {
    if (localUrlOrIp != null && localUrlOrIp.trim().isNotEmpty) {
      _localServerUrl = normalizeLocalUrl(localUrlOrIp);
    }
    _applyState(mode: ServerEnvironment.auto);
    await _persistSelection();
    await resolveBestBackend(forceProbe: true, client: probeClient);
  }

  /// Pin and persist the deployed Company Server (`https://regen.krishub.in`).
  static Future<void> useCompanyServer() async {
    _applyState(mode: ServerEnvironment.company);
    await _persistSelection();
  }

  /// Pin and persist the Local Server (`http://<LAN_IP>:5006`).
  static Future<void> useLocalServer({String? localUrlOrIp}) async {
    final targetLocal =
        localUrlOrIp != null && localUrlOrIp.trim().isNotEmpty
            ? normalizeLocalUrl(localUrlOrIp)
            : _localServerUrl;
    _applyState(mode: ServerEnvironment.local, localUrl: targetLocal);
    await _persistSelection();
  }

  /// Save and activate either Company Server or Local Server from a URL string.
  static Future<void> setCustomUrl(String url) async {
    if (isCompanyHostUrl(url)) {
      await useCompanyServer();
    } else {
      await useLocalServer(localUrlOrIp: url);
    }
  }

  static Future<void> _persistSelection() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final modeStr = _serverEnvironment == ServerEnvironment.auto
          ? 'auto'
          : (_serverEnvironment == ServerEnvironment.company ? 'company' : 'local');
      await prefs.setString(_prefServerModeKey, modeStr);
      await prefs.setString(_prefLocalServerUrlKey, _localServerUrl);
      await prefs.setString(_prefLegacyCustomUrlKey, activeBaseUrl);
    } catch (_) {}
  }

  @visibleForTesting
  static Future<void> resetForTest({http.Client? probeClient}) async {
    _probeClientOverride = probeClient;
    _lastProbeAt = null;
    _inFlightProbe = null;
    _localServerUrl = defaultLocalServerUrl;
    _serverEnvironment = ServerEnvironment.auto;
    _setResolvedUrl(companyServerUrl);
  }

  // Endpoint routes
  static String get loginUrl => '$activeBaseUrl/api/auth/login';
  static String get healthUrl => '$activeBaseUrl/api/health';
  static String get profileUrl => '$activeBaseUrl/api/users/me';
}
