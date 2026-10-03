#!/usr/bin/env bash

# ==============================================================================
# Script de Build Release - Sary360
# ==============================================================================
# Ce script génère des builds de release pour Android et iOS, avec le choix
# du type de livrable (APK universel, APK par architecture, AAB, IPA).
#
# Le projet n'a pas de flavor : point d'entrée unique lib/main.dart.
# Android compile aussi le module natif d'assemblage (native/stitcher), qui
# nécessite l'OpenCV Android SDK (voir README).
# ==============================================================================

set -e

# Couleurs pour l'affichage
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Se placer à la racine du projet
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

TARGET_FILE="lib/main.dart"

# Affichage de l'aide
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    echo -e "${BOLD}Usage :${NC} ./scripts/build.sh [PLATFORME] [TYPE] [CLEAN]"
    echo ""
    echo -e "${BOLD}Arguments (optionnels, mode interactif par défaut si omis) :${NC}"
    echo "  PLATFORME   : android | ios | all (Android + iOS)"
    echo "  TYPE        : apk | split | aab | both (Android et all) ; ignoré pour ios (IPA)"
    echo "                apk   = APK universel (3 architectures)"
    echo "                split = un APK par architecture (arm64-v8a, armeabi-v7a, x86_64)"
    echo "                both  = AAB + APK universel"
    echo "  CLEAN       : y | n (exécuter flutter clean & pub get avant le build)"
    echo ""
    echo -e "${BOLD}Exemples :${NC}"
    echo "  ./scripts/build.sh                    # Mode interactif"
    echo "  ./scripts/build.sh android aab n      # AAB release (Play Store)"
    echo "  ./scripts/build.sh android split y    # APK par architecture, avec clean"
    echo "  ./scripts/build.sh ios ipa n          # IPA release"
    echo "  ./scripts/build.sh all aab n          # AAB + IPA"
    exit 0
fi

echo -e "${CYAN}${BOLD}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║          🚀 SARY360 - BUILD RELEASE SCRIPT                   ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# ------------------------------------------------------------------------------
# Détection de la commande Flutter (FVM ou standard)
# ------------------------------------------------------------------------------
FLUTTER_CMD="flutter"
if command -v fvm >/dev/null 2>&1 && [ -f ".fvmrc" ]; then
    FLUTTER_CMD="fvm flutter"
    echo -e "${GREEN}✓ Utilisation de FVM (${FLUTTER_CMD})${NC}"
else
    if ! command -v flutter >/dev/null 2>&1; then
        echo -e "${RED}❌ Erreur : Flutter n'est pas installé ou introuvable dans le PATH.${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓ Utilisation de Flutter système (${FLUTTER_CMD})${NC}"
fi

# ------------------------------------------------------------------------------
# 1. Choix de la plateforme
# ------------------------------------------------------------------------------
PLATFORM=""
if [ -n "$1" ]; then
    PLATFORM="$1"
else
    echo -e "\n${BOLD}${BLUE}[1/3] Choisissez la plateforme :${NC}"
    echo "  1) Android"
    echo "  2) iOS"
    echo "  3) Les deux (Android + iOS)"
    while true; do
        read -rp "Votre choix (1, 2 ou 3) : " platform_choice
        case $platform_choice in
            1|android|Android)
                PLATFORM="android"
                break
                ;;
            2|ios|iOS|IOS)
                PLATFORM="ios"
                break
                ;;
            3|all|both)
                PLATFORM="all"
                break
                ;;
            *)
                echo -e "${YELLOW}Option invalide. Veuillez entrer 1, 2 ou 3.${NC}"
                ;;
        esac
    done
fi

[ "$PLATFORM" = "both" ] && PLATFORM="all"
case $PLATFORM in
    android|ios|all) ;;
    *)
        echo -e "${RED}❌ Plateforme inconnue : $PLATFORM${NC}"
        exit 1
        ;;
esac

# ------------------------------------------------------------------------------
# Vérifications propres au projet
# ------------------------------------------------------------------------------

