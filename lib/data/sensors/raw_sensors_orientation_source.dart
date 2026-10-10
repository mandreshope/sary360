import 'dart:async';

import 'package:sensors_plus/sensors_plus.dart';

import '../../core/math/camera_rotation.dart';
import '../../domain/services/orientation_source.dart';

/// Repli sans platform channel (iOS, appareils sans vecteur de rotation) :
/// orientation calculée à partir de l'accéléromètre et du magnétomètre,
/// lissés. Le cap est plus bruité qu'avec le gyroscope.
class RawSensorsOrientationSource implements OrientationSource {
  @override
  String get name => 'accéléromètre + magnétomètre';

  @override
  Stream<OrientationSample> get samples {
    late StreamController<OrientationSample> controller;
    StreamSubscription<AccelerometerEvent>? accel;
    StreamSubscription<MagnetometerEvent>? magnet;
    var gravity = <double>[0, 0, 9.81];
    List<double>? field;
    const alpha = 0.2; // filtre passe-bas

    List<double> smooth(List<double> prev, double x, double y, double z) => [
      prev[0] + alpha * (x - prev[0]),
      prev[1] + alpha * (y - prev[1]),
      prev[2] + alpha * (z - prev[2]),
    ];

    controller = StreamController<OrientationSample>(
      onListen: () {
        const period = SensorInterval.gameInterval;
        accel = accelerometerEventStream(samplingPeriod: period).listen((e) {
          gravity = smooth(gravity, e.x, e.y, e.z);
          final f = field;
          if (f == null) return;
          final q = CameraRotation.deviceToWorldFromSensors(gravity, f);
          if (q != null) {
            controller.add(
              OrientationSample(q, e.timestamp.microsecondsSinceEpoch / 1e6),
            );
          }
        }, onError: controller.addError);
        magnet = magnetometerEventStream(samplingPeriod: period).listen((e) {
          field = field == null
              ? [e.x, e.y, e.z]
              : smooth(field!, e.x, e.y, e.z);
        }, onError: controller.addError);
      },
      onCancel: () async {
        await accel?.cancel();
        await magnet?.cancel();
      },
    );
    return controller.stream;
  }
}
