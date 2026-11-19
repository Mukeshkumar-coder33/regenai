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

  /// Displays a dedicated, professional appearance customization sheet allowing
  /// users to customize and reorder their bottom navigation bar pages from
  /// Settings -> Appearance.
  static Future<void> showAppearanceCustomizerSheet({
    required BuildContext context,
    required String roleKey,
    required List<NavShortcutItem> catalog,
    required List<String> currentSlots,
    required List<String> defaultSlots,
    required void Function(List<String> updatedSlots) onSlotsChanged,
  }) async {
    NavShortcutItem shortcutForId(String id) {
      return catalog.firstWhere(
        (e) => e.id == id,
        orElse: () => NavShortcutItem(
          id: id,
          label: id,
          icon: Icons.circle_outlined,
          activeIcon: Icons.circle,
        ),
      );
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final activeSlots = List<String>.from(currentSlots);
            final activeSet = activeSlots.toSet();

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: const Color(0xFFCBD5E1),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: CeladonColors.primaryContainer,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.palette_outlined,
                            color: CeladonColors.primary,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Customize Navigation Bar',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                  color: CeladonColors.textPrimary,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Choose which pages appear in your bottom navigation bar',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: CeladonColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 20, color: Color(0xFF64748B)),
                          onPressed: () => Navigator.pop(sheetContext),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'ACTIVE SHORTCUTS',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF64748B),
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: activeSlots.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, slotIndex) {
                          final currentId = activeSlots[slotIndex];
                          final item = shortcutForId(currentId);
                          final available = catalog
                              .where((c) => !activeSet.contains(c.id))
                              .toList();

                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 26,
                                  height: 26,
                                  decoration: BoxDecoration(
                                    color: CeladonColors.primary.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(7),
                                  ),
                                  child: Center(
                                    child: Text(
                                      '${slotIndex + 1}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                        color: CeladonColors.primary,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Icon(item.icon, size: 20, color: CeladonColors.textPrimary),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    item.label,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: CeladonColors.textPrimary,
                                    ),
                                  ),
                                ),
                                if (available.isNotEmpty)
                                  InkWell(
                                    onTap: () async {
                                      final selected = await _showPageSelectionDialog(
                                        context: context,
                                        currentLabel: item.label,
                                        availableItems: available,
                                      );
                                      if (selected != null && selected != currentId) {
                                        activeSlots[slotIndex] = selected;
                                        await saveSlots(roleKey: roleKey, slots: activeSlots);
                                        currentSlots[slotIndex] = selected;
                                        onSlotsChanged(List<String>.from(activeSlots));
                                        setSheetState(() {});
                                      }
                                    },
                                    borderRadius: BorderRadius.circular(8),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: CeladonColors.softMint,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: CeladonColors.primary.withValues(alpha: 0.2)),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.swap_horiz_rounded,
                                            size: 14,
                                            color: CeladonColors.primary,
                                          ),
                                          SizedBox(width: 4),
                                          Text(
                                            'Change',
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
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton.icon(
                          onPressed: () async {
                            final reset = List<String>.from(defaultSlots);
                            await saveSlots(roleKey: roleKey, slots: reset);
                            currentSlots
                              ..clear()
                              ..addAll(reset);
                            onSlotsChanged(reset);
                            setSheetState(() {});
                          },
                          icon: const Icon(Icons.refresh_rounded, size: 16, color: Color(0xFF64748B)),
                          label: const Text(
                            'Reset to Defaults',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(sheetContext),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: CeladonColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 0,
                          ),
                          child: const Text('Done', style: TextStyle(fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  static Future<String?> _showPageSelectionDialog({
    required BuildContext context,
    required String currentLabel,
    required List<NavShortcutItem> availableItems,
  }) async {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFCBD5E1),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Replace "$currentLabel" with',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: CeladonColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: availableItems.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (_, i) {
                      final item = availableItems[i];
                      return ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                        tileColor: const Color(0xFFF8FAFC),
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: CeladonColors.primaryContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(item.icon, size: 18, color: CeladonColors.primary),
                        ),
                        title: Text(
                          item.label,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: CeladonColors.textPrimary,
                          ),
                        ),
                        trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Color(0xFF94A3B8)),
                        onTap: () => Navigator.pop(ctx, item.id),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

