import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/constellation_colors.dart';
import '../../../core/widgets/glass_panel.dart';
import '../../../domain/models/app_settings.dart';
import '../../providers/settings_providers.dart';

/// Ouvre la feuille de réglages (accent, thème, onboarding).
Future<void> showSettingsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (_) => const _SettingsSheet(),
  );
}

class _SettingsSheet extends ConsumerWidget {
  const _SettingsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsControllerProvider);
    final ctrl = ref.read(settingsControllerProvider.notifier);
    final text = Theme.of(context).textTheme;
    final c = context.colors;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: GlassPanel(
        tint: c.backgroundElevated.withValues(alpha: 0.82),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: c.starDim.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text('Réglages', style: text.headlineSmall),
            const SizedBox(height: 24),
            Text('ACCENT', style: text.labelSmall),
            const SizedBox(height: 12),
            Row(
              children: [
                for (final a in AccentChoice.values) ...[
                  _AccentSwatch(
                    accent: a,
                    selected: settings.accent == a,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      ctrl.setAccent(a);
                    },
                  ),
                  const SizedBox(width: 12),
                ],
              ],
            ),
            const SizedBox(height: 24),
            Text('APPARENCE', style: text.labelSmall),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<ThemePreference>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: ThemePreference.system,
                    label: Text('Système'),
                  ),
                  ButtonSegment(
                    value: ThemePreference.dark,
                    label: Text('Sombre'),
                  ),
                  ButtonSegment(
                    value: ThemePreference.light,
                    label: Text('Clair'),
                  ),
                ],
                selected: {settings.themePreference},
                onSelectionChanged: (s) {
                  HapticFeedback.selectionClick();
                  ctrl.setThemePreference(s.first);
                },
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.replay_rounded, color: c.accent),
              title: const Text('Revoir l\'introduction'),
              onTap: () {
                Navigator.of(context).pop();
                // La redirection du routeur ramène vers l'onboarding.
                ctrl.resetOnboarding();
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _AccentSwatch extends StatelessWidget {
  const _AccentSwatch({
    required this.accent,
    required this.selected,
    required this.onTap,
  });

  final AccentChoice accent;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = ConstellationColors.accentColor(
      accent,
      Theme.of(context).brightness,
    );
    final label = switch (accent) {
      AccentChoice.cyan => 'Cyan',
      AccentChoice.amber => 'Ambre',
    };
    return Semantics(
      selected: selected,
      button: true,
      label: 'Accent $label',
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: AppMotion.medium,
          curve: AppMotion.standard,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? color.withValues(alpha: 0.16)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadii.pill),
            border: Border.all(color: selected ? color : c.glassBorder),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.6),
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(label, style: Theme.of(context).textTheme.labelMedium),
            ],
          ),
        ),
      ),
    );
  }
}
