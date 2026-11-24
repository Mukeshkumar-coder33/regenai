import 'package:flutter/material.dart';
import '../../../core/theme/celadon_colors.dart';
import '../../../core/widgets/brand_logo.dart';
import '../../dashboard/presentation/dashboard_screen.dart';
import 'auth_controller.dart';
import '../../../app/app_config.dart';

/// ReGen Premium Emerald-Green Glassmorphism Login Screen
///
/// Faithfully reproduces the new modern office glassmorphism visual design:
/// - Photorealistic executive office desk, desktop monitor, window daylight background
/// - Sophisticated dark emerald & forest green glassmorphism container
/// - BackdropFilter with subtle blur, translucent gradient surface, thin border, and soft drop shadow
/// - ReGen glowing emblem, bold white brand typography, and "Sign in to continue"
/// - Translucent dark input fields with clear icons and crisp white/mint labels
/// - Mint green checkbox and "Forgot Password?" action
/// - Vibrant emerald-mint pill action button: "Login ->"
/// - Clean "or continue with" divider and white circular social SSO badges (Google, Apple, Microsoft)
/// - "Don't have an account? Sign Up" footer
/// - Full connection to the Node.js/Express dual-sync backend
class LoginScreen extends StatefulWidget {
  final AuthController? controller;

  const LoginScreen({super.key, this.controller});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  late final AuthController _authController;
  bool _obscurePassword = true;
  bool _rememberMe = true;

  @override
  void initState() {
    super.initState();
    AppConfig.initCustomUrl().then((_) {
      if (mounted) setState(() {});
    });
    _authController = widget.controller ?? AuthController();
    _authController.addListener(_onAuthStateChanged);
  }

  void _onAuthStateChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _authController.removeListener(_onAuthStateChanged);
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    _authController.clearError();

    if (!_formKey.currentState!.validate()) {
      return;
    }

    final success = await _authController.login(
      username: _usernameController.text.trim(),
      password: _passwordController.text,
      portal: 'company',
    );

