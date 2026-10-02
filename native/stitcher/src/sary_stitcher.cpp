// Pipeline d'assemblage sphérique de Sary360 (OpenCV, module cv::detail).
//
// Étapes :
//   1. Décodage, réduction à la résolution de travail, points-clés ORB.
//   2. Mise en correspondance des seules photos voisines (d'après les
//      rotations des capteurs), au lieu de toutes les paires.
//   3. Bundle adjustment (BundleAdjusterRay) initialisé avec les rotations
//      des capteurs. En cas d'échec ou de divergence, les rotations des
//      capteurs sont conservées.
//   4. Projection sphérique, compensation d'exposition (BlocksGain),
//      raccords (GraphCut), fusion multibande.
//   5. Remplissage des zones non couvertes par un dégradé flou, écriture JPEG.

#include "sary_stitcher.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <new>
#include <string>
#include <vector>

#include <opencv2/core.hpp>
#include <opencv2/core/ocl.hpp>
#include <opencv2/features2d.hpp>
#include <opencv2/imgcodecs.hpp>
#include <opencv2/imgproc.hpp>
#include <opencv2/stitching/detail/blenders.hpp>
#include <opencv2/stitching/detail/camera.hpp>
#include <opencv2/stitching/detail/exposure_compensate.hpp>
#include <opencv2/stitching/detail/matchers.hpp>
#include <opencv2/stitching/detail/autocalib.hpp>
#include <opencv2/stitching/detail/motion_estimators.hpp>
#include <opencv2/stitching/detail/seam_finders.hpp>
#include <opencv2/stitching/detail/warpers.hpp>

#ifdef __ANDROID__
#include <android/log.h>
#define SARY_LOG(...) __android_log_print(ANDROID_LOG_INFO, "SaryStitcher", __VA_ARGS__)
#else
#define SARY_LOG(...) (std::fprintf(stderr, "[SaryStitcher] " __VA_ARGS__), std::fputc('\n', stderr))
#endif

namespace {

using cv::Mat;
using cv::Point;
using cv::Rect;
using cv::Size;
using cv::UMat;
using Clock = std::chrono::steady_clock;

/// Levée quand l'utilisateur annule ; interceptée dans sary_stitch.
struct Cancelled {};

/// Contexte partagé : paramètres, progression, chronométrage.
class Context {
 public:
  explicit Context(const SaryStitchParams& p) : p_(p), start_(Clock::now()) {}

  const SaryStitchParams& params() const { return p_; }

  // Accès volatile : ces cellules sont lues / écrites par un autre thread
  // (isolate principal) pendant le traitement.
  void progress(float v) const {
    if (p_.progress) {
      *static_cast<volatile float*>(p_.progress) = std::min(1.f, std::max(0.f, v));
    }
  }

  /// Interrompt le traitement si une annulation a été demandée.
  void checkCancel() const {
    if (p_.cancel && *static_cast<volatile int32_t*>(p_.cancel) != 0) throw Cancelled{};
  }

  /// Journalise la durée de l'étape écoulée depuis le dernier appel.
  void lap(const char* stage) {
    const auto now = Clock::now();
    const auto ms =
        std::chrono::duration_cast<std::chrono::milliseconds>(now - last_).count();
    SARY_LOG("%s : %lld ms", stage, static_cast<long long>(ms));
    last_ = now;
  }

  int32_t elapsedMs() const {
    return static_cast<int32_t>(std::chrono::duration_cast<std::chrono::milliseconds>(
                                    Clock::now() - start_)
                                    .count());
  }

