---
name: regenerate-app-icon
description: Change or regenerate the app icon ("Constellation" theme) for Android (adaptive, monochrome, legacy) and iOS, from the code drawing in tool/icon/render_icon_test.dart.
---

# Regenerate the app icon

The icon is drawn by a `CustomPainter` (`IconPainter` in
`tool/icon/render_icon_test.dart`), in three variants:
- `full`: night background + sphere (iOS, legacy Android icons);
- `foreground`: sphere only, for the adaptive icon. flutter_launcher_icons
  insets it by 16 % (scale 0.68): radius 0.34 → ≈ 0.23 once displayed, halo
  kept within ≈ 0.30 (visible area after masking);
- `monochrome`: opaque white silhouette (Android 13+ themed icons).

## Steps

1. Edit the drawing in `tool/icon/render_icon_test.dart`. Theme colors: night
   `#07080C`, cyan `#2EE6FF`, star `#F2F4FF`. In color, keep
   `StrokeCap.butt` for semi-transparent segments (round caps overlap and
   look dotted).
2. Render the 1024 × 1024 PNGs into `assets/icon/`:
   ```bash
   flutter test tool/icon/render_icon_test.dart
   ```
3. Check visually with Read (downscale first:
   `sips -Z 512 assets/icon/icon.png --out $S/icon_512.png`). The monochrome
   variant is white on transparent: compose it on a dark background (small
   temporary test with `ClipOval`) to judge it.
4. Generate the platform icons (config: `flutter_launcher_icons.yaml`):
   ```bash
   dart run flutter_launcher_icons
   ```
5. **Revert the plugin's wrong Xcode project change** (it replaces
   `ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS` with
   `AppIcon`):
   ```bash
   git checkout ios/Runner.xcodeproj/project.pbxproj
   ```
6. Check: `flutter analyze` then `flutter build apk --debug`. On the device,
   the launcher may keep the old icon until the app is uninstalled.
