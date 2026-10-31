import 'package:flutter/material.dart';
import '../../../core/storage/session_storage.dart';
import '../../../core/theme/celadon_colors.dart';
import '../../../core/widgets/botanical_background.dart';
import '../../../core/widgets/brand_logo.dart';
import '../../auth/presentation/login_screen.dart';
import '../../dashboard/presentation/dashboard_screen.dart';

/// ReGen Premium Celadon Splash Screen
///
/// Matches Screen 1 of the official UI specification:
/// - Official ReGen brand emblem
/// - Subtitle: "Staff & Employee Management"
/// - Tagline: "People • Process • Performance"
/// - Bottom loading bar pill
class SplashScreen extends StatefulWidget {
  final VoidCallback? onInitializationComplete;

  const SplashScreen({super.key, this.onInitializationComplete});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _fadeAnimation;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _progressAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    );

    _scaleAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: Curves.easeOutBack,
      ),
    );

    _progressAnimation = Tween<double>(begin: 0.1, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: Curves.easeInOut,
      ),
    );

    _animController.forward();
    _checkInitialRoute();
  }

  Future<void> _checkInitialRoute() async {
    // Wait for the splash experience
    await Future.delayed(const Duration(milliseconds: 1800));

    if (!mounted) return;

    if (widget.onInitializationComplete != null) {
      widget.onInitializationComplete!();
      return;
    }

    final savedUser = await SessionStorage.getUserSession();

    if (!mounted) return;

    if (savedUser != null && savedUser.token.isNotEmpty) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => DashboardScreen(
            user: savedUser,
            onLogout: () async {
              await SessionStorage.clearSession();
            },
          ),
        ),
        (route) => false,
      );
    } else {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BotanicalBackground(
        showLeaves: true,
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const SizedBox(height: 40),

              // Center Logo & Brand Identity
              Center(
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: ScaleTransition(
                    scale: _scaleAnimation,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Official ReGen Logo
                        const BrandLogo(
                          size: 110,
                          borderRadius: 28,
                          backgroundColor: CeladonColors.primaryDark,
                        ),
                        const SizedBox(height: 18),

                        // Title: ReGen
                        const Text(
                          'ReGen',
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                            color: CeladonColors.primaryDark,
                          ),
                        ),
                        const SizedBox(height: 8),

                        // Subtitle matching reference: "Staff & Employee Management"
                        const Text(
                          'Staff & Employee\nManagement',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: CeladonColors.textSecondary,
                            height: 1.35,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Bottom Section: Tagline & Progress Bar
              Padding(
                padding: const EdgeInsets.only(bottom: 32),
                child: Column(
                  children: [
                    const Text(
                      'People\nProcess\nPerformance',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: CeladonColors.textSecondary,
                        letterSpacing: 0.4,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Thin loading bar pill matching reference
                    AnimatedBuilder(
                      animation: _progressAnimation,
                      builder: (context, child) {
                        return Container(
                          width: 120,
                          height: 4,
                          decoration: BoxDecoration(
                            color: CeladonColors.border,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          alignment: Alignment.centerLeft,
                          child: Container(
                            width: 120 * _progressAnimation.value,
                            height: 4,
                            decoration: BoxDecoration(
                              color: CeladonColors.primary,
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