 private:
  const SaryStitchParams& p_;
  Clock::time_point start_;
  Clock::time_point last_ = Clock::now();
};

constexpr double kPi = 3.14159265358979323846;
constexpr double kDeg = kPi / 180.0;

/// En dessous de ce nombre de points-clés, une photo (ciel, mur uni) est
/// exclue de la mise en correspondance : FLANN échoue (knn = 2) sur des
/// ensembles trop petits. Elle reste placée grâce aux capteurs.
constexpr int kMinKeypoints = 40;

/// Confiance minimale d'une paire pour le bundle adjustment
/// (inliers / (8 + 0,3 · correspondances), convention OpenCV).
constexpr double kPairConfidence = 1.0;

/// Seuil FAST d'ORB (20 par défaut dans OpenCV) : abaissé pour trouver des
/// points sur les surfaces peu texturées (murs, plafond).
constexpr int kOrbFastThreshold = 8;

/// Validation de l'affinage d'une composante : il doit réduire nettement
/// l'écart entre les rayons des points appariés, sans dériver.
constexpr double kMinErrorReduction = 0.8;   // erreur après ≤ 80 % de l'avant
constexpr double kMaxRayErrorDeg = 2.0;      // erreur résiduelle maximale
constexpr double kMaxCorrectionDeg = 35.0;   // écart maximal aux capteurs
constexpr double kMaxFocalRatio = 1.35;

/// Angle (radians) de la rotation relative entre deux matrices.
double rotationAngle(const Mat& a, const Mat& b) {
  Mat a64, b64;
  a.convertTo(a64, CV_64F);
  b.convertTo(b64, CV_64F);
  const Mat d = a64.t() * b64;
  const double c = (cv::trace(d)[0] - 1.0) / 2.0;
  return std::acos(std::min(1.0, std::max(-1.0, c)));
}

/// Angle (radians) entre les axes de visée (colonne z) de deux caméras.
double viewAngle(const Mat& a, const Mat& b) {
  double dot = 0;
  for (int k = 0; k < 3; ++k) dot += a.at<float>(k, 2) * b.at<float>(k, 2);
  return std::acos(std::min(1.0, std::max(-1.0, dot)));
}

/// Rotation globale G minimisant Σ‖G·refined_i − sensor_i‖ (Procrustes).
/// Le bundle adjustment recentre le repère sur une caméra : G ramène les
/// rotations affinées dans le repère des capteurs (gravité, cap).
Mat alignToSensors(const std::vector<Mat>& refined, const std::vector<Mat>& sensor,
                   const std::vector<int>& indices) {
  Mat m = Mat::zeros(3, 3, CV_64F);
  for (int i : indices) {
    Mat r64, s64;
    refined[i].convertTo(r64, CV_64F);
    sensor[i].convertTo(s64, CV_64F);
    m += s64 * r64.t();
  }
  cv::SVD svd(m);
  Mat g = svd.u * svd.vt;
  if (cv::determinant(g) < 0) {
    Mat u = svd.u.clone();
    u.col(2) *= -1;
    g = u * svd.vt;
  }
  return g;
}

/// Écart angulaire moyen (radians) entre les rayons des points appariés
/// (inliers des paires fiables) pour un jeu de caméras. Indépendant d'une
/// rotation globale : mesure la cohérence interne de l'alignement.
double meanRayError(const std::vector<cv::detail::ImageFeatures>& features,
                    const std::vector<cv::detail::MatchesInfo>& pairs,
                    const std::vector<cv::detail::CameraParams>& cams) {
  const auto rayMatrix = [](const cv::detail::CameraParams& c) {
    Mat k64, r64;
    c.K().convertTo(k64, CV_64F);
    c.R.convertTo(r64, CV_64F);
    return cv::Matx33d(Mat(r64 * k64.inv()));
  };
  double sum = 0;
  long count = 0;
  for (const auto& m : pairs) {
    if (m.src_img_idx < 0 || m.src_img_idx >= m.dst_img_idx || m.confidence <= kPairConfidence) {
      continue;
    }
    const cv::Matx33d a = rayMatrix(cams[m.src_img_idx]);
    const cv::Matx33d b = rayMatrix(cams[m.dst_img_idx]);
    for (size_t k = 0; k < m.matches.size(); ++k) {
      if (!m.inliers_mask[k]) continue;
      const cv::Point2f p = features[m.src_img_idx].keypoints[m.matches[k].queryIdx].pt;
      const cv::Point2f q = features[m.dst_img_idx].keypoints[m.matches[k].trainIdx].pt;
      cv::Vec3d ra = a * cv::Vec3d(p.x, p.y, 1.0);
      cv::Vec3d rb = b * cv::Vec3d(q.x, q.y, 1.0);
      const double c = ra.dot(rb) / (cv::norm(ra) * cv::norm(rb));
      sum += std::acos(std::min(1.0, std::max(-1.0, c)));
      ++count;
    }
  }
  return count > 0 ? sum / count : 0.0;
}

/// Composantes reliées du graphe des paires fiables (au moins 2 photos).
std::vector<std::vector<int>> connectedComponents(
    int n, const std::vector<cv::detail::MatchesInfo>& pairs) {
  std::vector<int> parent(n);
  for (int i = 0; i < n; ++i) parent[i] = i;
  const auto find = [&](int x) {
    while (parent[x] != x) x = parent[x] = parent[parent[x]];
    return x;
  };
  for (const auto& m : pairs) {
    if (m.src_img_idx >= 0 && m.src_img_idx < m.dst_img_idx && m.confidence > kPairConfidence) {
      parent[find(m.src_img_idx)] = find(m.dst_img_idx);
    }
  }
  std::vector<std::vector<int>> groups(n);
  for (int i = 0; i < n; ++i) groups[find(i)].push_back(i);
  std::vector<std::vector<int>> result;
  for (auto& g : groups) {
    if (g.size() >= 2) result.push_back(std::move(g));
  }
  return result;
}

/// Sous-problème (points-clés + paires) restreint aux photos [indices],
/// renumérotées de 0 à indices.size() − 1.
void extractSubset(const std::vector<int>& indices,
                   const std::vector<cv::detail::ImageFeatures>& features,
                   const std::vector<cv::detail::MatchesInfo>& pairs, int n,
                   std::vector<cv::detail::ImageFeatures>& subFeatures,
                   std::vector<cv::detail::MatchesInfo>& subPairs) {
  const int m = static_cast<int>(indices.size());
  subFeatures.clear();
  subPairs.assign(static_cast<size_t>(m) * m, cv::detail::MatchesInfo());
  for (int a = 0; a < m; ++a) {
    subFeatures.push_back(features[indices[a]]);
    subFeatures.back().img_idx = a;
    for (int b = 0; b < m; ++b) {
      cv::detail::MatchesInfo info = pairs[indices[a] * n + indices[b]];
      if (info.src_img_idx >= 0) {
        info.src_img_idx = a;
        info.dst_img_idx = b;
      }
      subPairs[a * m + b] = info;
    }
  }
}

/// Remplit les zones non couvertes (masque nul) par un dégradé flou des
/// couleurs voisines : convolution normalisée à basse résolution, avec
/// bouclage horizontal (le bord gauche d'un équirectangulaire touche le
/// droit), puis fondu doux à la lisière des zones couvertes.
void fillUncovered(Mat& pano, const Mat& coverage) {
  if (static_cast<size_t>(cv::countNonZero(coverage)) == coverage.total()) return;

  const int lowW = std::max(64, pano.cols / 32);
  const Size low(lowW, lowW / 2);
  Mat img, weight;
  cv::resize(pano, img, low, 0, 0, cv::INTER_AREA);
  cv::resize(coverage, weight, low, 0, 0, cv::INTER_AREA);
  img.convertTo(img, CV_32FC3);
  weight.convertTo(weight, CV_32F, 1.0 / 255.0);
  // Les pixels partiellement couverts ont été moyennés avec du noir :
  // on ne garde que les pixels entièrement couverts comme sources.
  cv::threshold(weight, weight, 0.99, 1.0, cv::THRESH_BINARY);

  Mat weighted;
  {
    std::vector<Mat> ch;
    cv::split(img, ch);
    for (auto& c : ch) c = c.mul(weight);
    cv::merge(ch, weighted);
  }

  // Flou avec bouclage horizontal : marge copiée de l'autre bord.
  const auto wrapBlur = [&](const Mat& src, double sigma) {
    const int pad = std::min(src.cols / 2, static_cast<int>(sigma * 3) + 1);
    Mat padded, blurred;
    cv::copyMakeBorder(src, padded, 0, 0, pad, pad, cv::BORDER_WRAP);
    cv::GaussianBlur(padded, blurred, Size(), sigma, sigma, cv::BORDER_REPLICATE);
    return blurred(Rect(pad, 0, src.cols, src.rows)).clone();
  };

  Mat fill(low, CV_32FC3, cv::Scalar::all(0));
  Mat filled(low, CV_8U, cv::Scalar(0));
  for (double sigma = lowW / 64.0; sigma <= lowW * 2.0; sigma *= 2.0) {
    const Mat num = wrapBlur(weighted, sigma);
    const Mat den = wrapBlur(weight, sigma);
    for (int y = 0; y < low.height; ++y) {
      for (int x = 0; x < low.width; ++x) {
        if (filled.at<uchar>(y, x) || den.at<float>(y, x) < 1e-3f) continue;
        fill.at<cv::Vec3f>(y, x) = num.at<cv::Vec3f>(y, x) / den.at<float>(y, x);
        filled.at<uchar>(y, x) = 255;
      }
    }
    if (static_cast<size_t>(cv::countNonZero(filled)) == filled.total()) break;
  }
  // Dernier recours (aucune photo exploitable) : gris neutre.
  fill.setTo(cv::Scalar::all(128), filled == 0);

  // Lissage final pour un dégradé sans marches.
  fill = wrapBlur(fill, lowW / 48.0);
  Mat fillFull;
  cv::resize(fill, fillFull, pano.size(), 0, 0, cv::INTER_CUBIC);

  // Alpha : 1 à l'intérieur des zones couvertes, 0 dans les trous, avec une
  // transition qui reste du côté couvert (les pixels photo ne sont jamais
  // mélangés avec le noir des trous).
  const int feather = std::max(3, pano.cols / 256);
  Mat alpha;
  cv::erode(coverage, alpha,
            cv::getStructuringElement(cv::MORPH_ELLIPSE, Size(2 * feather + 1, 2 * feather + 1)));
  alpha.convertTo(alpha, CV_32F, 1.0 / 255.0);
  cv::GaussianBlur(alpha, alpha, Size(), feather / 2.0);
  Mat cov;
  coverage.convertTo(cov, CV_32F, 1.0 / 255.0);
  alpha = alpha.mul(cov);

  Mat panoF;
  pano.convertTo(panoF, CV_32FC3);
  std::vector<Mat> pc, fc;
  cv::split(panoF, pc);
  cv::split(fillFull, fc);
  for (int k = 0; k < 3; ++k) {
    pc[k] = pc[k].mul(alpha) + fc[k].mul(1.0 - alpha);
  }
  cv::merge(pc, panoF);
  panoF.convertTo(pano, CV_8UC3);
}

double scaleFor(double megapix, double area) {
  if (megapix <= 0) return 1.0;
  return std::min(1.0, std::sqrt(megapix * 1e6 / area));
}

void writeMessage(SaryStitchResult* r, const std::string& msg) {
  std::snprintf(r->message, sizeof(r->message), "%s", msg.c_str());
}

int32_t run(Context& ctx, SaryStitchResult* result) {
  const SaryStitchParams& p = ctx.params();
  const int n = p.image_count;
  cv::ocl::setUseOpenCL(false);

  // ── 1. Décodage et points-clés ─────────────────────────────────────────
  Mat first = cv::imread(p.image_paths[0], cv::IMREAD_COLOR);
  if (first.empty()) {
    writeMessage(result, std::string("Lecture impossible : ") + p.image_paths[0]);
    return SARY_ERR_IMAGE_READ;
  }
  const Size fullSize = first.size();
  const double area = static_cast<double>(fullSize.area());
  const double workScale = scaleFor(p.work_megapix, area);
  const double seamScale = scaleFor(p.seam_megapix, area);
  const double composeScale = scaleFor(p.compose_megapix, area);
  first.release();

  // Focale déduite de l'angle de vue horizontal, à la résolution de travail.
  const double workWidth = fullSize.width * workScale;
  const double workFocal = (workWidth / 2.0) / std::tan(p.hfov_deg * kDeg / 2.0);

  cv::Ptr<cv::Feature2D> orb =
      cv::ORB::create(p.max_features > 0 ? p.max_features : 3000, 1.2f, 8, 31, 0, 2,
                      cv::ORB::HARRIS_SCORE, 31, kOrbFastThreshold);
  std::vector<cv::detail::ImageFeatures> features(n);
  std::vector<UMat> seamImages(n);
  std::vector<cv::detail::CameraParams> sensorCams(n);
  std::vector<Mat> sensorR(n);

  for (int i = 0; i < n; ++i) {
    ctx.checkCancel();
    Mat full = cv::imread(p.image_paths[i], cv::IMREAD_COLOR);
    if (full.empty()) {
      writeMessage(result, std::string("Lecture impossible : ") + p.image_paths[i]);
      return SARY_ERR_IMAGE_READ;
    }
    if (full.size() != fullSize) {
      writeMessage(result, "Les photos n'ont pas toutes la même taille");
      return SARY_ERR_INVALID_ARGS;
    }
    Mat work, seam;
    cv::resize(full, work, Size(), workScale, workScale, cv::INTER_AREA);
    cv::resize(full, seam, Size(), seamScale, seamScale, cv::INTER_AREA);
    seam.copyTo(seamImages[i]);

    cv::detail::computeImageFeatures(orb, work, features[i]);
    features[i].img_idx = i;

    Mat r(3, 3, CV_32F);
    for (int k = 0; k < 9; ++k) r.at<float>(k / 3, k % 3) = p.rotations[i * 9 + k];
    sensorR[i] = r;

    auto& cam = sensorCams[i];
    cam.focal = workFocal;
    cam.aspect = 1.0;
    cam.ppx = work.cols / 2.0;
    cam.ppy = work.rows / 2.0;
    cam.R = r.clone();
    cam.t = Mat::zeros(3, 1, CV_64F);

    ctx.progress(0.25f * (i + 1) / n);
  }
  ctx.lap("décodage + points-clés");

  // ── 2. Mise en correspondance des voisines uniquement ─────────────────
  std::vector<cv::detail::MatchesInfo> pairwise;
  int candidatePairs = 0;
  if (p.refine) {
    Mat mask(n, n, CV_8U, cv::Scalar(0));
    const double maxAngle = p.neighbor_max_angle_deg * kDeg;
    for (int i = 0; i < n; ++i) {
      if (static_cast<int>(features[i].keypoints.size()) < kMinKeypoints) continue;
      for (int j = i + 1; j < n; ++j) {
        if (static_cast<int>(features[j].keypoints.size()) < kMinKeypoints) continue;
        if (viewAngle(sensorR[i], sensorR[j]) < maxAngle) {
          mask.at<uchar>(i, j) = 1;
          ++candidatePairs;
        }
      }
    }
    ctx.checkCancel();
    if (candidatePairs > 0) {
      cv::detail::BestOf2NearestMatcher matcher(false, 0.3f);
      matcher(features, pairwise, mask.getUMat(cv::ACCESS_READ));
      matcher.collectGarbage();
    }
  }
  // Diagnostic détaillé (variable d'environnement SARY_DEBUG, outil CLI).
  if (std::getenv("SARY_DEBUG") != nullptr) {
    for (int i = 0; i < n; ++i) {
      SARY_LOG("photo %d : %zu points-clés", i, features[i].keypoints.size());
    }
    for (const auto& m : pairwise) {
      if (m.src_img_idx >= 0 && m.src_img_idx < m.dst_img_idx) {
        SARY_LOG("paire %d-%d : %zu corresp., %d inliers, confiance %.2f", m.src_img_idx,
                 m.dst_img_idx, m.matches.size(), m.num_inliers, m.confidence);
      }
    }
  }

  if (std::getenv("SARY_DEBUG") != nullptr && !pairwise.empty()) {
    // Focale déduite des homographies des paires (indépendante du FOV supposé).
    for (const auto& m : pairwise) {
      if (m.src_img_idx < 0 || m.src_img_idx >= m.dst_img_idx || m.confidence <= kPairConfidence) {
        continue;
      }
      double f0 = 0, f1 = 0;
      bool ok0 = false, ok1 = false;
      cv::detail::focalsFromHomography(m.H.inv(), f0, f1, ok0, ok1);
      if (ok0 && ok1) {
        const double f = std::sqrt(f0 * f1);
        SARY_LOG("focale paire %d-%d : %.0f px → HFOV %.1f°", m.src_img_idx, m.dst_img_idx, f,
                 2 * std::atan(workWidth / 2 / f) / kDeg);
      }
    }
  }

  int matchedPairs = 0;
  for (const auto& m : pairwise) {
    if (m.src_img_idx < m.dst_img_idx && m.confidence > kPairConfidence) ++matchedPairs;
  }
  result->matched_pairs = matchedPairs;
  ctx.progress(0.40f);
  ctx.lap("mise en correspondance");
  SARY_LOG("%d paires candidates, %d fiables", candidatePairs, matchedPairs);

  // ── 3. Affinage (bundle adjustment) par composante reliée ────────────
  // Chaque groupe de photos reliées par des correspondances fiables est
  // affiné séparément (BundleAdjusterRay, initialisé avec les capteurs),
  // puis replacé dans le repère des capteurs. Les photos isolées et les
  // groupes dont l'affinage n'améliore pas l'alignement gardent les
  // rotations des capteurs.
  std::vector<cv::detail::CameraParams> cams = sensorCams;
  for (auto& c : cams) c.R = c.R.clone();
  result->refined = 0;
  result->median_correction_deg = -1.f;
  int refinedPhotos = 0;
  std::vector<bool> isRefined(n, false);
  std::vector<double> acceptedCorrections;
  const bool debug = std::getenv("SARY_DEBUG") != nullptr;

  if (p.refine && matchedPairs >= 1) {
    for (const auto& comp : connectedComponents(n, pairwise)) {
      ctx.checkCancel();
      const int m = static_cast<int>(comp.size());
      std::vector<cv::detail::ImageFeatures> subFeatures;
      std::vector<cv::detail::MatchesInfo> subPairs;
      extractSubset(comp, features, pairwise, n, subFeatures, subPairs);

      std::vector<cv::detail::CameraParams> before, refined;
      std::vector<Mat> compSensorR;
      for (int idx : comp) {
        before.push_back(sensorCams[idx]);
        before.back().R = sensorCams[idx].R.clone();
        compSensorR.push_back(sensorR[idx]);
      }
      refined = before;
      for (auto& c : refined) c.R = c.R.clone();
      const double errBefore = meanRayError(subFeatures, subPairs, before) / kDeg;

      try {
        cv::detail::BundleAdjusterRay adjuster;
        adjuster.setConfThresh(kPairConfidence);
        adjuster.setTermCriteria(
            cv::TermCriteria(cv::TermCriteria::COUNT + cv::TermCriteria::EPS, 200, 1e-4));
        if (!adjuster(subFeatures, subPairs, refined)) {
          SARY_LOG("groupe de %d photos : bundle adjustment en échec", m);
          continue;
        }
      } catch (const cv::Exception& e) {
        SARY_LOG("groupe de %d photos : %s", m, e.what());
        continue;
      }

      // Retour dans le repère des capteurs (le BA recentre sur une photo).
      std::vector<Mat> refinedR(m);
      std::vector<int> all(m);
      for (int k = 0; k < m; ++k) {
        refinedR[k] = refined[k].R;
        all[k] = k;
      }
      const Mat g = alignToSensors(refinedR, compSensorR, all);
      bool focalOk = true;
      std::vector<double> corrections;
      for (int k = 0; k < m; ++k) {
        Mat r64;
        refined[k].R.convertTo(r64, CV_64F);
        Mat(g * r64).convertTo(refined[k].R, CV_32F);
        const double ratio = refined[k].focal / workFocal;
        focalOk = focalOk && std::isfinite(ratio) && ratio <= kMaxFocalRatio &&
                  ratio >= 1.0 / kMaxFocalRatio;
        corrections.push_back(rotationAngle(refined[k].R, compSensorR[k]) / kDeg);
        if (debug) {
          SARY_LOG("  photo %d : correction %.1f°, focale %.0f (initiale %.0f)", comp[k],
                   corrections.back(), refined[k].focal, workFocal);
        }
      }
      const double errAfter = meanRayError(subFeatures, subPairs, refined) / kDeg;
      const double maxCorr = *std::max_element(corrections.begin(), corrections.end());
      const bool accept = focalOk && maxCorr <= kMaxCorrectionDeg &&
                          errAfter <= kMaxRayErrorDeg &&
                          errAfter <= errBefore * kMinErrorReduction;
      SARY_LOG("groupe de %d photos : écart des rayons %.2f° → %.2f°, correction max %.1f° : %s",
               m, errBefore, errAfter, maxCorr, accept ? "affiné" : "rejeté");
      if (!accept) continue;

      for (int k = 0; k < m; ++k) {
        cams[comp[k]] = refined[k];
        isRefined[comp[k]] = true;
      }
      refinedPhotos += m;
      acceptedCorrections.insert(acceptedCorrections.end(), corrections.begin(),
                                 corrections.end());
    }
  }
  // Auto-calibration : la focale réelle peut différer de celle déduite du
  // champ de vision théorique (correction de distorsion de l'appareil, qui
  // recadre l'image). Avec assez de photos affinées, leur focale médiane est
  // appliquée aux photos placées par les capteurs.
  if (refinedPhotos >= 5) {
    std::vector<double> focals;
    for (int i = 0; i < n; ++i) {
      if (isRefined[i]) focals.push_back(cams[i].focal);
    }
    std::sort(focals.begin(), focals.end());
    const double median = focals[focals.size() / 2];
    for (int i = 0; i < n; ++i) {
      if (!isRefined[i]) cams[i].focal = median;
    }
    SARY_LOG("focale médiane des photos affinées : %.0f px (théorique %.0f)", median, workFocal);
  }
  if (!acceptedCorrections.empty()) {
    std::sort(acceptedCorrections.begin(), acceptedCorrections.end());
    result->median_correction_deg =
        static_cast<float>(acceptedCorrections[acceptedCorrections.size() / 2]);
    result->refined = 1;
  }
  SARY_LOG("%d photos affinées sur %d", refinedPhotos, n);
  features.clear();
  pairwise.clear();
  ctx.progress(0.50f);
  ctx.lap("affinage");

  // ── 4a. Projection basse résolution : exposition et raccords ──────────
  // Échelle du warper sphérique : largeur finale = 2π · échelle.
  const double composeWarpScale = p.output_width / (2.0 * kPi);
  const double seamWarpScale = composeWarpScale * seamScale / composeScale;
  auto seamWarper = cv::makePtr<cv::detail::SphericalWarper>(static_cast<float>(seamWarpScale));

  const auto scaledK = [&](const cv::detail::CameraParams& c, double imgScale) {
    cv::detail::CameraParams s = c;
    const double f = imgScale / workScale;
    s.focal *= f;
    s.ppx *= f;
    s.ppy *= f;
    Mat k;
    s.K().convertTo(k, CV_32F);
    return k;
  };

  std::vector<Point> seamCorners(n);
  std::vector<UMat> seamWarped(n), seamMasks(n);
  for (int i = 0; i < n; ++i) {
    ctx.checkCancel();
    const Mat k = scaledK(cams[i], seamScale);
    seamCorners[i] = seamWarper->warp(seamImages[i], k, cams[i].R, cv::INTER_LINEAR,
                                      cv::BORDER_REFLECT, seamWarped[i]);
    UMat mask(seamImages[i].size(), CV_8U, cv::Scalar::all(255));
    seamWarper->warp(mask, k, cams[i].R, cv::INTER_NEAREST, cv::BORDER_CONSTANT,
                     seamMasks[i]);
    ctx.progress(0.50f + 0.10f * (i + 1) / n);
  }
  seamImages.clear();

  auto compensator =
      cv::detail::ExposureCompensator::createDefault(cv::detail::ExposureCompensator::GAIN_BLOCKS);
  compensator->feed(seamCorners, seamWarped, seamMasks);
  ctx.checkCancel();
  ctx.progress(0.65f);
  ctx.lap("projection + exposition");

  {
    std::vector<UMat> seamWarpedF(n);
    for (int i = 0; i < n; ++i) seamWarped[i].convertTo(seamWarpedF[i], CV_32F);
    cv::detail::GraphCutSeamFinder seamFinder(
        cv::detail::GraphCutSeamFinderBase::COST_COLOR);
    seamFinder.find(seamWarpedF, seamCorners, seamMasks);
  }
  seamWarped.clear();
  ctx.checkCancel();
  ctx.progress(0.75f);
  ctx.lap("raccords");

  // ── 4b. Composition pleine résolution ─────────────────────────────────
  auto composeWarper =
      cv::makePtr<cv::detail::SphericalWarper>(static_cast<float>(composeWarpScale));
  const int outW = p.output_width;
  const int outH = p.output_width / 2;
  // Marge : les bords projetés peuvent déborder d'un pixel du canevas.
  const int pad = 4;
  const Rect canvas(-outW / 2 - pad, -pad, outW + 2 * pad, outH + 2 * pad);

  cv::detail::MultiBandBlender blender(false);
  const double blendWidth = std::sqrt(static_cast<double>(outW) * outH) * 0.05;
  blender.setNumBands(std::max(1, static_cast<int>(std::ceil(std::log2(blendWidth))) - 1));
  blender.prepare(canvas);

  for (int i = 0; i < n; ++i) {
    ctx.checkCancel();
    Mat full = cv::imread(p.image_paths[i], cv::IMREAD_COLOR);
    if (full.empty()) {
      writeMessage(result, std::string("Lecture impossible : ") + p.image_paths[i]);
      return SARY_ERR_IMAGE_READ;
    }
    if (composeScale < 1.0) {
      cv::resize(full, full, Size(), composeScale, composeScale, cv::INTER_AREA);
    }
    const Mat k = scaledK(cams[i], composeScale);

    Mat warped, warpedMask;
    const Point corner = composeWarper->warp(full, k, cams[i].R, cv::INTER_LINEAR,
                                             cv::BORDER_REFLECT, warped);
    Mat mask(full.size(), CV_8U, cv::Scalar::all(255));
    composeWarper->warp(mask, k, cams[i].R, cv::INTER_NEAREST, cv::BORDER_CONSTANT,
                        warpedMask);
    full.release();

    compensator->apply(i, corner, warped, warpedMask);

    // Raccord trouvé en basse résolution, agrandi à la taille projetée.
    Mat seamMask, dilated;
    cv::dilate(seamMasks[i], dilated, Mat());
    cv::resize(dilated, seamMask, warpedMask.size(), 0, 0, cv::INTER_LINEAR_EXACT);
    warpedMask &= seamMask;

    Mat warpedS;
    warped.convertTo(warpedS, CV_16S);
    blender.feed(warpedS, warpedMask, corner);
    ctx.progress(0.75f + 0.20f * (i + 1) / n);
  }
  seamMasks.clear();
  ctx.lap("composition");

  Mat blended, blendedMask;
  blender.blend(blended, blendedMask);
  ctx.checkCancel();

  Mat pano, coverage;
  blended(Rect(pad, pad, outW, outH)).convertTo(pano, CV_8UC3);
  blendedMask(Rect(pad, pad, outW, outH)).copyTo(coverage);
  blended.release();
  blendedMask.release();

  // ── 5. Zones non couvertes et écriture ────────────────────────────────
  fillUncovered(pano, coverage);
  ctx.progress(0.98f);

  const std::vector<int> jpegParams = {cv::IMWRITE_JPEG_QUALITY,
                                       std::min(100, std::max(1, p.jpeg_quality))};
  if (!cv::imwrite(p.output_path, pano, jpegParams)) {
    writeMessage(result, std::string("Écriture impossible : ") + p.output_path);
    return SARY_ERR_WRITE;
  }
  ctx.lap("fusion + remplissage + écriture");
  ctx.progress(1.0f);

  writeMessage(result, std::to_string(refinedPhotos) + " photos affinées sur " +
                           std::to_string(n) + ", les autres placées par les capteurs");
  return SARY_OK;
}

}  // namespace

