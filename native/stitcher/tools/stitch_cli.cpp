// Outil de test en ligne de commande du module d'assemblage (hors app).
//
// Usage : stitch_cli <liste.txt>
// Format de la liste :
//   ligne 1 : <sortie.jpg> <hfov_deg> <largeur> <refine 0|1>
//   lignes suivantes : <photo.jpg> r00 r01 r02 r10 r11 r12 r20 r21 r22
// Les rotations suivent la convention de SaryStitchParams::rotations.

#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>

#include "sary_stitcher.h"

int main(int argc, char** argv) {
  // Floor eraser mode:
  //   stitch_cli --erase-nadir <in.jpg> <out.jpg> <model.onnx> <deg> [before.jpg after.jpg]
  if (argc >= 6 && std::string(argv[1]) == "--erase-nadir") {
    SaryNadirParams nadir{};
    nadir.input_path = argv[2];
    nadir.output_path = argv[3];
    nadir.model_path = argv[4];
    nadir.mask_deg = static_cast<float>(std::atof(argv[5]));
    nadir.jpeg_quality = 90;
    nadir.preview_before_path = argc > 6 ? argv[6] : nullptr;
    nadir.preview_after_path = argc > 7 ? argv[7] : nullptr;
    char message[256] = {0};
    const int32_t status = sary_erase_nadir(&nadir, message, sizeof(message));
    std::printf("statut=%d message=%s\n", status, message);
    return status;
  }
  if (argc < 2) {
    std::fprintf(stderr, "usage: %s <liste.txt>\n", argv[0]);
    return 2;
  }
  std::ifstream in(argv[1]);
  std::string output;
  float hfov = 0;
  int width = 0, refine = 1;
  in >> output >> hfov >> width >> refine;

  std::vector<std::string> paths;
  std::vector<float> rotations;
  std::string line;
  while (std::getline(in, line)) {
    std::istringstream ls(line);
    std::string path;
    if (!(ls >> path)) continue;
    paths.push_back(path);
    for (int k = 0; k < 9; ++k) {
      float v = 0;
      ls >> v;
      rotations.push_back(v);
    }
  }
  std::vector<const char*> cpaths;
  for (const auto& p : paths) cpaths.push_back(p.c_str());

  float progress = 0;
  int32_t cancel = 0;
  SaryStitchParams params{};
  params.image_count = static_cast<int32_t>(paths.size());
  params.image_paths = cpaths.data();
  params.rotations = rotations.data();
  params.hfov_deg = hfov;
  params.output_width = width;
  params.jpeg_quality = 90;
  // Réglages surchargeables pour les essais : SARY_WORK_MP, SARY_SEAM_MP,
  // SARY_FEATURES.
  const auto env = [](const char* name, float fallback) {
    const char* v = std::getenv(name);
    return v ? static_cast<float>(std::atof(v)) : fallback;
  };
  params.work_megapix = env("SARY_WORK_MP", 0.6f);
  params.seam_megapix = env("SARY_SEAM_MP", 0.05f);
  params.max_features = static_cast<int32_t>(env("SARY_FEATURES", 0));
  params.compose_megapix = -1;
  // (hFov + vFov) / 2 comme l'app ; 68° pour l'ultra grand angle.
  params.neighbor_max_angle_deg = env("SARY_NEIGHBOR", 68.0f);
  params.refine = refine;
  // Nadir removal: SARY_INPAINT_MODEL=<migan .onnx>, SARY_NADIR_DEG (default 25).
  const char* model = std::getenv("SARY_INPAINT_MODEL");
  params.inpaint_model_path = model;
  params.nadir_mask_deg = model ? env("SARY_NADIR_DEG", 25.0f) : 0.0f;
  params.output_path = output.c_str();
  params.progress = &progress;
  params.cancel = &cancel;

  SaryStitchResult result{};
  const int32_t status = sary_stitch(&params, &result);
  std::printf("statut=%d affine=%d paires=%d correction=%.1f duree=%dms message=%s\n", status,
              result.refined, result.matched_pairs, result.median_correction_deg,
              result.elapsed_ms, result.message);
  return status;
}
