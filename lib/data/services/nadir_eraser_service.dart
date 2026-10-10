import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/constants/app_constants.dart';
import '../../domain/models/panorama.dart';
import '../native/sary_stitcher_bindings.g.dart';
import 'photo_sphere_xmp.dart';

/// Result of a nadir removal preview: the edited panorama (not applied yet)
/// and top-down views of the floor before / after.
class NadirPreview {
  const NadirPreview({
    required this.maskDeg,
    required this.resultPath,
    required this.beforePath,
    required this.afterPath,
  });

  /// Radius (degrees) of the rebuilt disc around the nadir.
  final double maskDeg;
  final String resultPath;
  final String beforePath;
  final String afterPath;
}

/// Failure of the nadir removal, with a user-facing message.
class NadirEraseException implements Exception {
  const NadirEraseException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Manual removal of the photographer's feet / tripod / shadow at the bottom
/// of a panorama, with the on-device MI-GAN inpainting model (MIT license,
/// assets/models). The original image is kept so the edit can be undone.
class NadirEraserService {
  static const _modelAsset = 'assets/models/migan_512_generator.onnx';
  static const _modelFile = 'migan_512_generator.onnx';

  /// Folder (inside the panoramas folder) keeping originals before editing.
  static const _originalsFolder = 'originals';

  /// Copies the bundled model to the app support folder once: the native
  /// module needs a file path.
  Future<String> _modelPath() async {
    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}/models/$_modelFile');
    final data = await rootBundle.load(_modelAsset);
    if (!file.existsSync() || file.lengthSync() != data.lengthInBytes) {
      await file.parent.create(recursive: true);
      await file.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
    }
    return file.path;
  }

  /// Runs the removal on a copy of [panorama] and returns the preview.
  Future<NadirPreview> preview(Panorama panorama, double maskDeg) async {
    final model = await _modelPath();
    final temp = await getTemporaryDirectory();
    final dir = Directory(
      '${temp.path}/nadir/${DateTime.now().millisecondsSinceEpoch}',
    );
    await dir.create(recursive: true);
    final request = _NadirRequest(
      inputPath: panorama.stitchedImagePath,
      outputPath: '${dir.path}/result.jpg',
      modelPath: model,
      maskDeg: maskDeg,
      beforePath: '${dir.path}/before.jpg',
      afterPath: '${dir.path}/after.jpg',
    );
    final (status, message) = await _runInIsolate(request);
    if (status != SARY_OK) {
      throw NadirEraseException(switch (status) {
        SARY_ERR_OUT_OF_MEMORY => 'Mémoire insuffisante pour retoucher le sol.',
        SARY_ERR_IMAGE_READ =>
          'Cette image n\'est pas une sphère 360° complète.',
        _ => 'Retouche impossible : $message',
      });
    }
    // OpenCV rewrites the JPEG without metadata: restore the Photo Sphere XMP.
    final result = File(request.outputPath);
    final size = await _panoramaSize(panorama.stitchedImagePath);
    await result.writeAsBytes(
      injectPhotoSphereXmp(await result.readAsBytes(), size.$1, size.$2),
    );
    return NadirPreview(
      maskDeg: maskDeg,
      resultPath: request.outputPath,
      beforePath: request.beforePath,
      afterPath: request.afterPath,
    );
  }

  /// Replaces the panorama with the previewed edit, keeping the original.
  Future<void> apply(Panorama panorama, NadirPreview preview) async {
    final original = await _originalFile(panorama);
    final current = File(panorama.stitchedImagePath);
    if (!original.existsSync()) {
      await original.parent.create(recursive: true);
      await current.copy(original.path);
    }
    await File(preview.resultPath).copy(current.path);
  }

  /// Whether an unedited original is available for [panorama].
  Future<bool> hasOriginal(Panorama panorama) async =>
      (await _originalFile(panorama)).existsSync();

  /// Restores the unedited panorama.
  Future<void> restore(Panorama panorama) async {
    final original = await _originalFile(panorama);
    if (!original.existsSync()) return;
    await original.copy(panorama.stitchedImagePath);
    await original.delete();
  }

  Future<File> _originalFile(Panorama panorama) async {
    final appDir = await getApplicationDocumentsDirectory();
    final name = panorama.stitchedImagePath.split('/').last;
    return File(
      '${appDir.path}/${AppConstants.panoramasFolder}/$_originalsFolder/$name',
    );
  }

  /// Image size read from the header, without decoding the pixels.
  static Future<(int, int)> _panoramaSize(String path) async {
    final buffer = await ui.ImmutableBuffer.fromFilePath(path);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    final size = (descriptor.width, descriptor.height);
    descriptor.dispose();
    buffer.dispose();
    return size;
  }

  // ═══════════════════════════════════════════════════════════════════
  //  ISOLATE: blocking call to the native module (≈ 2 s)
  // ═══════════════════════════════════════════════════════════════════

  /// Created in a static method so the closure only captures the request.
  static Future<(int, String)> _runInIsolate(_NadirRequest request) =>
      Isolate.run(() => _erase(request));

  static (int, String) _erase(_NadirRequest req) {
    final library = Platform.isAndroid
        ? ffi.DynamicLibrary.open('libsary_stitcher.so')
        : ffi.DynamicLibrary.process();
    final bindings = SaryStitcherBindings(library);
    return using((arena) {
      const messageSize = 256;
      final message = arena<ffi.Char>(messageSize);
      final params = SaryNadirParams.$allocate(
        arena,
        input_path: req.inputPath.toNativeUtf8(allocator: arena).cast(),
        output_path: req.outputPath.toNativeUtf8(allocator: arena).cast(),
        model_path: req.modelPath.toNativeUtf8(allocator: arena).cast(),
        mask_deg: req.maskDeg,
        jpeg_quality: AppConstants.jpegQuality,
        preview_before_path: req.beforePath
            .toNativeUtf8(allocator: arena)
            .cast(),
        preview_after_path: req.afterPath.toNativeUtf8(allocator: arena).cast(),
      );
      final status = bindings.sary_erase_nadir(params, message, messageSize);
      return (status, message.cast<Utf8>().toDartString());
    });
  }
}

/// Request sent to the isolate (plain values only).
class _NadirRequest {
  const _NadirRequest({
    required this.inputPath,
    required this.outputPath,
    required this.modelPath,
    required this.maskDeg,
    required this.beforePath,
    required this.afterPath,
  });

  final String inputPath;
  final String outputPath;
  final String modelPath;
  final double maskDeg;
  final String beforePath;
  final String afterPath;
}
