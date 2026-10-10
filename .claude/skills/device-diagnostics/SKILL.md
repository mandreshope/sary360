---
name: device-diagnostics
description: Diagnose a problem reported on the phone (crash, freeze, black screen, slow or failed stitching) by reading the app's logs and files on the connected Android device, without reinstalling the app.
---

# On-device diagnostics (read-only)

Do not install or relaunch the app unless asked: the user tests it. Everything
below is read-only.

```bash
D=$(adb devices | awk 'NR==2{print $1}')
PKG=com.mandreshope.sary360
PID=$(adb -s $D shell pidof $PKG)
```

## Logs

- Native stitching: `adb -s $D logcat -d -s SaryStitcher flutter | grep -E "SaryStitcher|\[stitch\]"`
  (stages, timings, reliable pairs, refined groups, final status).
- Capture: `[capture]` lines under the `flutter` tag (orientation source
  fallback, failed shots, manifest).
- Flutter errors: `adb -s $D logcat -d --pid=$PID | grep -E "flutter|════|Exception"`.
- Native crashes: `adb -s $D logcat -d -b crash`, and `F DEBUG` /
  `Abort message` in the main log. Check the PID: a crash of
  `com.google.pixel.camera.hal` (`liblyric_hwl.so`) belongs to the camera
  service, not to the app.
- App stopped: `grep -E "Killing .*$PKG|has died|lowmemorykiller"`.
  "stop … due to from pid" = external stop (relaunch from the IDE), not a
  crash. "Lost connection to device" from `flutter run` usually just means the
  debug connection dropped: check `pidof` before assuming a crash.
- `Handler … sending message to a Handler on a dead thread` from
  `CameraDeviceImpl` is a harmless camera plugin warning on release.
- The logcat buffer rotates fast (chatty third-party apps): read early.

## Running process

- Memory / CPU: `adb -s $D shell "grep VmRSS /proc/$PID/status; cat /proc/$PID/stat"`
  (fields 14 + 15 = CPU ticks; sample twice to get a rate).
- Busiest threads: loop over `/proc/$PID/task/*/stat` + `comm`.
- Thermal throttling: `adb -s $D shell "dumpsys thermalservice | grep 'Thermal Status'"`
  (≥ 2 slows stitching 2–3×).
- Native stacks: `debuggerd` needs root; use
  `adb shell simpleperf record --app $PKG --duration 6 -o /data/local/tmp/perf.data`
  then `simpleperf report -i … --sort dso,symbol`.

## App files

```bash
adb -s $D shell "run-as $PKG ls -la cache/temp app_flutter/panoramas"
adb -s $D exec-out "run-as $PKG cat app_flutter/panoramas/<file>.jpg" > $S/pano.jpg
```

- Capture photos: `cache/temp/photo_r{row}_i{index}_{timestamp}.jpg`
  (1920 × 1080, EXIF orientation 6 → portrait once decoded) and
  `cache/temp/session.json` (measured quaternions, capture order).
- Panoramas: `app_flutter/panoramas/panorama_{timestamp}.jpg` (4096 × 2048).

## Camera characteristics

`adb -s $D shell dumpsys media.camera > $S/cam.txt`, then look for
`zoomRatioRange`, `availableFocalLengths`, `physicalSize`,
`intrinsicCalibration`, `lens.distortion`, and `android.control.zoomRatio`
(the app's current request).

To replay a stitching outside the app: skill `test-stitcher-on-device`.
