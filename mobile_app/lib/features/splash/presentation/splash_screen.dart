import 'package:flutter/material.dart';
import '../../../core/theme/celadon_colors.dart';

/// ReGen Mobile Splash Screen
///
/// Serves as the visual entry point of the app with an animated logo,
/// brand identity, and initialization status.
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

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    );

    _scaleAnimation = Tween<double>(begin: 0.88, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: Curves.easeOutBack,
      ),
    );

    _animController.forward();

    // Trigger completion callback if supplied
    if (widget.onInitializationComplete != null) {
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          widget.onInitializationComplete!();
        }
      });
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: CeladonColors.background,
      body: SafeArea(
        child: Stack(
          children: [
            // Subtle botanical background gradient circles
            Positioned(
              top: -80,
              right: -80,
              child: Container(
                width: 220,
                height: 220,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: CeladonColors.primaryContainer,
                ),
              ),
            ),
            Positioned(
              bottom: -60,
              left: -60,
              child: Container(
                width: 180,
                height: 180,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: CeladonColors.primaryContainer,
                ),
              ),
            ),

            // Main Centered Content
            Center(
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: ScaleTransition(
                  scale: _scaleAnimation,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // ReGen Logo Badge
                      Container(
                        width: 110,
                        height: 110,
                        decoration: BoxDecoration(
                          color: CeladonColors.surface,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: CeladonColors.border,
                            width: 1.5,
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x141B5E4B),
                              blurRadius: 20,
                              offset: Offset(0, 8),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(18),
                        child: Image.asset(
                          'assets/images/logo.png',
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) {
                            return const Icon(
                              Icons.spa_rounded,
                              size: 48,
                              color: CeladonColors.primary,
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 24),

                      // App Title
                      Text(
                        'ReGen',
                        style: theme.textTheme.displayMedium?.copyWith(
                          color: CeladonColors.primaryDark,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 6),

                      // App Subtitle / Tagline
                      Text(
                        'Workforce & Office Management System',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: CeladonColors.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 48),

                      // Loading indicator with celadon styling
                      const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            CeladonColors.primary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),

                      Text(
                        'Initializing workspace...',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: CeladonColors.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Version Footer
            Positioned(
              left: 0,
              right: 0,
              bottom: 24,
              child: Text(
                'v1.0.0 • ReGen Enterprise',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: CeladonColors.textMuted,
                  fontSize: 11,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