extern "C" int32_t sary_stitch(const SaryStitchParams* params, SaryStitchResult* result) {
  if (result == nullptr) return SARY_ERR_INVALID_ARGS;
  std::memset(result, 0, sizeof(*result));
  result->median_correction_deg = -1.f;

  if (params == nullptr || params->image_count < 1 || params->image_paths == nullptr ||
      params->rotations == nullptr || params->output_path == nullptr ||
      params->output_width < 64 || params->output_width % 2 != 0 || params->hfov_deg <= 1.f ||
      params->hfov_deg >= 179.f) {
    writeMessage(result, "Paramètres invalides");
    return SARY_ERR_INVALID_ARGS;
  }

  Context ctx(*params);
  int32_t status;
  try {
    status = run(ctx, result);
  } catch (const Cancelled&) {
    writeMessage(result, "Assemblage annulé");
    status = SARY_ERR_CANCELLED;
  } catch (const std::bad_alloc&) {
    writeMessage(result, "Mémoire insuffisante");
    status = SARY_ERR_OUT_OF_MEMORY;
  } catch (const cv::Exception& e) {
    writeMessage(result, e.what());
    status = e.code == cv::Error::StsNoMem ? SARY_ERR_OUT_OF_MEMORY : SARY_ERR_OPENCV;
  } catch (const std::exception& e) {
    writeMessage(result, e.what());
    status = SARY_ERR_OPENCV;
  }
  result->elapsed_ms = ctx.elapsedMs();
  SARY_LOG("terminé (statut %d) en %d ms : %s", status, result->elapsed_ms, result->message);
  return status;
}

extern "C" const char* sary_opencv_version(void) { return CV_VERSION; }
