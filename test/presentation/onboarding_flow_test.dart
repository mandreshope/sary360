import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sary360/app.dart';
import 'package:sary360/core/theme/app_theme.dart';
import 'package:sary360/presentation/providers/settings_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Les animations tournent en boucle : on avance le temps par paliers
/// plutôt que d'attendre `pumpAndSettle` (qui ne terminerait jamais).
Future<void> _advance(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<SharedPreferences> _pumpApp(
  WidgetTester tester,
  Map<String, Object> initial,
) async {
  // Surface d'un téléphone courant (393 × 851 dp).
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues(initial);
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const Sary360App(),
    ),
  );
  await _advance(tester);
  return prefs;
}

void main() {
  setUpAll(() => AppTheme.useGoogleFonts = false);

  testWidgets('premier lancement : onboarding puis accueil', (tester) async {
    final prefs = await _pumpApp(tester, {});

    expect(find.text('Tournez sur\nvous-même'), findsOneWidget);

    await tester.tap(find.text('Suivant'));
    await _advance(tester);
    expect(find.text('Le téléphone\nreste au centre'), findsOneWidget);

    await tester.tap(find.text('Suivant'));
    await _advance(tester);
    expect(find.text('Commencer'), findsOneWidget);

    await tester.tap(find.text('Commencer'));
    await _advance(tester);

    expect(find.text('Nouvelle sphère'), findsOneWidget);
    expect(prefs.getBool('settings.onboardingCompleted'), isTrue);
  });

  testWidgets('« Passer » mène directement à l\'accueil', (tester) async {
    await _pumpApp(tester, {});

    await tester.tap(find.text('Passer'));
    await _advance(tester);

    expect(find.text('Nouvelle sphère'), findsOneWidget);
  });

  testWidgets('onboarding déjà vu : démarrage sur l\'accueil', (tester) async {
    await _pumpApp(tester, {'settings.onboardingCompleted': true});

    expect(find.text('Nouvelle sphère'), findsOneWidget);
    expect(find.text('Passer'), findsNothing);
  });

  testWidgets('le changement d\'accent est persisté', (tester) async {
    final prefs = await _pumpApp(tester, {
      'settings.onboardingCompleted': true,
    });

    await tester.tap(find.byTooltip('Réglages'));
    await _advance(tester);
    await tester.tap(find.text('Ambre'));
    await _advance(tester);

    expect(prefs.getString('settings.accent'), 'amber');
  });
}