# OpenCV Android SDK : même ordre de recherche que android/app/build.gradle.kts
# (clé opencv.dir de local.properties, OPENCV_ANDROID_SDK, third_party/).
check_opencv_sdk() {
    local dir=""
    if [ -f "android/local.properties" ]; then
        dir=$(grep -E '^opencv\.dir=' android/local.properties | cut -d= -f2- || true)
    fi
    [ -z "$dir" ] && dir="${OPENCV_ANDROID_SDK:-}"
    [ -z "$dir" ] && dir="${PROJECT_ROOT}/third_party/OpenCV-android-sdk"
    if [ ! -f "${dir}/sdk/native/jni/OpenCVConfig.cmake" ]; then
        echo -e "${RED}❌ OpenCV Android SDK introuvable (${dir}).${NC}"
        echo "   Le module natif d'assemblage en a besoin : voir la section"
        echo "   « Installer l'OpenCV Android SDK » du README."
        exit 1
    fi
    echo -e "${GREEN}✓ OpenCV Android SDK : ${dir}${NC}"
}

if [ "$PLATFORM" = "android" ] || [ "$PLATFORM" = "all" ]; then
    check_opencv_sdk
    # Signature : android/key.properties + keystore (voir README).
    if [ -f "android/key.properties" ]; then
        store_file=$(grep -E '^storeFile=' android/key.properties | cut -d= -f2- || true)
        if [ -z "$store_file" ] || { [ ! -f "android/app/${store_file}" ] && [ ! -f "$store_file" ]; }; then
            echo -e "${RED}❌ Keystore introuvable : storeFile=${store_file} (relatif à android/app).${NC}"
            exit 1
        fi
        echo -e "${GREEN}✓ Signature release : android/key.properties (${store_file})${NC}"
    else
        echo -e "${YELLOW}⚠️  android/key.properties absent : la release sera signée avec la clé${NC}"
        echo -e "${YELLOW}   de debug (non publiable sur le Play Store).${NC}"
    fi
fi
if [ "$PLATFORM" = "ios" ] || [ "$PLATFORM" = "all" ]; then
    echo -e "${YELLOW}⚠️  Le module d'assemblage natif n'est pas encore intégré à iOS :${NC}"
    echo -e "${YELLOW}   l'IPA se construit, mais l'assemblage des sphères y échouera.${NC}"
fi

# ------------------------------------------------------------------------------
# 2. Choix du Type de livrable
# ------------------------------------------------------------------------------
# BUILD_TYPE contient le type de package Android ("all" ajoute un IPA)
BUILD_TYPE=""
if [ "$PLATFORM" = "android" ] || [ "$PLATFORM" = "all" ]; then
    if [ -n "$2" ]; then
        BUILD_TYPE="$2"
    else
        echo -e "\n${BOLD}${BLUE}[2/3] Choisissez le type de package Android :${NC}"
        echo "  1) AAB (Android App Bundle pour Google Play Store)"
        echo "  2) APK universel (installation directe / tests, 3 architectures)"
        echo "  3) APK par architecture (plus léger : arm64-v8a, armeabi-v7a, x86_64)"
        echo "  4) Les deux (AAB + APK universel)"
        while true; do
            read -rp "Votre choix (1-4) : " type_choice
            case $type_choice in
                1|aab|AAB)
                    BUILD_TYPE="aab"
                    break
                    ;;
                2|apk|APK)
                    BUILD_TYPE="apk"
                    break
                    ;;
                3|split)
                    BUILD_TYPE="split"
                    break
                    ;;
                4|both|Both)
                    BUILD_TYPE="both"
                    break
                    ;;
                *)
                    echo -e "${YELLOW}Option invalide. Veuillez entrer un chiffre entre 1 et 4.${NC}"
                    ;;
            esac
        done
    fi
    case $BUILD_TYPE in
        apk|split|aab|both) ;;
        *)
            echo -e "${RED}❌ Type de package inconnu : $BUILD_TYPE${NC}"
            exit 1
            ;;
    esac
    if [ "$PLATFORM" = "all" ]; then
        echo -e "${BOLD}${BLUE}      Type de package iOS :${NC} ${GREEN}IPA (Archive / Distribution)${NC}"
    fi
else
    # iOS -> IPA
    BUILD_TYPE="ipa"
    echo -e "\n${BOLD}${BLUE}[2/3] Type de package iOS :${NC} ${GREEN}IPA (Archive / Distribution)${NC}"
fi

# ------------------------------------------------------------------------------
# 3. Nettoyage optionnel
# ------------------------------------------------------------------------------
CLEAN_BUILD="n"
if [ -n "$3" ]; then
    CLEAN_BUILD="$3"
else
    echo -e "\n${BOLD}${BLUE}[3/3] Exécuter 'flutter clean' & 'pub get' avant le build ?${NC}"
    echo "  (le prochain build Android recompilera alors le module natif)"
    read -rp "Nettoyer le cache ? (o/N, défaut: non) : " clean_choice
    case $clean_choice in
        o|O|y|Y|oui|yes)
            CLEAN_BUILD="y"
            ;;
        *)
            CLEAN_BUILD="n"
            ;;
    esac
