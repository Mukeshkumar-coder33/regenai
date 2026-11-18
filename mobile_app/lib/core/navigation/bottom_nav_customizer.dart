import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/celadon_colors.dart';

/// Immutable descriptor for a bottom-navigation / menu destination.
class NavShortcutItem {
  final String id;
  final String label;
  final IconData icon;
  final IconData activeIcon;

  const NavShortcutItem({
    required this.id,
    required this.label,
    required this.icon,
    required this.activeIcon,
  });
}

/// Role-isolated persistence and contextual replacement menu for long-press
/// bottom navigation customization.
class BottomNavCustomizer {
  static String _storageKey(String roleKey) => 'regen_bottom_nav_slots_$roleKey';

  /// Loads persisted bottom navigation slot IDs for [roleKey], sanitizing
  /// against [validIds] and guaranteeing exact length & uniqueness.
  static Future<List<String>> loadSlots({
    required String roleKey,
    required List<String> defaults,
    required Set<String> validIds,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList(_storageKey(roleKey));
      if (saved == null || saved.length != defaults.length) {
        return List<String>.from(defaults);
      }
      final seen = <String>{};
      final cleaned = <String>[];
      for (final id in saved) {
        if (validIds.contains(id) && seen.add(id)) {
          cleaned.add(id);
        }
      }
      if (cleaned.length != defaults.length) {
        return List<String>.from(defaults);
      }
      return cleaned;
    } catch (_) {
      return List<String>.from(defaults);
    }
  }

  /// Persists the customized bottom navigation slot IDs independently per role.
  static Future<void> saveSlots({
    required String roleKey,
    required List<String> slots,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_storageKey(roleKey), slots);
    } catch (_) {
      // Ignore storage errors in ephemeral environments
    }
  }

  /// Displays a compact contextual menu anchored near the long-pressed bottom
  /// navigation icon containing ONLY eligible replacement pages not currently
  /// displayed in the bottom navigation bar.
  static Future<String?> showReplacementMenu({
    required BuildContext context,
    required GlobalKey anchorKey,
    required String currentLabel,
    required List<NavShortcutItem> availableItems,
  }) async {
    if (availableItems.isEmpty) return null;

    final overlayBox =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    final itemBox =
        anchorKey.currentContext?.findRenderObject() as RenderBox?;

    RelativeRect position;
    if (overlayBox != null && itemBox != null) {
      final overlaySize = overlayBox.size;
      final topLeft = itemBox.localToGlobal(Offset.zero, ancestor: overlayBox);
      final bottomRight = itemBox.localToGlobal(
        itemBox.size.bottomRight(Offset.zero),
        ancestor: overlayBox,
      );
      position = RelativeRect.fromLTRB(
        topLeft.dx.clamp(8.0, (overlaySize.width - 200).clamp(8.0, overlaySize.width)),
        (topLeft.dy - 12).clamp(16.0, overlaySize.height),
        (overlaySize.width - bottomRight.dx).clamp(8.0, overlaySize.width),
        (overlaySize.height - topLeft.dy + 8).clamp(8.0, overlaySize.height),
      );
    } else {
      position = const RelativeRect.fromLTRB(24, 240, 24, 80);
    }

    return showMenu<String>(
      context: context,
      position: position,
      elevation: 10,
      color: CeladonColors.cardBackground,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: CeladonColors.border, width: 1.0),
      ),
      items: <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          enabled: false,
          height: 34,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.swap_horiz_rounded,
                size: 15,
                color: CeladonColors.primary,
              ),
              const SizedBox(width: 6),
              Text(
                'Replace "$currentLabel"',
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: CeladonColors.textSecondary,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(height: 1),
        ...availableItems.map(
          (item) => PopupMenuItem<String>(
            value: item.id,
            height: 44,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  item.icon,
                  size: 19,
                  color: CeladonColors.primary,
                ),
                const SizedBox(width: 10),
                Text(
                  item.label,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: CeladonColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

