---
name: regenerate-ffi-bindings
description: Régénérer les bindings Dart du module natif après une modification de native/stitcher/include/sary_stitcher.h (nouveau champ, nouvelle fonction, nouveau code de retour), et vérifier que l'interface reste compatible FFI.
---

# Régénérer les bindings FFI

1. Modifier `native/stitcher/include/sary_stitcher.h` en respectant les
   contraintes de ffigen :
   - pas d'`enum` dans l'interface (taille dépendante du compilateur) : codes
     de retour en `#define SARY_*` et fonctions renvoyant `int32_t` ;
   - pas de pointeurs `volatile` dans les structs (ffigen supprime alors
     **tous** les champs de la struct) : déclarer `float *` / `int32_t *` et
     appliquer `volatile` côté C++ (`static_cast<volatile float*>`) ;
   - types à taille fixe (`int32_t`, `float`) ; chaînes en `const char *` UTF-8.
2. Mettre à jour `native/stitcher/src/sary_stitcher.cpp` et, si un champ de
   `SaryStitchParams` est ajouté, `native/stitcher/tools/stitch_cli.cpp`
   (initialisé avec `SaryStitchParams params{}`).
3. Générer (libclang fourni par Xcode sur macOS) :
   ```bash
   dart run ffigen --config ffigen.yaml
   ```
   Lire la sortie : aucune ligne `[WARNING]` ni `[SEVERE]` ne doit apparaître.
   Résultat : `lib/data/native/sary_stitcher_bindings.g.dart` (ne jamais
   l'éditer à la main).
4. Renseigner le nouveau champ dans `SaryStitchParams.$allocate(...)` de
   `lib/data/services/stitching_service.dart` (`_stitchInIsolate`).
5. Vérifier :
   ```bash
   flutter analyze
   flutter build apk --debug
   ```
