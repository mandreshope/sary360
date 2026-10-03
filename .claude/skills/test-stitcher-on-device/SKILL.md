---
name: test-stitcher-on-device
description: Tester le module C++ d'assemblage (native/stitcher) sur le téléphone Android branché, hors de l'app, avec les photos de la dernière capture. À utiliser après une modification de sary_stitcher.cpp, pour mesurer les durées, régler un paramètre ou juger la qualité d'un panorama sans réinstaller l'app.
---

# Tester l'assemblage natif sur l'appareil

Compile `stitch_cli` + `libsary_stitcher.so` avec le NDK, les pousse dans
`/data/local/tmp/sary` avec les photos de la dernière session, lance
l'assemblage et récupère le panorama. L'app n'est ni réinstallée ni lancée.

Les chemins ci-dessous supposent la racine du projet comme dossier courant et
`$S` = dossier temporaire de travail (scratchpad).

## 1. Compiler pour arm64

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

Les recompilations suivantes : `$CM/ninja -C $B` suffit.

## 2. Récupérer les photos de la dernière session

Les photos sont dans le cache de l'app (`cache/temp/`). Passer par le Mac :
un tuyau `run-as … | adb shell "cat > …"` s'arrête après le premier fichier.

```bash
D=$(adb devices | awk 'NR==2{print $1}')
mkdir -p $S/session
for f in $(adb -s $D shell "run-as com.mandreshope.sary360 ls cache/temp" | tr -d '\r'); do
  adb -s $D exec-out "run-as com.mandreshope.sary360 cat cache/temp/$f" > $S/session/$f
done
```

## 3. Générer la liste d'entrée

Les quaternions ne sont pas sauvegardés sur disque : le script reconstruit les
rotations à partir des angles des cibles (approximation : le cap réel peut
s'en écarter de 10 à 30°, l'affinage par points-clés le corrige).

```bash
python3 .claude/skills/test-stitcher-on-device/scripts/make_list.py $S/session \
  --grid wide > $S/list.txt          # --grid standard pour l'objectif principal
```

Options : `--hfov`, `--width 8192`, `--refine 0` (rotations seules, sans
bundle adjustment), `--count`.

## 4. Pousser, lancer, récupérer

```bash
adb -s $D shell "mkdir -p /data/local/tmp/sary/photos"
mkdir -p $S/push && rm -f $S/push/*
for f in $(awk 'NR>1{n=split($1,a,"/"); print a[n]}' $S/list.txt); do cp $S/session/$f $S/push/; done
adb -s $D push $S/push/. /data/local/tmp/sary/photos/
adb -s $D push $B/stitch_cli $B/libsary_stitcher.so \
  $NDK/toolchains/llvm/prebuilt/darwin-x86_64/sysroot/usr/lib/aarch64-linux-android/libc++_shared.so \
  $S/list.txt /data/local/tmp/sary/
adb -s $D logcat -c
adb -s $D shell "cd /data/local/tmp/sary && SARY_DEBUG=1 LD_LIBRARY_PATH=. ./stitch_cli list.txt"
adb -s $D logcat -d -s SaryStitcher | sed 's/.*SaryStitcher: //'
adb -s $D pull /data/local/tmp/sary/pano.jpg $S/pano.jpg
sips -Z 1600 $S/pano.jpg --out $S/pano_small.jpg   # pour l'afficher avec Read
```

Réglages surchargeables par variables d'environnement de `stitch_cli` :
`SARY_WORK_MP`, `SARY_SEAM_MP`, `SARY_FEATURES`. `SARY_DEBUG=1` journalise
points-clés et confiance par paire, netteté relative, corrections et focales
par photo.

## 5. Lire le résultat

- `paires candidates / fiables` : peu de paires fiables = recouvrement ou
  texture insuffisants.
- `groupe de N photos : écart des rayons A° → B°` : l'affinage est retenu
  s'il réduit nettement l'écart (≤ 80 %, ≤ 2°).
- `focale médiane des photos affinées` vs `théorique` : un écart > 5 % indique
  un champ de vision mal estimé dans `AppConstants`.
- Comparer des recadrages à pleine résolution (`sips -c H W --cropOffset Y X`)
  pour juger raccords et netteté.

## 6. Nettoyer

```bash
adb -s $D shell "rm -rf /data/local/tmp/sary"
```

Attention zsh : `for f in $VAR` ne découpe pas une variable ; utiliser une
substitution de commande comme ci-dessus ou `${=VAR}`.