fi

# ------------------------------------------------------------------------------
# Récapitulatif et Confirmation
# ------------------------------------------------------------------------------
APP_VERSION=$(grep -E '^version:' pubspec.yaml | awk '{print $2}')

echo -e "\n${CYAN}════════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}📋 RÉCAPITULATIF DU BUILD :${NC}"
echo -e "  • Plateforme   : ${GREEN}${PLATFORM}${NC}"
echo -e "  • Version      : ${GREEN}${APP_VERSION}${NC}"
echo -e "  • Point d'entrée : ${GREEN}${TARGET_FILE}${NC}"
echo -e "  • Type         : ${GREEN}${BUILD_TYPE}$([ "$PLATFORM" = "all" ] && echo " + ipa")${NC}"
echo -e "  • Mode         : ${GREEN}release${NC}"
echo -e "  • Clean build  : $([ "$CLEAN_BUILD" = "y" ] && echo -e "${GREEN}Oui${NC}" || echo -e "${YELLOW}Non${NC}")"
echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}\n"

read -rp "Lancer le build ? (O/n, défaut: oui) : " confirm
case $confirm in
    n|N|non|no)
        echo -e "${YELLOW}Build annulé par l'utilisateur.${NC}"
        exit 0
        ;;
esac

# ------------------------------------------------------------------------------
# Exécution du nettoyage si demandé
# ------------------------------------------------------------------------------
START_TIME=$(date +%s)

# Suffixe commun à tous les fichiers produits par ce run (version + horodatage)
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
ARTIFACT_SUFFIX="v${APP_VERSION}-${TIMESTAMP}"

# Fichier repère : seuls les fichiers plus récents appartiennent à ce run
BUILD_MARKER="$(mktemp)"
trap 'rm -f "$BUILD_MARKER"' EXIT

if [ "$CLEAN_BUILD" = "y" ]; then
    echo -e "\n${YELLOW}🧹 Nettoyage du projet...${NC}"
    $FLUTTER_CMD clean
    echo -e "${YELLOW}📦 Récupération des dépendances...${NC}"
    $FLUTTER_CMD pub get
fi

# ------------------------------------------------------------------------------
# Lancement de la compilation
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}${GREEN}⚙️  Démarrage de la compilation en mode Release...${NC}\n"

OUTPUT_FILES=()

# Renomme un fichier produit avec le suffixe du run et l'ajoute à OUTPUT_FILES
rename_artifact() {
    local src="$1"
    local dest_name="$2"
    local dest
    dest="$(dirname "$src")/${dest_name}"
    mv "$src" "$dest"
    OUTPUT_FILES+=("$dest")
}

build_android_apk() {
    echo -e "${BLUE}▶ Build Android APK universel...${NC}"
    $FLUTTER_CMD build apk --release -t "$TARGET_FILE"

    local apk="build/app/outputs/flutter-apk/app-release.apk"
    if [ -f "$apk" ]; then
        rename_artifact "$apk" "sary360-${ARTIFACT_SUFFIX}.apk"
        # Le .sha1 ne correspond plus au nom renommé
        rm -f "${apk}.sha1"
    fi
}

build_android_split_apk() {
    echo -e "${BLUE}▶ Build Android APK par architecture...${NC}"
    $FLUTTER_CMD build apk --release --split-per-abi -t "$TARGET_FILE"

    # app-arm64-v8a-release.apk, app-armeabi-v7a-release.apk, app-x86_64-release.apk
    local file abi
    while IFS= read -r file; do
        [ -n "$file" ] || continue
        abi="$(basename "$file" -release.apk)"
        abi="${abi#app-}"
        rename_artifact "$file" "sary360-${abi}-${ARTIFACT_SUFFIX}.apk"
        rm -f "${file}.sha1"
    done < <(find build/app/outputs/flutter-apk -maxdepth 1 -name "app-*-release.apk" -newer "$BUILD_MARKER" 2>/dev/null)
}

build_android_aab() {
    echo -e "${BLUE}▶ Build Android App Bundle...${NC}"
    $FLUTTER_CMD build appbundle --release -t "$TARGET_FILE"

    local aab="build/app/outputs/bundle/release/app-release.aab"
    if [ -f "$aab" ]; then
        rename_artifact "$aab" "sary360-${ARTIFACT_SUFFIX}.aab"
    fi
}

