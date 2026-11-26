import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../app/app_config.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/messenger/data/call_notification_service.dart';
import '../../features/messenger/data/messenger_service.dart';
import '../../features/messenger/data/messenger_socket_service.dart';
import '../../features/messenger/data/messenger_store.dart';
import '../../features/messenger/data/webrtc_call_manager.dart';
import '../storage/session_storage.dart';
import '../theme/celadon_colors.dart';

/// Result of pinging `<server>/api/health`.
class ServerHealthCheckResult {
  final bool isReachable;
  final String message;

  const ServerHealthCheckResult({
    required this.isReachable,
    required this.message,
  });
}

/// Verifies `/api/health` reachability on the candidate backend URL.
Future<ServerHealthCheckResult> checkReGenServerHealth(String baseUrl) async {
  final normalized = AppConfig.normalizeServerUrl(baseUrl);
  try {
    final response = await http
        .get(
          Uri.parse('$normalized/api/health'),
          headers: const {'Accept': 'application/json'},
        )
        .timeout(const Duration(seconds: 5));

    if (response.statusCode == 200) {
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          final mongoConnected = decoded['mongoConnected'] == true;
          return ServerHealthCheckResult(
            isReachable: true,
            message: mongoConnected
                ? 'Connected (API & Database online)'
                : 'Server reachable (Database connecting)',
          );
        }
      } catch (_) {}
      return const ServerHealthCheckResult(
        isReachable: true,
        message: 'Connected (Server online)',
      );
    }

    return ServerHealthCheckResult(
      isReachable: false,
      message: 'Server responded with HTTP ${response.statusCode}',
    );
  } catch (_) {
    return ServerHealthCheckResult(
      isReachable: false,
      message: 'Cannot reach $normalized',
    );
  }
}

/// Clears active session & Socket.IO state when switching servers while signed in.
Future<void> resetSessionForServerSwitch(
  BuildContext context, {
  VoidCallback? onAfterClear,
}) async {
  await WebRtcCallManager.instance.resetOnLogout();
  MessengerSocketService.instance.disconnect();
  MessengerStore.instance.reset();
  MessengerService.clearKeysCache();
  await CallNotificationService.instance.cancelAll();
  await SessionStorage.clearSession();
  try {
    onAfterClear?.call();
  } catch (_) {}
  if (context.mounted) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }
}

