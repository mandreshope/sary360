import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/models/panorama.dart';
import '../../presentation/pages/capture_page.dart';
import '../../presentation/pages/gallery_page.dart';
import '../../presentation/pages/home_page.dart';
import '../../presentation/pages/onboarding/onboarding_page.dart';
import '../../presentation/pages/viewer_page.dart';
import '../../presentation/providers/settings_providers.dart';
import '../theme/app_theme.dart';
import 'app_routes.dart';

/// Routeur de l'application.
///
/// Le routeur est créé une seule fois ; les changements de l'état
/// « onboarding terminé » déclenchent uniquement une réévaluation de la
/// redirection via [refreshListenable].
final appRouterProvider = Provider<GoRouter>((ref) {
  final onboardingDone = ValueNotifier<bool>(
    ref.read(settingsControllerProvider).onboardingCompleted,
  );
  ref.listen(
    settingsControllerProvider.select((s) => s.onboardingCompleted),
    (_, next) => onboardingDone.value = next,
  );

  final router = GoRouter(
    initialLocation: AppRoutes.home,
    refreshListenable: onboardingDone,
    redirect: (context, state) {
      final atOnboarding = state.matchedLocation == AppRoutes.onboarding;
      if (!onboardingDone.value && !atOnboarding) return AppRoutes.onboarding;
      if (onboardingDone.value && atOnboarding) return AppRoutes.home;
      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.onboarding,
        pageBuilder: (context, state) =>
            _fadePage(state, const OnboardingPage()),
      ),
      GoRoute(
        path: AppRoutes.home,
        pageBuilder: (context, state) => _fadePage(state, const HomePage()),
      ),
      GoRoute(
        path: AppRoutes.capture,
        builder: (context, state) => const CapturePage(),
      ),
      GoRoute(
        path: AppRoutes.gallery,
        builder: (context, state) => const GalleryPage(),
      ),
      GoRoute(
        path: AppRoutes.viewer,
        redirect: (context, state) =>
            state.extra is Panorama ? null : AppRoutes.gallery,
        builder: (context, state) =>
            ViewerPage(panorama: state.extra! as Panorama),
      ),
    ],
  );

  ref.onDispose(() {
    router.dispose();
    onboardingDone.dispose();
  });
  return router;
});

/// Transition en fondu enchaîné, utilisée entre onboarding et accueil.
CustomTransitionPage<void> _fadePage(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: AppMotion.slow,
    transitionsBuilder: (context, animation, _, child) => FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: AppMotion.standard),
      child: child,
    ),
  );
}