build_ios_ipa() {
    echo -e "${BLUE}▶ Build iOS IPA...${NC}"
    $FLUTTER_CMD build ipa --release -t "$TARGET_FILE"

    # Le nom de l'IPA dépend du nom de produit : ne prendre que ceux de ce run
    local ipa_dir="build/ios/ipa"
    local file
    if [ -d "$ipa_dir" ]; then
        while IFS= read -r file; do
            [ -n "$file" ] || continue
            rename_artifact "$file" "$(basename "$file" .ipa)-${ARTIFACT_SUFFIX}.ipa"
        done < <(find "$ipa_dir" -maxdepth 1 -name "*.ipa" -newer "$BUILD_MARKER" 2>/dev/null)
    fi

    local archive="build/ios/archive/Runner.xcarchive"
    if [ -d "$archive" ]; then
        rename_artifact "$archive" "Runner-${ARTIFACT_SUFFIX}.xcarchive"
    fi
}

if [ "$PLATFORM" = "android" ] || [ "$PLATFORM" = "all" ]; then
    case $BUILD_TYPE in
        apk)
            build_android_apk
            ;;
        split)
            build_android_split_apk
            ;;
        aab)
            build_android_aab
            ;;
        both)
            build_android_aab
            build_android_apk
            ;;
    esac
fi
if [ "$PLATFORM" = "ios" ] || [ "$PLATFORM" = "all" ]; then
    build_ios_ipa
fi

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
MINUTES=$((DURATION / 60))
SECONDS=$((DURATION % 60))

# ------------------------------------------------------------------------------
# Rapport de fin de build
# ------------------------------------------------------------------------------
echo -e "\n${GREEN}${BOLD}════════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}${BOLD}🎉 BUILD TERMINÉ AVEC SUCCÈS en ${MINUTES}m ${SECONDS}s !${NC}"
echo -e "${GREEN}${BOLD}════════════════════════════════════════════════════════════════${NC}\n"

if [ ${#OUTPUT_FILES[@]} -gt 0 ]; then
    echo -e "${BOLD}📁 Fichiers générés :${NC}"
    for file in "${OUTPUT_FILES[@]}"; do
        if [ -e "$file" ]; then
            # du fonctionne pour les fichiers (.apk/.aab/.ipa) et les bundles (.xcarchive)
            FILE_SIZE=$(du -sh "$file" | awk '{print $1}')
            echo -e "  • ${CYAN}$file${NC} (${BOLD}$FILE_SIZE${NC})"
            # Liens cliquables dans la plupart des terminaux (iTerm2, VS Code, Terminal.app)
            echo -e "    ↳ Fichier : file://${PROJECT_ROOT}/${file}"
            echo -e "    ↳ Dossier : file://${PROJECT_ROOT}/$(dirname "$file")/"
        fi
    done

    # Sur macOS, proposer d'ouvrir le dossier dans le Finder
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo ""
        read -rp "Ouvrir l'emplacement dans le Finder ? (o/N) : " open_finder
        case $open_finder in
            o|O|y|Y|oui|yes)
                # Sélectionne chaque fichier produit (APK, AAB, IPA, archive) dans le Finder
                for file in "${OUTPUT_FILES[@]}"; do
                    [ -e "$file" ] && open -R "$file"
                done
                ;;
        esac

        # Ouvrir le .xcarchive l'importe dans l'Organizer de Xcode
        for file in "${OUTPUT_FILES[@]}"; do
            if [[ "$file" == *.xcarchive ]]; then
                read -rp "Ouvrir l'archive dans Xcode Organizer ? (o/N) : " open_xcode
                case $open_xcode in
                    o|O|y|Y|oui|yes)
                        open "$file"
                        ;;
                esac
            fi
        done
    fi
else
    echo -e "${YELLOW}ℹ️  Vérifiez les dossiers de sortie :${NC}"
    if [ "$PLATFORM" = "android" ] || [ "$PLATFORM" = "all" ]; then
        echo "  • APK     : file://${PROJECT_ROOT}/build/app/outputs/flutter-apk/"
        echo "  • AAB     : file://${PROJECT_ROOT}/build/app/outputs/bundle/release/"
    fi
    if [ "$PLATFORM" = "ios" ] || [ "$PLATFORM" = "all" ]; then
        echo "  • IPA     : file://${PROJECT_ROOT}/build/ios/ipa/"
        echo "  • Archive : file://${PROJECT_ROOT}/build/ios/archive/"
    fi
fi

echo -e "\n${GREEN}✨ Terminé !${NC}"