/// Shared modal dialog for choosing Company Server vs Local Server.
///
/// Reused by App Settings, Company Settings, and the Login screen so there is
/// one centralized server-switching UI and connection lifecycle.
Future<bool> showServerConnectionDialog(
  BuildContext context, {
  bool isAuthenticatedSession = false,
  VoidCallback? onSessionResetRequired,
}) async {
  var selectedMode = AppConfig.serverEnvironment;
  final localCtrl = TextEditingController(text: AppConfig.localHostOrIp);
  var isTesting = false;
  ServerHealthCheckResult? healthResult;

  String candidateUrl() {
    if (selectedMode == ServerEnvironment.company) {
      return AppConfig.companyServerUrl;
    }
    if (selectedMode == ServerEnvironment.local) {
      return AppConfig.normalizeLocalUrl(localCtrl.text);
    }
    return AppConfig.normalizeLocalUrl(localCtrl.text);
  }

  final saved = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (dialogCtx, setDialogState) {
        final targetUrl = candidateUrl();
        final willChangeActiveServer =
            selectedMode != ServerEnvironment.auto && targetUrl != AppConfig.activeBaseUrl;

        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: CeladonColors.border),
          ),
          title: const Row(
            children: [
              Icon(Icons.dns_rounded, color: CeladonColors.primary, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Server Connection',
                  style: TextStyle(
                    color: CeladonColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Select how ReGen connects to your backend server:',
                  style: TextStyle(color: CeladonColors.textMuted, fontSize: 12),
                ),
                const SizedBox(height: 12),
                _ServerOptionTile(
                  selected: selectedMode == ServerEnvironment.auto,
                  icon: Icons.auto_awesome_rounded,
                  title: 'Auto (Recommended)',
                  subtitle: 'Local Wi-Fi when reachable → Public Server fallback',
                  badge: 'AUTO',
                  onTap: () => setDialogState(() {
                    selectedMode = ServerEnvironment.auto;
                    healthResult = null;
                  }),
                ),
                const SizedBox(height: 8),
                _ServerOptionTile(
                  selected: selectedMode == ServerEnvironment.company,
                  icon: Icons.cloud_done_outlined,
                  title: 'Company Server',
                  subtitle: AppConfig.companyServerUrl,
                  badge: 'HTTPS',
                  onTap: () => setDialogState(() {
                    selectedMode = ServerEnvironment.company;
                    healthResult = null;
                  }),
                ),
                const SizedBox(height: 8),
                _ServerOptionTile(
                  selected: selectedMode == ServerEnvironment.local,
                  icon: Icons.lan_outlined,
                  title: 'Local Server',
                  subtitle: AppConfig.normalizeLocalUrl(localCtrl.text),
                  badge: 'LAN :${AppConfig.backendPort}',
                  onTap: () => setDialogState(() {
                    selectedMode = ServerEnvironment.local;
                    healthResult = null;
                  }),
                ),
                if (selectedMode == ServerEnvironment.local ||
                    selectedMode == ServerEnvironment.auto) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: localCtrl,
                    onChanged: (_) => setDialogState(() {
                      healthResult = null;
                    }),
                    style: const TextStyle(
                      color: CeladonColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: CeladonColors.inputBackground,
                      labelText: 'PC LAN IP or Local URL',
                      hintText: AppConfig.defaultLocalIp,
                      helperText:
                          'Default LAN: ${AppConfig.defaultLocalIp} (port ${AppConfig.backendPort} auto-added)',
                      helperStyle: const TextStyle(fontSize: 10.5),
                      labelStyle: const TextStyle(
                        color: CeladonColors.primary,
                        fontSize: 12,
                      ),
                      suffixIcon: IconButton(
                        tooltip: 'Use default LAN IP (${AppConfig.defaultLocalIp})',
                        icon: const Icon(
                          Icons.restart_alt_rounded,
                          size: 18,
                          color: CeladonColors.primary,
                        ),
                        onPressed: () => setDialogState(() {
                          localCtrl.text = AppConfig.defaultLocalIp;
                          healthResult = null;
                        }),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: CeladonColors.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: CeladonColors.primary),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: isTesting
                      ? null
                      : () async {
                          setDialogState(() {
                            isTesting = true;
                            healthResult = null;
                          });
                          final result = await checkReGenServerHealth(candidateUrl());
                          if (dialogCtx.mounted) {
                            setDialogState(() {
                              isTesting = false;
                              healthResult = result;
                            });
                          }
                        },
                  icon: isTesting
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: CeladonColors.primary,
                          ),
                        )
                      : const Icon(Icons.network_check_rounded, size: 16),
                  label: Text(
                    isTesting ? 'Checking Server...' : 'Test Connection',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: CeladonColors.primary,
                    side: const BorderSide(color: CeladonColors.border),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                if (healthResult != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: healthResult!.isReachable
                          ? const Color(0xFFECFDF3)
                          : const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: healthResult!.isReachable
                            ? CeladonColors.primary.withValues(alpha: 0.4)
                            : const Color(0xFFDC4C4C).withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          healthResult!.isReachable
                              ? Icons.check_circle_outline_rounded
                              : Icons.error_outline_rounded,
                          size: 16,
                          color: healthResult!.isReachable
                              ? CeladonColors.primary
                              : const Color(0xFFDC4C4C),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            healthResult!.message,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: healthResult!.isReachable
                                  ? CeladonColors.primaryDark
                                  : const Color(0xFFDC4C4C),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (isAuthenticatedSession && willChangeActiveServer) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFBEB),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.5)),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFFB45309)),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Switching servers signs out your current session so authentication and real-time updates reconnect on the new server.',
                            style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFF92400E),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text(
                'Cancel',
                style: TextStyle(color: CeladonColors.textMuted),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                final previousUrl = AppConfig.activeBaseUrl;
                if (selectedMode == ServerEnvironment.auto) {
                  await AppConfig.useAutoMode(localUrlOrIp: localCtrl.text);
                } else if (selectedMode == ServerEnvironment.company) {
                  await AppConfig.useCompanyServer();
                } else {
                  await AppConfig.useLocalServer(localUrlOrIp: localCtrl.text);
                }
                final switchedUrl = AppConfig.activeBaseUrl != previousUrl;
                if (ctx.mounted) Navigator.pop(ctx, true);

                if (switchedUrl && isAuthenticatedSession && context.mounted) {
                  if (onSessionResetRequired != null) {
                    MessengerSocketService.instance.disconnect();
                    onSessionResetRequired();
                  } else {
                    await resetSessionForServerSwitch(context);
                  }
                } else if (isAuthenticatedSession) {
                  await MessengerSocketService.instance.ensureConnected();
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: CeladonColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(
                isAuthenticatedSession && willChangeActiveServer
                    ? 'Switch & Sign In'
                    : 'Save Server',
              ),
            ),
          ],
        );
      },
    ),
  );

  localCtrl.dispose();
  return saved == true;
}

class _ServerOptionTile extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final String badge;
  final VoidCallback onTap;

  const _ServerOptionTile({
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFE8F3EC) : CeladonColors.inputBackground,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? CeladonColors.primary : CeladonColors.border,
            width: selected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
              size: 18,
              color: selected ? CeladonColors.primary : CeladonColors.textMuted,
            ),
            const SizedBox(width: 10),
            Icon(icon, size: 18, color: CeladonColors.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: CeladonColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: CeladonColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: CeladonColors.border),
              ),
              child: Text(
                badge,
                style: const TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  color: CeladonColors.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
