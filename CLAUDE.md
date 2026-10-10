# Sary360

Flutter app that captures **360° spherical photos** ("Photo Sphere" style):
the user turns on the spot, the app takes a photo at each target of the
sphere, then a C++ OpenCV module stitches a 2:1 equirectangular image with
GPano XMP metadata. Visual theme: **"Constellation"** (capturing = completing
a star map).

## Language rules

- **All documentation and code comments are written in English**: CLAUDE.md,
  skills, README and docs, Dart / Kotlin / C++ / Python comments and doc
  comments, commit messages.
- **User-facing UI text stays in French** (the app targets French speakers).
- Many existing comments are still in French: translate them to English when
  you touch the surrounding code.
- Conversation with the user: French.

## Commands

Flutter is pinned to **3.47.5** (`.fvmrc`, FVM).

```bash
flutter pub get
flutter analyze                 # must stay at "No issues found!"
flutter test                    # runs directly on macOS
flutter build apk --debug       # also builds the native module (3 ABIs)
dart run ffigen --config ffigen.yaml   # after changing sary_stitcher.h
./scripts/build.sh              # release builds (APK, per-ABI APK, AAB, IPA)
```

Android prerequisites: NDK 28, CMake 3.22.1, **OpenCV Android SDK 4.13.0** in
`third_party/OpenCV-android-sdk` (git-ignored; otherwise `opencv.dir` in
`android/local.properties` or `OPENCV_ANDROID_SDK`). Procedure: README.
Release signing: `android/key.properties` + `android/key.jks` (git-ignored).

## Architecture

```
lib/
├── app.dart, main.dart          # MaterialApp.router, theme, ProviderScope
├── core/
│   ├── constants/               # AppConstants, CaptureGrid (target grids)
│   ├── math/                    # Vec3, Quaternion, CameraRotation, ScreenProjection
│   ├── router/                  # go_router (AppRoutes), onboarding redirect
│   ├── theme/                   # ConstellationColors (ThemeExtension), AppTheme
│   ├── utils/formatters.dart    # French dates / sizes for the UI
│   └── widgets/                 # GlassPanel, StarfieldBackground, ConstellationOrb
├── domain/                      # models, CaptureSession, interfaces (OrientationSource…)
├── data/
│   ├── native/                  # generated FFI bindings (do not edit)
│   ├── repositories/            # settings (SharedPreferences), panoramas (files)
│   ├── sensors/                 # orientation sources (rotation vector, raw sensors)
│   └── services/                # camera, stitching (isolate + FFI), gallery export
└── presentation/                # pages, viewmodels, Riverpod providers, widgets
native/stitcher/                 # C++ module: include/sary_stitcher.h, src/, tools/stitch_cli.cpp
android/.../OrientationStreamHandler.kt  # EventChannel sary360/orientation
tool/icon/                       # icon drawing (see skill regenerate-app-icon)
```

- State: **Riverpod** (`Notifier`). Capture separates low-frequency state
  (`CaptureState`) from ~50 Hz measurements (`CaptureController.frame`, a
  `ValueNotifier` listened to directly by the painter). Navigation:
  **go_router**, paths in `AppRoutes`.
- 360° viewer: `presentation/widgets/custom_panorama.dart` (local fork of
  `panorama` on top of `flutter_cube`).

## UI conventions

- Colors: always through `context.colors` (`ConstellationColors`), never
  hard-coded. Radii `AppRadii`, durations/curves `AppMotion`.
- Floating surfaces: `GlassPanel` / `GlassIconButton`. Backgrounds:
  `StarfieldBackground`.
- Fonts: Space Grotesk (titles) / Manrope (body) via google_fonts;
  `AppTheme.useGoogleFonts = false` in widget tests.
- The viewer forces the dark theme (controls sit on the photo), but its info
  sheet follows the app theme.
- Looping animations: use `pump(duration)` in tests, never `pumpAndSettle`
  (it never settles).

## Native stitching module (native/stitcher)

`cv::detail` pipeline called through FFI inside an isolate
(`stitching_service.dart`): sensor rotations → ORB (FAST threshold 8, 3000
keypoints) on **neighbors only** → `BundleAdjusterRay` **per connected
component**, kept only if it reduces the matched-ray error → corrections
propagated to unrefined photos (neighbors in capture order, compensating
gyroscope drift) → focal self-calibration → sharp photos take seam priority →
SphericalWarper, BlocksGain, GraphCut (0.05 Mpx), MultiBand → blurred hole
filling → JPEG, then XMP on the Dart side.

