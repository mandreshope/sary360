// Interface C du module d'assemblage de Sary360.
//
// Le pipeline (OpenCV, module cv::detail) est appelé depuis Dart via FFI.
// L'appel est bloquant : il doit être exécuté dans un isolate dédié.
// La progression et l'annulation passent par deux pointeurs partagés que
// l'isolate principal lit / écrit pendant le traitement.

#ifndef SARY_STITCHER_H
#define SARY_STITCHER_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32)
#define SARY_EXPORT __declspec(dllexport)
#else
#define SARY_EXPORT __attribute__((visibility("default"))) __attribute__((used))
#endif

/// Codes de retour de sary_stitch (int32_t : la taille d'un enum C dépend
/// du compilateur, ce qui le rend dangereux à travers FFI).
#define SARY_OK 0
#define SARY_ERR_INVALID_ARGS 1
#define SARY_ERR_IMAGE_READ 2
#define SARY_ERR_OUT_OF_MEMORY 3
#define SARY_ERR_CANCELLED 4
#define SARY_ERR_OPENCV 5
#define SARY_ERR_WRITE 6

/// Paramètres d'un assemblage.
typedef struct SaryStitchParams {
  /// Nombre de photos.
  int32_t image_count;

  /// Chemins des JPEG (UTF-8). L'orientation EXIF est appliquée au décodage.
  const char *const *image_paths;

  /// Rotations mesurées par les capteurs : image_count matrices 3×3, ligne
  /// par ligne. Chaque matrice envoie le repère caméra OpenCV (x à droite,
  /// y vers le bas, z vers l'avant) dans le repère monde de la sphère
  /// (y vers le bas, z au centre du panorama).
  const float *rotations;

  /// Champ de vision horizontal d'une photo décodée, en degrés.
  float hfov_deg;

  /// Largeur de l'image équirectangulaire (hauteur = largeur / 2).
  int32_t output_width;

  /// Qualité JPEG de sortie (1-100).
  int32_t jpeg_quality;

  /// Résolutions de travail en mégapixels : détection des points-clés,
  /// recherche des raccords, composition (≤ 0 : résolution d'origine).
  float work_megapix;
  float seam_megapix;
  float compose_megapix;

  /// Nombre maximal de points-clés ORB par photo (≤ 0 : 1500).
  int32_t max_features;

  /// Seules les paires dont les axes de visée sont séparés de moins de cet
  /// angle (degrés) sont mises en correspondance.
  float neighbor_max_angle_deg;

  /// 1 : affiner les rotations par points-clés + bundle adjustment ;
  /// 0 : utiliser directement les rotations des capteurs.
  int32_t refine;

  /// Chemin du JPEG équirectangulaire produit.
  const char *output_path;

  /// Progression 0..1 écrite par le module (peut être NULL). Lue en
  /// parallèle par l'isolate principal.
  float *progress;

  /// Mis à une valeur non nulle par l'isolate principal pour demander
  /// l'annulation (peut être NULL).
  int32_t *cancel;
} SaryStitchParams;

/// Compte rendu d'un assemblage.
typedef struct SaryStitchResult {
  /// 1 si les rotations affinées ont été retenues, 0 si celles des capteurs.
  int32_t refined;

  /// Nombre de paires de photos avec des correspondances fiables.
  int32_t matched_pairs;

  /// Écart médian entre rotations affinées et rotations capteurs (degrés),
  /// ou -1 si l'affinage n'a pas abouti.
  float median_correction_deg;

  /// Durée totale en millisecondes.
  int32_t elapsed_ms;

  /// Message d'erreur ou de diagnostic (UTF-8, terminé par 0).
  char message[256];
} SaryStitchResult;

/// Assemble les photos en une image équirectangulaire 360° (2:1).
/// Renvoie un code SARY_OK / SARY_ERR_*.
SARY_EXPORT int32_t sary_stitch(const SaryStitchParams *params,
                                   SaryStitchResult *result);

/// Version d'OpenCV liée au module (chaîne statique).
SARY_EXPORT const char *sary_opencv_version(void);

#ifdef __cplusplus
}
#endif

#endif  // SARY_STITCHER_H
