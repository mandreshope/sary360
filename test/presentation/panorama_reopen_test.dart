import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sary360/presentation/widgets/custom_panorama.dart' as pw;

void main() {
  testWidgets('la visionneuse recharge sa texture à chaque ouverture', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('pano');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/pano.png')
      ..writeAsBytesSync(
        img.encodePng(
          img.Image(width: 64, height: 32)..clear(img.ColorRgb8(200, 50, 50)),
        ),
      );

    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(navigatorKey: navKey, home: const SizedBox()),
    );

    Future<dynamic> open() async {
      navKey.currentState!.push(
        MaterialPageRoute(
          builder: (_) => Scaffold(body: pw.Panorama(child: Image.file(file))),
        ),
      );
      // Le décodage du fichier se fait hors de l'horloge simulée.
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
          () => Future.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      return tester.state(find.byType(pw.Panorama));
    }

    final first = await open();
    expect(first.scene.texture, isNotNull);

    navKey.currentState!.pop();
    await tester.pumpAndSettle();
    // La fermeture libère la texture et vide le cache pour cette image.
    expect(first.scene.texture, isNull);
    expect(imageCache.containsKey(FileImage(file)), isFalse);

    final second = await open();
    expect(second.scene.texture, isNotNull);
    expect(second.surface.mesh.texture, isNotNull);
  });
}
