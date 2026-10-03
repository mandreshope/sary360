---
name: device-diagnostics
description: Diagnostiquer un problème signalé sur le téléphone (plantage, blocage, écran noir, assemblage lent ou raté) en lisant les logs et les fichiers de l'app sur l'appareil Android branché, sans réinstaller l'app.
---

# Diagnostic sur l'appareil (lecture seule)

Ne pas installer ni relancer l'app sans demande : l'utilisateur teste
lui-même. Tout ce qui suit est en lecture seule.

```bash
D=$(adb devices | awk 'NR==2{print $1}')
PKG=com.mandreshope.sary360
PID=$(adb -s $D shell pidof $PKG)
```

## Logs

- Assemblage natif : `adb -s $D logcat -d -s SaryStitcher flutter | grep -E "SaryStitcher|\[stitch\]"`
  (étapes, durées, paires fiables, groupes affinés, statut final).
- Erreurs Flutter : `adb -s $D logcat -d --pid=$PID | grep -E "flutter|════|Exception"`.
- Plantages natifs : `adb -s $D logcat -d -b crash`, et `F DEBUG` / `Abort message`
  dans le log principal. Vérifier le PID : un crash de
  `com.google.pixel.camera.hal` (`liblyric_hwl.so`) concerne le service caméra,
  pas l'app.
- Arrêt de l'app : `grep -E "Killing .*$PKG|has died|lowmemorykiller"`.
  « stop … due to from pid » = arrêt externe (relance depuis l'IDE), pas un crash.
- Le tampon logcat tourne vite (applications tierces bavardes) : lire tôt.

## Processus en cours

- Mémoire / CPU : `adb -s $D shell "grep VmRSS /proc/$PID/status; cat /proc/$PID/stat"`
  (champs 14 + 15 = ticks CPU ; échantillonner deux fois pour une vitesse).
- Threads les plus actifs : boucle sur `/proc/$PID/task/*/stat` + `comm`.
- Pile native : `debuggerd` exige root ; utiliser
  `adb shell simpleperf record --app $PKG --duration 6 -o /data/local/tmp/perf.data`
  puis `simpleperf report -i … --sort dso,symbol`.

## Fichiers de l'app

```bash
adb -s $D shell "run-as $PKG ls -la cache/temp app_flutter/panoramas"
adb -s $D exec-out "run-as $PKG cat app_flutter/panoramas/<fichier>.jpg" > $S/pano.jpg
```

- Photos de capture : `cache/temp/photo_r{rangée}_i{index}_{horodatage}.jpg`
  (1920 × 1080, orientation EXIF 6 → portrait au décodage).
- Sphères : `app_flutter/panoramas/panorama_{horodatage}.jpg` (4096 × 2048).

## Caractéristiques caméra

`adb -s $D shell dumpsys media.camera > $S/cam.txt`, puis chercher
`zoomRatioRange`, `availableFocalLengths`, `physicalSize`,
`intrinsicCalibration`, `lens.distortion`, et `android.control.zoomRatio`
(requête en cours de l'app).

Pour rejouer un assemblage hors de l'app : skill `test-stitcher-on-device`.
