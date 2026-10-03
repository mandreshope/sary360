---
name: regenerate-app-icon
description: Modifier ou régénérer l'icône de l'application (thème « Constellation ») pour Android (adaptative, monochrome, classique) et iOS, à partir du dessin en code de tool/icon/render_icon_test.dart.
---

# Régénérer l'icône de l'application

L'icône est dessinée par un `CustomPainter` (`IconPainter` dans
`tool/icon/render_icon_test.dart`), en trois variantes :
- `full` : fond nuit + sphère (iOS, icônes Android classiques) ;
- `foreground` : sphère seule pour l'icône adaptative. flutter_launcher_icons
  l'insère avec une marge de 16 % (échelle 0,68) : rayon 0,34 → ≈ 0,23 affiché,
  halo limité à ≈ 0,30 (zone visible après masquage) ;
- `monochrome` : silhouette blanche opaque (icônes à thème Android 13+).

## Étapes

1. Modifier le dessin dans `tool/icon/render_icon_test.dart`. Couleurs du
   thème : nuit `#07080C`, cyan `#2EE6FF`, étoile `#F2F4FF`.
   En couleur, garder `StrokeCap.butt` pour les segments semi-transparents
   (des extrémités rondes se chevauchent et donnent un effet pointillé).
2. Générer les PNG 1024 × 1024 dans `assets/icon/` :
   ```bash
   flutter test tool/icon/render_icon_test.dart
   ```
3. Contrôler visuellement avec Read (réduire d'abord :
   `sips -Z 512 assets/icon/icon.png --out $S/icon_512.png`). La version
   monochrome est blanche sur transparent : la composer sur un fond sombre
   (petit test temporaire avec `ClipOval`) pour la juger.
4. Générer les icônes des plateformes (config : `flutter_launcher_icons.yaml`) :
   ```bash
   dart run flutter_launcher_icons
   ```
5. **Annuler le changement erroné du projet Xcode** fait par le plugin
   (il remplace `ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS`
   par `AppIcon`) :
   ```bash
   git checkout ios/Runner.xcodeproj/project.pbxproj
   ```
6. Vérifier : `flutter analyze` puis `flutter build apk --debug`.
   Sur l'appareil, le lanceur peut garder l'ancienne icône jusqu'à la
   désinstallation de l'app.
