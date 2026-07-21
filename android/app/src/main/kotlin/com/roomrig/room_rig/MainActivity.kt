package com.roomrig.room_rig

import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import kotlin.math.cos
import kotlin.math.sin

class MainActivity : FlutterActivity() {
	private val channelName = "room_rig/arcore"
	private var trackingPhase = 0.0

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)

		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
			.setMethodCallHandler { call, result ->
				when (call.method) {
					"initializeTracking" -> {
						trackingPhase = 0.0
						result.success(mapOf("ready" to true, "backend" to "android-platform-stub"))
					}

					"updateTracking" -> {
						trackingPhase += 0.08
						result.success(
							mapOf(
								"x" to (1.15 + sin(trackingPhase) * 0.9),
								"y" to 1.5,
								"z" to (1.05 + cos(trackingPhase * 0.75) * 0.9),
								"yaw" to ((trackingPhase * 22.0) % 360.0),
								"pitch" to 0.0,
								"roll" to 0.0,
								"trackingStable" to true
							)
						)
					}

					"disposeTracking" -> {
						result.success(null)
					}

					else -> result.notImplemented()
				}
			}
	}
}