    if (success && mounted) {
      final user = _authController.currentUser!;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => DashboardScreen(
            key: ValueKey('dashboard_${user.userId}_${user.role}'),
            user: user,
            onLogout: () async {
              await _authController.logout();
            },
          ),
        ),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CeladonColors.background,
      body: CustomPaint(
        painter: const _LoginWaveBackgroundPainter(),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ReGen Official Branding (Screen 2 Exact Match)
                    Center(
                      child: GestureDetector(
                        onLongPress: _showServerUrlDialog,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            BrandLogo(size: 76, borderRadius: 22),
                            SizedBox(height: 14),
                            Text(
                              'ReGen',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.5,
                                color: CeladonColors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),

                    // Subtitle
                    const Text(
                      'Sign in to continue',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w500,
                        color: CeladonColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 22),

                    // Surface Card Container
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 24,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFFFF),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: CeladonColors.border,
                          width: 1.0,
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x100D1F17),
                            blurRadius: 24,
                            offset: Offset(0, 8),
                          ),
                        ],
                      ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Error Banner
                          if (_authController.errorMessage != null) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEF2F2),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: const Color(0xFFDC4C4C),
                                  width: 1.0,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Padding(
                                        padding: EdgeInsets.only(top: 2),
                                        child: Icon(
                                          Icons.error_outline_rounded,
                                          size: 18,
                                          color: Color(0xFFDC4C4C),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          _authController.errorMessage!,
                                          style: const TextStyle(
                                            fontSize: 12.5,
                                            color: Color(0xFFDC4C4C),
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (_authController.errorMessage!.contains('Cannot reach ReGen server') ||
                                      _authController.errorMessage!.contains('SocketException') ||
                                      _authController.errorMessage!.contains('192.168.')) ...[
                                    const SizedBox(height: 8),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: InkWell(
                                        onTap: _showServerUrlDialog,
                                        borderRadius: BorderRadius.circular(8),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                          decoration: BoxDecoration(
                                            color: CeladonColors.primaryLight,
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(color: CeladonColors.primary.withValues(alpha: 0.3)),
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.settings_ethernet_rounded, size: 15, color: CeladonColors.primary),
                                              SizedBox(width: 6),
                                              Text(
                                                'Configure Server IP',
                                                style: TextStyle(
                                                  fontSize: 11.5,
                                                  fontWeight: FontWeight.w700,
                                                  color: CeladonColors.primary,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],

                          // Email / Username Input Field
                          _buildGlassTextField(
                            controller: _usernameController,
                            hintText: 'Email',
                            prefixIcon: Icons.mail_outline_rounded,
                            textInputAction: TextInputAction.next,
                            enabled: !_authController.isLoading,
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Please enter your email or username';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),

                          // Password Input Field
                          _buildGlassTextField(
                            controller: _passwordController,
                            hintText: 'Password',
                            prefixIcon: Icons.lock_outline_rounded,
                            obscureText: _obscurePassword,
                            textInputAction: TextInputAction.done,
                            enabled: !_authController.isLoading,
                            onSubmitted: (_) => _handleLogin(),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                size: 20,
                                color: CeladonColors.textMuted,
                              ),
                              onPressed: () {
                                setState(() {
                                  _obscurePassword = !_obscurePassword;
                                });
                              },
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter your password';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 14),

                          // Remember Me & Forgot Password Row
                          Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                            children: [
                              Flexible(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: Checkbox(
                                        value: _rememberMe,
                                        activeColor: CeladonColors.primary,
                                        checkColor: Colors.white,
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        side: const BorderSide(
                                          color: CeladonColors.border,
                                          width: 1.4,
                                        ),
                                        onChanged: (val) {
                                          setState(() =>
                                              _rememberMe = val ?? true);
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 7),
                                    const Flexible(
                                      child: Text(
                                        'Remember me',
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w500,
                                          color: CeladonColors.textSecondary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),
                              TextButton(
                                onPressed: () {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                          'Please contact your company administrator to reset credentials.'),
                                      backgroundColor:
                                          CeladonColors.primary,
                                    ),
                                  );
                                },
                                style: TextButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: const Text(
                                  'Forgot Password?',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: CeladonColors.primary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 22),

                          // Primary Emerald Login Button
                          Container(
                            width: double.infinity,
                            height: 52,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                                colors: CeladonColors.primaryGradient,
                              ),
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x30075438),
                                  blurRadius: 14,
                                  offset: Offset(0, 5),
                                ),
                              ],
                            ),
                            child: ElevatedButton(
                              onPressed: _authController.isLoading
                                  ? null
                                  : _handleLogin,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                                shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(16),
                                ),
                                padding: EdgeInsets.zero,
                              ),
                              child: _authController.isLoading
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.4,
                                        color: Colors.white,
                                      ),
                                    )
                                  : Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: const [
                                        Text(
                                          'Login',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: 0.3,
                                            color: Colors.white,
                                          ),
                                        ),
                                        SizedBox(width: 8),
                                        Icon(
                                          Icons.arrow_forward_rounded,
                                          size: 19,
                                          color: Colors.white,
                                        ),
                                      ],
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
          ),
        ),
      ),
    );
  }

  Widget _buildGlassTextField({
    required TextEditingController controller,
    required String hintText,
    required IconData prefixIcon,
    bool obscureText = false,
    bool enabled = true,
    TextInputAction? textInputAction,
    Widget? suffixIcon,
    void Function(String)? onSubmitted,
    String? Function(String?)? validator,
  }) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: CeladonColors.inputBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: CeladonColors.border,
          width: 1.0,
        ),
      ),
      child: TextFormField(
        controller: controller,
        obscureText: obscureText,
        enabled: enabled,
        textInputAction: textInputAction,
        onFieldSubmitted: onSubmitted,
        validator: validator,
        style: const TextStyle(
          fontSize: 14.5,
          color: CeladonColors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: Colors.transparent,
          hintText: hintText,
          hintStyle: const TextStyle(
            fontSize: 14,
            color: CeladonColors.textPlaceholder,
            fontWeight: FontWeight.w400,
          ),
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 14, right: 10),
            child: Icon(
              prefixIcon,
              size: 20,
              color: CeladonColors.textMuted,
            ),
          ),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 44, minHeight: 44),
          suffixIcon: suffixIcon,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          errorBorder: InputBorder.none,
          focusedErrorBorder: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
        ),
      ),
    );
  }

  void _showServerUrlDialog() {
    final ctrl = TextEditingController(text: AppConfig.activeBaseUrl);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: CeladonColors.border),
        ),
        title: Row(
          children: const [
            Icon(Icons.dns_rounded, color: CeladonColors.primary, size: 20),
            SizedBox(width: 8),
            Text(
              'Server Configuration',
              style: TextStyle(color: CeladonColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Connect your mobile device to the ReGen backend API server:',
              style: TextStyle(color: CeladonColors.textMuted, fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              style: const TextStyle(color: CeladonColors.textPrimary, fontSize: 13),
              decoration: InputDecoration(
                filled: true,
                fillColor: CeladonColors.inputBackground,
                labelText: 'Backend Base URL',
                labelStyle: const TextStyle(color: CeladonColors.primary, fontSize: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
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
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _buildPresetUrlChip('Wi-Fi PC (192.168.1.37)', 'http://192.168.1.37:5006', ctrl),
                _buildPresetUrlChip('Wi-Fi PC (192.168.1.50)', 'http://192.168.1.50:5006', ctrl),
                _buildPresetUrlChip('Emulator (10.0.2.2)', 'http://10.0.2.2:5006', ctrl),
                _buildPresetUrlChip('Localhost', 'http://127.0.0.1:5006', ctrl),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: CeladonColors.textMuted)),
          ),
          ElevatedButton(
            onPressed: () async {
              final newUrl = ctrl.text.trim();
              if (newUrl.isNotEmpty) {
                await AppConfig.setCustomUrl(newUrl);
                if (mounted) setState(() {});
              }
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Server connected to ${AppConfig.activeBaseUrl}'),
                    backgroundColor: CeladonColors.primary,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: CeladonColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Save & Connect'),
          ),
        ],
      ),
    );
  }

  Widget _buildPresetUrlChip(String label, String url, TextEditingController ctrl) {
    return InkWell(
      onTap: () => ctrl.text = url,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFE8F3EC),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: CeladonColors.border),
        ),
        child: Text(label, style: const TextStyle(fontSize: 10, color: CeladonColors.primary, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

/// Flowing emerald wave curves and fine contour lines matching Screen 2
class _LoginWaveBackgroundPainter extends CustomPainter {
  const _LoginWaveBackgroundPainter();

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Top-Right Wave Ribbon
    final topPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: [
          Color(0xFF075438),
          Color(0xFF0B704C),
          Color(0xFF15803D),
        ],
      ).createShader(Rect.fromLTWH(size.width * 0.35, 0, size.width * 0.65, size.height * 0.32))
      ..style = PaintingStyle.fill;

    final topPath = Path()
      ..moveTo(size.width * 0.42, 0)
      ..quadraticBezierTo(
        size.width * 0.60,
        size.height * 0.07,
        size.width * 0.76,
        size.height * 0.10,
      )
      ..quadraticBezierTo(
        size.width * 0.90,
        size.height * 0.13,
        size.width,
        size.height * 0.22,
      )
      ..lineTo(size.width, 0)
      ..close();

    canvas.drawPath(topPath, topPaint);

    // Top-Right Contour Accent Lines
    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = const Color(0xFF096544).withValues(alpha: 0.18);

    for (int i = 0; i < 4; i++) {
      final linePath = Path()
        ..moveTo(size.width * (0.34 + i * 0.04), 0)
        ..quadraticBezierTo(
          size.width * (0.54 + i * 0.04),
          size.height * (0.06 + i * 0.02),
          size.width,
          size.height * (0.15 + i * 0.04),
        );
      canvas.drawPath(linePath, linePaint);
    }

    // 2. Bottom Wave Ribbon
    final bottomPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topRight,
        colors: [
          Color(0xFF075438),
          Color(0xFF0B704C),
          Color(0xFF15803D),
        ],
      ).createShader(Rect.fromLTWH(0, size.height * 0.72, size.width, size.height * 0.28))
      ..style = PaintingStyle.fill;

    final bottomPath = Path()
      ..moveTo(0, size.height * 0.92)
      ..quadraticBezierTo(
        size.width * 0.26,
        size.height * 0.94,
        size.width * 0.52,
        size.height * 0.88,
      )
      ..quadraticBezierTo(
        size.width * 0.78,
        size.height * 0.82,
        size.width,
        size.height * 0.78,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(bottomPath, bottomPaint);

    // Bottom Contour Accent Lines
    for (int i = 0; i < 4; i++) {
      final linePath = Path()
        ..moveTo(0, size.height * (0.86 - i * 0.025))
        ..quadraticBezierTo(
          size.width * 0.32,
          size.height * (0.88 - i * 0.025),
          size.width * 0.75,
          size.height * (0.75 - i * 0.03),
        );
      canvas.drawPath(linePath, linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
