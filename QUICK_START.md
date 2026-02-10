# 🚀 Guide de Démarrage Rapide - Sary360

## ⚠️ PROBLÈME CRITIQUE DÉTECTÉ

Le code source contient des **caractères HTML encodés** (`<`, `>`, etc.) qui rendent le projet **non compilable**. Ces caractères ont probablement été introduits lors d'une copie/colle depuis un navigateur ou un document HTML.

## 🔧 Solution Immédiate

### Option 1: Réinitialisation Complète (RECOMMANDÉ)

```powershell
# 1. Supprimer le dossier lib actuel
Remove-Item -Recurse -Force .\lib

# 2. Recréer la structure de base
New-Item -ItemType Directory -Force -Path .\lib\core\constants
New-Item -ItemType Directory -Force -Path .\lib\data\services
New-Item -ItemType Directory -Force -Path .\lib\domain\models
New-Item -ItemType Directory -Force -Path .\lib\presentation\pages
New-Item -ItemType Directory -Force -Path .\lib\presentation\viewmodels
New-Item -ItemType Directory -Force -Path .\lib\presentation\widgets

# 3. Corriger pubspec.yaml
code .\pubspec.yaml
```

### Option 2: Recherche et Remplacement Global

Utilisez un éditeur de texte comme VS Code pour remplacer dans TOUS les fichiers `.dart` :

- Remplacer `<` par `<`
- Remplacer `>` par `>`
- Remplacer `&` par `&`
- Remplacer `"` par `"`

```powershell
# Dans VS Code: Ctrl+Shift+H (Rechercher/Remplacer dans les fichiers)
```

## 📦 Dépendances Correctes (pour pubspec.yaml)

```yaml
dependencies:
  flutter:
    sdk: flutter

  # State management
  flutter_riverpod: ^2.6.1

  # Camera & sensors
  camera: ^0.11.0+2
  sensors_plus: ^6.1.0
  permission_handler: ^11.3.1

  # Image processing
  image: ^4.3.0

  # Storage
  path_provider: ^2.1.4

  # 360 viewer
  panorama: ^0.4.1

  # UI utilities
  flutter_svg: ^2.0.10+1
  cupertino_icons: ^1.0.8
```

## 📁 Structure de Fichiers Requise

```
lib/
├── core/
│   └── constants/
│       └── app_constants.dart
├── data/
│   └── services/
│       ├── camera_service.dart
│       └── stitching_service.dart
├── domain/
│   └── models/
│       ├── captured_photo.dart
│       └── panorama.dart
├── presentation/
│   ├── pages/
│   │   ├── home_page.dart
│   │   ├── capture_page.dart
│   │   └── viewer_page.dart
│   ├── viewmodels/
│   │   └── capture_viewmodel.dart
│   └── widgets/
│       ├── capture_button.dart
│       ├── progress_indicator.dart
│       └── rotation_indicator.dart
└── main.dart
```

## ✅ Vérification post-correction

```powershell
# 1. Nettoyer le cache
flutter clean

# 2. Récupérer les dépendances
flutter pub get

# 3. Vérifier les erreurs
flutter analyze

# 4. Tester la compilation
flutter build apk --debug
```

## 🎯 Prochaines Étapes (après correction)

1. **Configuration Android** (`ANDROID_SETUP.md`)
   - Ajouter permissions dans `AndroidManifest.xml`
   - Vérifier `minSdkVersion >= 21`

2. **Test sur appareil réel**
   ```powershell
   flutter devices
   flutter run
   ```

3. **Tester les fonctionnalités**
   - Permissions caméra/capteurs
   - Capture de photos
   - Rotation gyroscopique
   - Stitching d'images
   - Visualisation 360°

## 📚 Documentation Complète

- `README.md` - Vue d'ensemble du projet
- `DOCUMENTATION.md` - Guide technique détaillé
- `ANDROID_SETUP.md` - Configuration Android spécifique

## 🆘 Support

Si le problème persiste après ces corrections:

1. Vérifiez l'encodage des fichiers (doit être UTF-8)
2. Assurez-vous qu'aucun fichier ne contient de caractères HTML
3. Vérifiez que tous les imports sont corrects
4. Consultez les logs d'erreur complets avec `flutter run --verbose`

---

**Note:** Ce projet nécessite un appareil Android physique avec gyroscope pour fonctionner correctement. L'émulateur ne supportera pas pleinement les fonctionnalités de capture panoramique.
