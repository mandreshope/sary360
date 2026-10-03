# Sary360

Application Flutter de capture de **photos sphériques 360°** (type « Photo
Sphere ») : l'utilisateur tourne sur lui-même, l'app déclenche une photo à
chaque cible de la sphère, puis un module C++ OpenCV assemble une image
équirectangulaire 2:1 avec métadonnées XMP GPano. Thème visuel :
**« Constellation »** (capturer = compléter une carte du ciel).

Langue du projet : **français** (commentaires, textes de l'UI, échanges).
Messages de commit en anglais.

## Commandes

Flutter est fixé à **3.47.5** (`.fvmrc`, FVM).

```bash
flutter pub get
flutter analyze                 # doit rester à « No issues found! »
flutter test                    # tourne directement sur macOS
flutter build apk --debug       # compile aussi le module natif (3 ABI)
dart run ffigen --config ffigen.yaml   # après modification de sary_stitcher.h
```

Prérequis Android : NDK 28, CMake 3.22.1, **OpenCV Android SDK 4.13.0** dans
`third_party/OpenCV-android-sdk` (ignoré par git ; sinon `opencv.dir` dans
`android/local.properties` ou `OPENCV_ANDROID_SDK`). Procédure : README.

## Architecture

```
lib/
├── app.dart, main.dart          # MaterialApp.router, thème, ProviderScope
├── core/
│   ├── constants/               # AppConstants, CaptureGrid (grilles de cibles)
│   ├── math/                    # Vec3, Quaternion, CameraRotation (repères)
│   ├── router/                  # go_router (AppRoutes), redirection onboarding
│   ├── theme/                   # ConstellationColors (ThemeExtension), AppTheme
│   ├── utils/formatters.dart    # dates / tailles en français
│   └── widgets/                 # GlassPanel, StarfieldBackground, ConstellationOrb
├── domain/                      # modèles (CapturedPhoto, Panorama, AppSettings) + interfaces
├── data/
│   ├── native/                  # bindings FFI générés (ne pas éditer)
│   ├── repositories/            # réglages (SharedPreferences), sphères (fichiers)
│   └── services/                # caméra/capteurs, assemblage (isolate + FFI), export galerie
└── presentation/                # pages, viewmodels, providers Riverpod, widgets
native/stitcher/                 # module C++ : include/sary_stitcher.h, src/, tools/stitch_cli.cpp
tool/icon/                       # dessin de l'icône (voir skill regenerate-app-icon)
```

- État : **Riverpod** (`Notifier` pour le neuf ; `StateNotifier` subsiste dans
  `capture_viewmodel.dart`). Navigation : **go_router**, chemins dans `AppRoutes`.
- Visionneuse 360° : `presentation/widgets/custom_panorama.dart` (fork local
  de `panorama` sur `flutter_cube`).

## Conventions d'interface

- Couleurs : toujours via `context.colors` (`ConstellationColors`), jamais de
  couleur en dur. Rayons `AppRadii`, durées/courbes `AppMotion`.
- Surfaces flottantes : `GlassPanel` / `GlassIconButton`. Fonds : `StarfieldBackground`.
- Polices : Space Grotesk (titres) / Manrope (texte) via google_fonts ;
  `AppTheme.useGoogleFonts = false` dans les tests de widgets.
- La visionneuse force le thème sombre (commandes posées sur la photo), mais
  la feuille d'infos suit le thème de l'app.
- Animations en boucle : utiliser `pump(durée)` dans les tests, jamais
  `pumpAndSettle` (ne se termine pas).

## Module natif d'assemblage (native/stitcher)

Pipeline `cv::detail` appelé via FFI dans un isolate (`stitching_service.dart`) :
rotations des capteurs → ORB (seuil FAST 8, 3000 pts) sur les **voisines
uniquement** → `BundleAdjusterRay` **par composante reliée**, conservé seulement
s'il réduit l'écart des rayons appariés → auto-calibration de la focale →
priorité aux photos nettes → SphericalWarper, BlocksGain, GraphCut (0,05 Mpx),
MultiBand → remplissage flou des trous → JPEG, puis XMP côté Dart.

Points à connaître :
- `rotations` = caméra OpenCV (x droite, y bas, z visée) → monde OpenCV
  (y bas, z = centre du panorama). Conversions et tests : `core/math/camera_rotation.dart`.
- Progression / annulation via deux cellules de mémoire native partagées
  (adresses passées à l'isolate). Pas d'`enum` ni de `volatile` dans l'en-tête
  C (ffigen) : codes `int32_t` `SARY_*`.
- Journal Android : tag **`SaryStitcher`** (étapes, durées, groupes affinés) ;
  `SARY_DEBUG=1` (outil CLI) ajoute le détail par photo et par paire.
- Ultra grand angle du Pixel 6a : champ réel **≈ 53° × 83°** en portrait
  (correction de distorsion de l'appareil), pas 62° × 94°. Grille ultra grand
  angle : 26 cibles (10 / 7 / 7 / 1 / 1) ; objectif principal : 42.
- Le plugin `camera` ne capture qu'en **16:9** (tous les presets sont vidéo).

## Pièges rencontrés

- `Isolate.run(() => …)` dans une méthode d'instance capture tout le contexte
  (callbacks → ViewModel → CameraController non envoyable) : créer la closure
  dans une méthode **statique** qui ne voit que la requête.
- `ImageInfo` reçus d'un `ImageStream` : les libérer (`dispose`) et retirer la
  même instance d'écouteur ; sinon la visionneuse s'affichait en noir à la
  réouverture.
- `flutter_launcher_icons` remplace à tort
  `ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS` dans
  `ios/Runner.xcodeproj/project.pbxproj` : annuler ce changement.
- Shell zsh : `for f in $VAR` ne découpe pas la variable (utiliser `${=VAR}`).
- Fichiers de l'app sur l'appareil : `adb exec-out run-as com.mandreshope.sary360 cat <chemin>`
  (photos dans `cache/temp/`, sphères dans `app_flutter/panoramas/`).

## Façon de travailler

- **Ne pas installer ni lancer l'app sur le téléphone sans demande** :
  l'utilisateur teste lui-même. Lire les logs et fichiers de l'appareil
  (lecture seule) est accepté ; l'outil `stitch_cli` dans `/data/local/tmp`
  aussi, en nettoyant après.
- Commits uniquement sur demande, en commits thématiques, sur la branche de
  travail (pas `develop`). Style : `feat:` / `fix:` / `enhance:` / `chore:` +
  résumé anglais, puis la ligne `Co-Authored-By`.
- `DOCUMENTATION.md`, `QUICK_START.md` et `ANDROID_SETUP.md` sont **obsolètes**
  (avant la refonte) ; le README est à jour pour l'installation et le module natif.

## Avancement (cahier des charges en 7 étapes)

1. ✅ Structure, thème, navigation, onboarding.
2. ⏳ Platform channel `TYPE_ROTATION_VECTOR` (Kotlin) + écran de capture
   « constellation » — l'orientation vient encore de `sensors_plus`
   (accéléromètre + magnétomètre, cap bruité).
3. ⏳ Capture automatique : verrouillage exposition / mise au point après la
   1re photo (aujourd'hui ~3 s d'autofocus par photo → flou de bougé).
4. ✅ Module C++ OpenCV + FFI + isolate.
5. ⏳ Export JPEG + XMP GPano conforme (APP1 aujourd'hui inséré avant APP0),
   partage natif. Export galerie fait (`gal`).
6. ⏳ Galerie et visionneuse refaites ; reste le mode « petite planète ».
7. ⏳ Finitions, tests, README complet, polices embarquées hors ligne.