Floor eraser (manual, from the viewer's "Sol" button): `sary_erase_nadir`
unfolds the nadir into a 512 × 512 top-down view, fills a disc of the chosen
radius with the **MI-GAN 512 generator** (`assets/models/`, MIT, 27 MB) run by
OpenCV `dnn`, and projects it back (~1.6 s). `NadirEraserService` keeps the
original in `panoramas/originals/` for "Restaurer l'original". It is never
applied automatically: on scenes without feet it replaces real objects.

Things to know:
- `rotations` = OpenCV camera (x right, y down, z forward) → OpenCV world
  (y down, z = panorama center). Conversions and tests:
  `core/math/camera_rotation.dart`.
- Progress / cancellation through two shared native memory cells (addresses
  passed to the isolate). No `enum` nor `volatile` in the C header (ffigen):
  `int32_t` `SARY_*` codes.
- Each capture writes `cache/temp/session.json` (measured quaternions, capture
  order): `stitch_cli` then replays the stitching exactly (skill
  `test-stitcher-on-device`).
- Android log tag **`SaryStitcher`** (stages, timings, refined groups);
  `SARY_DEBUG=1` (CLI tool) adds per-photo and per-pair details.
- Pixel 6a ultra-wide: real field of view **≈ 53° × 83°** in portrait (the
  device's distortion correction crops it), not 62° × 94°. Ultra-wide grid:
  26 targets (10 / 7 / 7 / 1 / 1); main lens: 42.
- The `camera` plugin only captures **16:9** (all presets are video ones).
  `takePicture` runs an autofocus (3 s timeout with a fixed-focus lens) then
  an exposure metering (3 s if exposure is locked): hence focus locked and
  exposure left on auto.
- The app runs the phone hot: a thermal status ≥ 2 slows stitching 2–3×
  (`adb shell dumpsys thermalservice`).

## Known pitfalls

- `Isolate.run(() => …)` inside an instance method captures the whole context
  (callbacks → ViewModel → unsendable CameraController): create the closure in
  a **static** method that only sees the request.
- `ImageInfo` received from an `ImageStream`: dispose it and remove the same
  listener instance; otherwise the viewer showed black when reopened.
- `flutter_launcher_icons` wrongly rewrites
  `ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS` in
  `ios/Runner.xcodeproj/project.pbxproj`: revert that change.
- zsh: `for f in $VAR` does not split the variable (use `${=VAR}`), and an
  unmatched `*` glob makes the command fail (prefer `find … -exec`).
- `--split-per-abi` fails if `ndk.abiFilters` is set: the Gradle script only
  sets it when the `split-per-abi` property is absent.
- App files on the device: `adb exec-out run-as com.mandreshope.sary360 cat <path>`
  (photos in `cache/temp/`, panoramas in `app_flutter/panoramas/`).

## Working agreements

- **Do not install or launch the app on the phone unless asked**: the user
  tests it. Reading device logs and files (read-only) is fine, and so is the
  `stitch_cli` tool in `/data/local/tmp` (clean up afterwards).
- Commit only when asked, in thematic commits, on the working branch (not
  `develop`). Style: `feat:` / `fix:` / `enhance:` / `chore:` / `docs:` +
  English summary. **No `Co-Authored-By` line** (also disabled through
  `attribution` in `.claude/settings.json`).
- `DOCUMENTATION.md`, `QUICK_START.md` and `ANDROID_SETUP.md` are **obsolete**
  (pre-redesign); the README is up to date for setup and the native module.

## Progress (7-step specification)

1. ✅ Structure, theme, navigation, onboarding.
2. ✅ Orientation: `OrientationStreamHandler.kt` (EventChannel
   `sary360/orientation`, GAME_ROTATION_VECTOR else ROTATION_VECTOR) behind
   `OrientationSource` (`sensors_plus` fallback on iOS). "Constellation"
   capture screen (`ConstellationPainter`, `CaptureSession`).
3. ✅ Auto capture: angular distance to the reticle, 300 ms stillness, averaged
   quaternion stored. Focus locked after the first photo; exposure **not**
   locked (the `camera` plugin would wait 3 s per photo).
4. ✅ C++ OpenCV module + FFI + isolate.
5. ⏳ Compliant JPEG + GPano XMP export (APP1 currently inserted before APP0),
   native sharing. Gallery export done (`gal`).
6. ⏳ Gallery and viewer redesigned; "little planet" mode remaining.
7. ⏳ Polish, tests, full README, fonts bundled for offline use.

Next ideas: XFeat keypoints instead of ORB for low-texture walls (could also
run through OpenCV `dnn`), automatic feet detection to suggest the floor
eraser.
