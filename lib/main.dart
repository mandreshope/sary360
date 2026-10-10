import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'presentation/providers/settings_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Portrait uniquement : la capture repose sur l'orientation du capteur.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // Affichage bord à bord : le fond étoilé passe sous les barres système.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
    ),
  );

  // MIT notice of the bundled MI-GAN model (shown in the licenses page).
  LicenseRegistry.addLicense(() async* {
    final text = await rootBundle.loadString('assets/models/MIGAN_LICENSE.txt');
    yield LicenseEntryWithLineBreaks(const ['MI-GAN'], text);
  });

  // Les réglages sont lus avant le premier frame pour décider de la route
  // initiale (onboarding ou accueil) sans clignotement.
  final prefs = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const Sary360App(),
    ),
  );
}
