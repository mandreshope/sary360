# 🌐 Sary360

**Application mobile Flutter pour créer des panoramas 360° immersifs entièrement hors ligne.**

[![Flutter](https://img.shields.io/badge/Flutter-3.10+-02569B?logo=flutter)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.10+-0175C2?logo=dart)](https://dart.dev)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

![Sary360 Banner](assets/banner.png)

---

## 📱 Aperçu

Sary360 guide l'utilisateur lors de la capture de photos multiples grâce au **gyroscope**, assemble automatiquement les images en panorama **sur le téléphone**, et offre une **visualisation interactive 360°** avec gyroscope et touch.

### ✨ Fonctionnalités

- 🎯 **Guidage rotation intelligent** avec feedback visuel en temps réel
- 📸 **Capture optimisée** avec verrouillage exposition et focus
- 🔧 **Stitching offline** utilisant des algorithmes custom en pur Dart
- 🌍 **Viewer 360° interactif** avec gyroscope et contrôles tactiles
- ⚡ **Performances optimales** grâce aux isolates et gestion mémoire
- 📱 **100% offline** - aucun backend, aucune connexion requise

---

## 🎥 Démo

[Vidéo de démonstration à venir]

<!-- 
![Capture Flow](assets/demo_capture.gif)
![360 Viewer](assets/demo_viewer.gif)
-->

---

## 🚀 Installation

### Prérequis

- Flutter SDK 3.10+
- Dart SDK 3.10+
- Android Studio / VS Code
- Device Android 6.0+ (API 23+) ou émulateur

### Étapes

1. **Cloner le repository**
   ```bash
   git clone https://github.com/votre-username/sary360.git
   cd sary360
   ```

2. **Installer les dépendances**
   ```bash
   flutter pub get
   ```

3. **Lancer l'application**
   ```bash
   # Mode debug
   flutter run

   # Mode release (recommandé pour tester les performances)
   flutter run --release
   ```

---

## 🏗️ Architecture

```
lib/
├── core/              # Constantes et utilitaires
├── data/              # Services (caméra, stitching)
├── domain/            # Modèles métier
└── presentation/      # UI (pages, viewmodels, widgets)
```

**Patterns utilisés :**
- Clean Architecture (domain/data/presentation)
- MVVM avec Riverpod
- Service Layer
- Isolates pour traitement lourd

[Voir DOCUMENTATION.md pour détails complets](DOCUMENTATION.md)

---

## 📸 Comment ça marche ?

### 1. Capture Guidée

L'utilisateur capture **6 photos** en tournant à 360° :

- Le gyroscope track la rotation en temps réel
- Un indicateur visuel circulaire guide vers chaque angle cible (60° de distance)
- Le bouton de capture s'active uniquement quand l'angle est correct (±10°)
- L'exposition et le focus sont verrouillés pour cohérence

### 2. Stitching Offline

Le traitement se fait localement en **5 étapes** :

1. **Resize** → Optimisation pour performance (1920x1080 max)
2. **Crop** → Garde 85% du centre (minimise distorsion)
3. **Concatenation** → Assemblage horizontal avec chevauchement (100px)
4. **Blending** → Fusion douce dans les zones de chevauchement
5. **Balance** → Ajustements couleurs globaux

Le tout dans un **isolate séparé** pour ne pas bloquer l'UI.

### 3. Visualisation 360°

- Navigation à 360° avec gyroscope et touch
- Zoom et inertie fluide
- Aucune connexion internet requise

---

## 🛠️ Technologies

| Catégorie | Packages |
|-----------|----------|
| **Framework** | Flutter 3.10+ |
| **State Management** | flutter_riverpod ^2.6.1 |
| **Caméra** | camera ^0.11.0 |
| **Capteurs** | sensors_plus ^6.0.1 |
| **Traitement Image** | image ^4.3.0 (pur Dart) |
| **Viewer 360°** | panorama_viewer ^0.2.2 |
| **Permissions** | permission_handler ^11.3.1 |
| **Storage** | path_provider ^2.1.4 |

---

## 📊 Performances

| Métrique | Valeur |
|----------|--------|
| **Temps de stitching** | <10s (haut de gamme), 15-30s (milieu de gamme) |
| **Taille panorama** | ~2-4 MB (JPEG quality 85%) |
| **Résolution finale** | ~11520x1080 (6 photos × 1920px) |
| **Mémoire utilisée** | ~200-400 MB pendant stitching |
| **Taille APK** | ~25-30 MB |

---

## 🎨 Screenshots

<!-- Ajouter vos screenshots ici
| Home | Capture | Viewer |
|------|---------|--------|
| ![Home](assets/screenshot_home.png) | ![Capture](assets/screenshot_capture.png) | ![Viewer](assets/screenshot_viewer.png) |
-->

---

## 🧪 Tests

```bash
# Tests unitaires
flutter test

# Tests d'intégration
flutter test integration_test/

# Analyse de code
flutter analyze
```

---

## 📝 Configuration

### Android (obligatoire)

Ajouter les permissions dans `android/app/src/main/AndroidManifest.xml` :

```xml
<uses-permission android:name="android.permission.CAMERA" />
<uses-feature android:name="android.hardware.camera" android:required="true" />
<uses-feature android:name="android.hardware.sensor.gyroscope" android:required="true" />
```

### Personnalisation

Modifiez les constantes dans `lib/core/constants/app_constants.dart` :

```dart
static const int numberOfPhotos = 6;        // Nombre de photos
static const int maxImageWidth = 1920;      // Résolution max
static const int jpegQuality = 85;          // Qualité JPEG (0-100)
static const int overlapPixels = 100;       // Chevauchement
```

---

## 🗺️ Roadmap

- [x] MVP : Capture guidée + stitching simple + viewer
- [ ] **Phase 2** : Feature detection, multi-row stitching, HDR
- [ ] **Phase 3** : Hotspots interactifs, navigation multi-panoramas, export
- [ ] **Phase 4** : Mode VR, reconstruction 3D, AR

[Voir DOCUMENTATION.md pour roadmap détaillée](DOCUMENTATION.md)

---

## 🤝 Contribution

Les contributions sont les bienvenues !

1. Fork le projet
2. Créez votre branche (`git checkout -b feature/AmazingFeature`)
3. Commit vos changements (`git commit -m 'Add some AmazingFeature'`)
4. Push vers la branche (`git push origin feature/AmazingFeature`)
5. Ouvrez une Pull Request

---

## 📄 Licence

Distribué sous licence MIT. Voir `LICENSE` pour plus d'informations.

---

## 👤 Auteur

**Votre Nom**

- Portfolio: [votre-site.com](#)
- LinkedIn: [linkedin.com/in/votre-profil](#)
- GitHub: [@votre-username](https://github.com/votre-username)

---

## 🙏 Remerciements

- [Flutter](https://flutter.dev) - Framework
- [image package](https://pub.dev/packages/image) - Traitement d'images en pur Dart
- [panorama_viewer](https://pub.dev/packages/panorama_viewer) - Viewer 360°
- [sensors_plus](https://pub.dev/packages/sensors_plus) - Accès gyroscope

---

## 📚 Documentation Complète

Pour une documentation technique détaillée, voir [DOCUMENTATION.md](DOCUMENTATION.md) :

- Architecture complète
- Explications du code
- Bonnes pratiques de performance
- Conseils photo
- Limites techniques
- Guide développeur

---

**Fait avec ❤️ et Flutter**
