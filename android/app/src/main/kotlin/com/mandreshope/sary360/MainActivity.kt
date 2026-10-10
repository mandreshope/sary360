package com.mandreshope.sary360

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Orientation du téléphone pour la capture (voir OrientationStreamHandler).
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, OrientationStreamHandler.CHANNEL)
            .setStreamHandler(OrientationStreamHandler(applicationContext))
    }
}
