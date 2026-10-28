import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../theme/celadon_colors.dart';

/// Virtual Device Simulator for Web & Desktop Preview
///
/// When running in Chrome on a desktop screen, this widget wraps the
/// application inside an authentic smartphone chassis (390 x 844 px)
/// complete with curved corners, dynamic island, status bar, and shadows.
///
/// On mobile devices or narrow browser windows, it seamlessly renders
/// full-screen with no frame.
class VirtualDeviceFrame extends StatefulWidget {
  final Widget child;

  const VirtualDeviceFrame({super.key, required this.child});

  @override
  State<VirtualDeviceFrame> createState() => _VirtualDeviceFrameState();
}

class _VirtualDeviceFrameState extends State<VirtualDeviceFrame> {
  bool _enableFrame = true;

  @override
  Widget build(BuildContext context) {
    // On native mobile platforms (Android / iOS), always render full-screen natively
    if (!kIsWeb) {
      return widget.child;
    }

    // On Web / Desktop, only show virtual phone chassis when screen is wider than a phone
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    final isWideScreen = screenWidth > 500 && (kIsWeb || screenWidth > screenHeight);

    if (!isWideScreen || !_enableFrame) {
      return widget.child;
    }

    return Scaffold(
      backgroundColor: const Color(0xFFE5EDE8),
      body: Stack(
        children: [
          // Background ambient circles
          Positioned(
            top: -100,
            left: -100,
            child: Container(
              width: 350,
              height: 350,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFFD4E7DC),
              ),
            ),
          ),
          Positioned(
            bottom: -100,
            right: -100,
            child: Container(
              width: 400,
              height: 400,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFFDCEFE5),
              ),
            ),
          ),

          // Top control bar
          Positioned(
            top: 14,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: CeladonColors.border),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x0C000000),
                      blurRadius: 12,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.phone_android_rounded,
                      size: 18,
                      color: CeladonColors.primary,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'ReGen Virtual Device (390 × 844)',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: CeladonColors.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 14),
                    InkWell(
                      onTap: () => setState(() => _enableFrame = !_enableFrame),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: CeladonColors.primaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          'Full Screen',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: CeladonColors.primaryDark,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Centered Phone Chassis
          Center(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 40),
              width: 390,
              height: 844,
              decoration: BoxDecoration(
                color: const Color(0xFF1E2623), // Dark Titanium frame
                borderRadius: BorderRadius.circular(52),
                border: Border.all(
                  color: const Color(0xFF2C3A35),
                  width: 3.5,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x38000000),
                    blurRadius: 40,
                    spreadRadius: 4,
                    offset: Offset(0, 18),
                  ),
                  BoxShadow(
                    color: Color(0x1E1B5E4B),
                    blurRadius: 60,
                    spreadRadius: 8,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(10),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(42),
                child: Stack(
                  children: [
                    // The Real App
                    Positioned.fill(child: widget.child),

                    // Top Dynamic Island & Status Bar
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        height: 38,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              '9:41',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: CeladonColors.textPrimary,
                              ),
                            ),
                            // Dynamic Island
                            Container(
                              width: 100,
                              height: 22,
                              decoration: BoxDecoration(
                                color: Colors.black,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Container(
                                    margin: const EdgeInsets.only(right: 10),
                                    width: 8,
                                    height: 8,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF112218),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Row(
                              children: [
                                Icon(Icons.signal_cellular_4_bar_rounded,
                                    size: 13, color: CeladonColors.textPrimary),
                                SizedBox(width: 4),
                                Icon(Icons.wifi_rounded,
                                    size: 14, color: CeladonColors.textPrimary),
                                SizedBox(width: 4),
                                Icon(Icons.battery_5_bar_rounded,
                                    size: 14, color: CeladonColors.textPrimary),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Bottom Home Indicator Bar
                    Positioned(
                      bottom: 6,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          width: 130,
                          height: 4.5,
                          decoration: BoxDecoration(
                            color: CeladonColors.textPrimary.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
