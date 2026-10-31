import 'dart:ui';
import 'package:flutter/material.dart';
import '../../../core/theme/celadon_colors.dart';
import '../../dashboard/presentation/dashboard_screen.dart';
import 'auth_controller.dart';

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
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Attached Corporate Dark Green Office Background with Subtle Photographic Bokeh Blur (sigma 5.5)
          Positioned.fill(
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 5.5, sigmaY: 5.5),
              child: Transform.scale(
                scale: 1.05,
                child: Image.asset(
                  'assets/images/corporate_office_dark.jpg',
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Image.asset(
                      'assets/images/office_auth_portrait.png',
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          Container(color: const Color(0xFF031A14)),
                    );
                  },
                ),
              ),
            ),
          ),

          // 2. Translucent Ambient Lighting Preservation (Preserves natural daylight warmth without dark muddy cast)
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xFF04100B).withValues(alpha: 0.12),
                    Colors.transparent,
                    const Color(0xFF020906).withValues(alpha: 0.30),
                  ],
                ),
              ),
            ),
          ),

          // 3. Foreground Scrollable Content
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ReGen Official Branding (Using existing ReGen logo asset and clean typography)
                      Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Image.asset(
                              'assets/images/logo.png',
                              height: 48,
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) =>
                                  const SizedBox.shrink(),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'ReGen',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.5,
                                color: Color(0xFFFFFFFF),
                                shadows: [
                                  Shadow(
                                    offset: Offset(0, 2),
                                    blurRadius: 8,
                                    color: Color(0x99000000),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),

                      // Subtitle (Bright High-Contrast Typography)
                      const Text(
                        'Sign in to continue',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFF1F5F9),
                          shadows: [
                            Shadow(
                              offset: Offset(0, 1),
                              blurRadius: 4,
                              color: Color(0x88000000),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 22),

                      // 4. Luminous Frosted Glassmorphism Container Card (Lighter, Premium Ambient Depth)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(28),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 22,
                              vertical: 24,
                            ),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  const Color(0xFF1A4032).withValues(alpha: 0.45),
                                  const Color(0xFF102D22).withValues(alpha: 0.52),
                                  const Color(0xFF081C15).withValues(alpha: 0.62),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(28),
                              border: Border.all(
                                color: const Color(0xFF34D399).withValues(alpha: 0.32),
                                width: 1.2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.22),
                                  blurRadius: 28,
                                  offset: const Offset(0, 12),
                                ),
                                BoxShadow(
                                  color: const Color(0xFF10B981).withValues(alpha: 0.10),
                                  blurRadius: 24,
                                  spreadRadius: -2,
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
                                        color: const Color(0xFF7F1D1D)
                                            .withValues(alpha: 0.85),
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                          color: const Color(0xFFF87171),
                                          width: 1,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(
                                            Icons.error_outline_rounded,
                                            size: 18,
                                            color: Colors.white,
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              _authController.errorMessage!,
                                              style: const TextStyle(
                                                fontSize: 12.5,
                                                color: Colors.white,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ),
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
                                        color: const Color(0xFFE2E8F0),
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
                                                activeColor: const Color(0xFF10B981),
                                                checkColor: const Color(0xFF031A14),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                ),
                                                side: BorderSide(
                                                  color: const Color(0xFF34D399)
                                                      .withValues(alpha: 0.9),
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
                                                  fontWeight: FontWeight.w600,
                                                  color: Color(0xFFF1F5F9),
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
                                            color: Color(0xFF34D399),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 22),

                                  // Premium Radiant Emerald Login Pill Button
                                  Container(
                                    width: double.infinity,
                                    height: 52,
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [
                                          Color(0xFF10B981),
                                          Color(0xFF059669),
                                        ],
                                      ),
                                      borderRadius: BorderRadius.circular(26),
                                      boxShadow: [
                                        BoxShadow(
                                          color: const Color(0xFF10B981)
                                              .withValues(alpha: 0.40),
                                          blurRadius: 18,
                                          offset: const Offset(0, 6),
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
                                              BorderRadius.circular(26),
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
                                  const SizedBox(height: 24),

                                  // Divider: "or continue with"
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Container(
                                          height: 1,
                                          color: const Color(0xFFCBD5E1)
                                              .withValues(alpha: 0.25),
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 14),
                                        child: Text(
                                          'or continue with',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: const Color(0xFFE2E8F0)
                                                .withValues(alpha: 0.85),
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        child: Container(
                                          height: 1,
                                          color: const Color(0xFFCBD5E1)
                                              .withValues(alpha: 0.25),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 18),

                                  // Social SSO Buttons (Circular White Badges matching reference)
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
                                    children: [
                                      _buildCircularSocialButton(
                                        icon: const _GoogleIcon(),
                                        onTap: () =>
                                            _showSocialNotice('Google'),
                                      ),
                                      const SizedBox(width: 20),
                                      _buildCircularSocialButton(
                                        icon: const Icon(
                                          Icons.apple,
                                          size: 26,
                                          color: Colors.black87,
                                        ),
                                        onTap: () =>
                                            _showSocialNotice('Apple ID'),
                                      ),
                                      const SizedBox(width: 20),
                                      _buildCircularSocialButton(
                                        icon: const _MicrosoftIcon(),
                                        onTap: () =>
                                            _showSocialNotice('Microsoft 365'),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 22),

                                  // Sign Up Prompt
                                  Wrap(
                                    alignment: WrapAlignment.center,
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    children: [
                                      Text(
                                        "Don't have an account? ",
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                          color: const Color(0xFFE2E8F0)
                                              .withValues(alpha: 0.90),
                                        ),
                                      ),
                                      GestureDetector(
                                        onTap: () {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                  'Employee accounts are provisioned by your company administrator.'),
                                              backgroundColor:
                                                  CeladonColors.primary,
                                            ),
                                          );
                                        },
                                        child: const Text(
                                          'Sign Up',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF34D399),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
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
        ],
      ),
    );
  }

  void _showSocialNotice(String provider) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$provider single sign-on is enabled for enterprise accounts.'),
        backgroundColor: CeladonColors.primary,
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
        color: const Color(0xFF092017).withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF34D399).withValues(alpha: 0.30),
          width: 1.2,
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
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: Colors.transparent,
          hintText: hintText,
          hintStyle: const TextStyle(
            fontSize: 14,
            color: Color(0xFFCBD5E1),
            fontWeight: FontWeight.w400,
          ),
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 14, right: 10),
            child: Icon(
              prefixIcon,
              size: 20,
              color: const Color(0xFF6EE7B7),
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

  Widget _buildCircularSocialButton({
    required Widget icon,
    required VoidCallback onTap,
  }) {
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: const [
          BoxShadow(
            color: Color(0x24000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Center(child: icon),
        ),
      ),
    );
  }
}

/// Custom colored Google "G" icon
class _GoogleIcon extends StatelessWidget {
  const _GoogleIcon();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 22,
      height: 22,
      child: Center(
        child: Text(
          'G',
          style: TextStyle(
            fontFamily: 'sans-serif',
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: Color(0xFFEA4335),
          ),
        ),
      ),
    );
  }
}

/// Custom 4-quadrant Microsoft icon
class _MicrosoftIcon extends StatelessWidget {
  const _MicrosoftIcon();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: 20,
      child: GridView.count(
        crossAxisCount: 2,
        crossAxisSpacing: 2.5,
        mainAxisSpacing: 2.5,
        physics: const NeverScrollableScrollPhysics(),
        children: const [
          ColoredBox(color: Color(0xFFF25022)),
          ColoredBox(color: Color(0xFF7FBA00)),
          ColoredBox(color: Color(0xFF00A4EF)),
          ColoredBox(color: Color(0xFFFFB900)),
        ],
      ),
    );
  }
}
