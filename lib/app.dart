import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'presentation/providers/settings_providers.dart';

/// Racine de l'application : thème (accent + luminosité) et routeur.
class Sary360App extends ConsumerWidget {
  const Sary360App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = ref.watch(
      settingsControllerProvider.select((s) => s.accent),
    );
    return MaterialApp.router(
      title: 'Sary360',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(accent),
      darkTheme: AppTheme.dark(accent),
      themeMode: ref.watch(themeModeProvider),
      themeAnimationDuration: AppMotion.slow,
      routerConfig: ref.watch(appRouterProvider),
    );
  }
}
