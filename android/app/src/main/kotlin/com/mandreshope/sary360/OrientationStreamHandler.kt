package com.mandreshope.sary360

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import io.flutter.plugin.common.EventChannel

/**
 * Diffuse l'orientation du téléphone (quaternion appareil → monde) vers Dart.
 *
 * Capteur préféré : GAME_ROTATION_VECTOR (gyroscope + accéléromètre, sans
 * magnétomètre). Pour un panorama seul le cap relatif compte, et l'absence
 * de magnétomètre évite les sauts de cap près des masses métalliques.
 * Repli : ROTATION_VECTOR (avec magnétomètre).
 *
 * Chaque événement : [x, y, z, w, horodatage (s), source (0 = jeu, 1 = rotation)].
 */
class OrientationStreamHandler(context: Context) : EventChannel.StreamHandler, SensorEventListener {
    private val sensorManager = context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
    private val gameSensor: Sensor? = sensorManager.getDefaultSensor(Sensor.TYPE_GAME_ROTATION_VECTOR)
    private val rotationSensor: Sensor? = sensorManager.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)
    private var sink: EventChannel.EventSink? = null
    private val quaternion = FloatArray(4)

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        val sensor = gameSensor ?: rotationSensor
        if (sensor == null) {
            events.error("NO_SENSOR", "Aucun capteur de vecteur de rotation", null)
            return
        }
        sink = events
        sensorManager.registerListener(this, sensor, SensorManager.SENSOR_DELAY_GAME)
    }

    override fun onCancel(arguments: Any?) {
        sensorManager.unregisterListener(this)
        sink = null
    }

    override fun onSensorChanged(event: SensorEvent) {
        // getQuaternionFromVector renvoie [w, x, y, z].
        SensorManager.getQuaternionFromVector(quaternion, event.values)
        val source = if (event.sensor.type == Sensor.TYPE_GAME_ROTATION_VECTOR) 0.0 else 1.0
        sink?.success(
            doubleArrayOf(
                quaternion[1].toDouble(),
                quaternion[2].toDouble(),
                quaternion[3].toDouble(),
                quaternion[0].toDouble(),
                event.timestamp / 1e9,
                source,
            ),
        )
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit

    companion object {
        const val CHANNEL = "sary360/orientation"
    }
}
