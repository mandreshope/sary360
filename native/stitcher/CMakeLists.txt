# Module natif d'assemblage de Sary360 (libsary_stitcher.so).
#
# OpenCV est lié en statique depuis l'OpenCV Android SDK : seuls les modules
# utilisés sont embarqués. Chemin du SDK, par ordre de priorité :
#   1. -DOpenCV_DIR=<sdk>/sdk/native/jni (passé par Gradle, voir
#      android/app/build.gradle.kts et la clé opencv.dir de local.properties) ;
#   2. variable d'environnement OPENCV_ANDROID_SDK ;
#   3. third_party/OpenCV-android-sdk à la racine du projet.

cmake_minimum_required(VERSION 3.22.1)
project(sary_stitcher LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

if(NOT OpenCV_DIR)
  if(DEFINED ENV{OPENCV_ANDROID_SDK})
    set(OpenCV_DIR "$ENV{OPENCV_ANDROID_SDK}/sdk/native/jni")
  else()
    set(OpenCV_DIR "${CMAKE_CURRENT_LIST_DIR}/../../third_party/OpenCV-android-sdk/sdk/native/jni")
  endif()
endif()

set(OpenCV_STATIC ON)
find_package(OpenCV REQUIRED
  COMPONENTS core imgproc imgcodecs features2d flann calib3d stitching)

add_library(sary_stitcher SHARED src/sary_stitcher.cpp)

target_include_directories(sary_stitcher PUBLIC include)
target_include_directories(sary_stitcher PRIVATE ${OpenCV_INCLUDE_DIRS})

# Symboles masqués par défaut : seule l'API C (SARY_EXPORT) est visible,
# ce qui permet à l'éditeur de liens d'écarter le code OpenCV inutilisé.
set_target_properties(sary_stitcher PROPERTIES
  CXX_VISIBILITY_PRESET hidden
  VISIBILITY_INLINES_HIDDEN ON)

target_compile_options(sary_stitcher PRIVATE -O2 -Wall -Wextra -fexceptions -frtti)

target_link_libraries(sary_stitcher PRIVATE ${OpenCV_LIBS})

if(ANDROID)
  target_link_libraries(sary_stitcher PRIVATE log)
  target_link_options(sary_stitcher PRIVATE
    -Wl,--gc-sections
    -Wl,--exclude-libs,ALL
    # Pages de 16 Ko : requis par Google Play pour Android 15+.
    -Wl,-z,max-page-size=16384)
endif()

# Outil de test en ligne de commande (désactivé dans le build de l'app).
option(SARY_BUILD_CLI "Construire l'outil stitch_cli" OFF)
if(SARY_BUILD_CLI)
  add_executable(stitch_cli tools/stitch_cli.cpp)
  target_link_libraries(stitch_cli PRIVATE sary_stitcher)
endif()
