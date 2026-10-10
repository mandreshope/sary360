---
name: test-stitcher-on-device
description: Test the C++ stitching module (native/stitcher) on the connected Android phone, outside the app, with the photos of the latest capture. Use after changing sary_stitcher.cpp to measure timings, tune a parameter, compare two versions or judge panorama quality without reinstalling the app.
---

# Test native stitching on the device

Builds `stitch_cli` + `libsary_stitcher.so` with the NDK, pushes them to
`/data/local/tmp/sary` together with the latest session's photos, runs the
stitching and pulls the panorama back. The app is neither reinstalled nor
launched.

Paths below assume the project root as working directory and `$S` = a
temporary working folder (scratchpad).

## 1. Build for arm64

```bash
SDK=/Volumes/BarraCudaQ5/Developer/Android/SDK
NDK=$SDK/ndk/28.2.13676358
CM=$SDK/cmake/3.22.1/bin
B=$S/ndkbuild
$CM/cmake -S native/stitcher -B $B -G Ninja -DCMAKE_MAKE_PROGRAM=$CM/ninja \
  -DCMAKE_TOOLCHAIN_FILE=$NDK/build/cmake/android.toolchain.cmake \
  -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-26 -DANDROID_STL=c++_shared \
  -DCMAKE_BUILD_TYPE=Release -DSARY_BUILD_CLI=ON \
  -DOpenCV_DIR=$PWD/third_party/OpenCV-android-sdk/sdk/native/jni
$CM/ninja -C $B
```

Later rebuilds: `$CM/ninja -C $B` is enough.

## 2. Fetch the latest session's photos

Photos live in the app cache (`cache/temp/`), next to `session.json`. Go
through the Mac: a `run-as … | adb shell "cat > …"` pipe stops after the first
file.

```bash
D=$(adb devices | awk 'NR==2{print $1}')
mkdir -p $S/session
for f in $(adb -s $D shell "run-as com.mandreshope.sary360 ls cache/temp" | tr -d '\r'); do
  adb -s $D exec-out "run-as com.mandreshope.sary360 cat cache/temp/$f" > $S/session/$f
done
```

## 3. Generate the input list

When `session.json` was fetched with the photos (written by the app at the
end of each capture), the script uses the **actually measured quaternions**
and the capture order: the stitching is identical to the app's. Otherwise
(older sessions) it rebuilds rotations from the target angles — a misleading
approximation when comparing two versions (arbitrary heading at the poles).

```bash
python3 .claude/skills/test-stitcher-on-device/scripts/make_list.py $S/session \
  --grid wide > $S/list.txt          # --grid standard for the main lens
```

Options: `--hfov`, `--width 8192`, `--refine 0` (sensor rotations only, no
bundle adjustment), `--count`.

## 4. Push, run, pull

```bash
adb -s $D shell "mkdir -p /data/local/tmp/sary/photos"
rm -rf $S/push && mkdir $S/push
find $S/session -name "*.jpg" -exec cp {} $S/push/ \;
adb -s $D push $S/push/. /data/local/tmp/sary/photos/
adb -s $D push $B/stitch_cli $B/libsary_stitcher.so \
  $NDK/toolchains/llvm/prebuilt/darwin-x86_64/sysroot/usr/lib/aarch64-linux-android/libc++_shared.so \
  $S/list.txt /data/local/tmp/sary/
adb -s $D logcat -c
adb -s $D shell "cd /data/local/tmp/sary && SARY_DEBUG=1 LD_LIBRARY_PATH=. ./stitch_cli list.txt"
adb -s $D logcat -d -s SaryStitcher | sed 's/.*SaryStitcher: //'
adb -s $D pull /data/local/tmp/sary/pano.jpg $S/pano.jpg
sips -Z 1600 $S/pano.jpg --out $S/pano_small.jpg   # to view it with Read
```

`stitch_cli` settings overridable through environment variables:
`SARY_WORK_MP`, `SARY_SEAM_MP`, `SARY_FEATURES`, `SARY_NEIGHBOR` (neighbor
angle, default 68° = (hFov + vFov) / 2 for the ultra-wide lens).
`SARY_DEBUG=1` logs per-pair keypoints and confidence, relative sharpness,
per-photo corrections and focals.

## 5. Read the result

The module's log lines are currently in French:
- `paires candidates / fiables` (candidate / reliable pairs): few reliable
  pairs = not enough overlap or texture.
- `groupe de N photos : écart des rayons A° → B°` (group of N photos: ray
  error before → after): refinement is kept if it clearly reduces the error
  (≤ 80 %, ≤ 2°).
- `photos non affinées corrigées par leurs voisines`: unrefined photos that
  received their neighbors' correction (gyroscope drift).
- `focale médiane des photos affinées` vs `théorique` (refined median focal vs
  theoretical): a gap > 5 % means the field of view in `AppConstants` is off.
- Compare full-resolution crops (`sips -c H W --cropOffset Y X`) to judge
  seams and sharpness.

The phone heats up: check `adb shell dumpsys thermalservice | grep "Thermal
Status"` before comparing timings (status ≥ 2 slows everything 2–3×).

## 6. Compare two versions

Build the reference version in another folder (copy `native/stitcher`, then
`git show HEAD:native/stitcher/src/sary_stitcher.cpp > <copy>/src/sary_stitcher.cpp`),
push both binaries into separate subfolders and run them on the same list.

## 7. Clean up

```bash
adb -s $D shell "rm -rf /data/local/tmp/sary"
```

zsh caveats: `for f in $VAR` does not split a variable (use command
substitution or `${=VAR}`), and an unmatched `*` glob makes the command fail
(prefer `find … -exec`).
