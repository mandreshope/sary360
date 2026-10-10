import 'package:flutter/services.dart';

import '../../core/math/quaternion.dart';
import '../../domain/services/orientation_source.dart';

/// Orientation fournie par le vecteur de rotation fusionné d'Android
/// (GAME_ROTATION_VECTOR, sinon ROTATION_VECTOR), via le platform channel
/// `sary360/orientation` (android/.../OrientationStreamHandler.kt).
class RotationVectorOrientationSource implements OrientationSource {
  static const _channel = EventChannel('sary360/orientation');

  @override
  String get name => 'Android rotation vector';

  @override
  Stream<OrientationSample> get samples =>
      _channel.receiveBroadcastStream().map((event) {
        final v = (event as List).cast<double>();
        return OrientationSample(Quaternion(v[0], v[1], v[2], v[3]), v[4]);
      });
}
