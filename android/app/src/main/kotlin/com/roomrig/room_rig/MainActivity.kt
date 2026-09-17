package com.roomrig.room_rig

import android.opengl.GLSurfaceView
import android.view.ViewGroup
import android.widget.FrameLayout
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Hosts a hidden GLSurfaceView for ARCore camera textures and exposes
 * pose + luma frames to Flutter via [room_rig/arcore].
 */
class MainActivity : FlutterActivity() {
	private val channelName = "room_rig/arcore"
	private var arSession: ArCoreSessionManager? = null
	private var hiddenGlView: GLSurfaceView? = null

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)

		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
			.setMethodCallHandler { call, result ->
				when (call.method) {
					"initializeTracking" -> {
						val manager = ensureSession()
						val init = manager.initialize()
						val ready = (init["ready"] as? Boolean) == true
						if (ready) {
							manager.resume()
						}
						result.success(init)
					}

					"updateTracking" -> {
						val manager = arSession
						if (manager == null) {
							result.success(
								mapOf(
									"trackingStable" to false,
									"confidence" to 0.0,
									"backend" to "arcore",
									"reason" to "not_initialized",
								),
							)
							return@setMethodCallHandler
						}
						val timestampMs = (call.argument<Number>("timestampMs"))?.toLong() ?: System.currentTimeMillis()
						result.success(manager.updateTracking(timestampMs))
					}

					"disposeTracking" -> {
						arSession?.dispose()
						arSession = null
						removeHiddenGlView()
						result.success(null)
					}

					"getCapabilities" -> {
						result.success(
							arSession?.capabilities()
								?: mapOf(
									"backend" to "arcore-s10",
									"supportsDepthHint" to true,
									"supportsConfidence" to true,
									"supportsVisualFallback" to true,
									"ownsCamera" to true,
									"deviceNotes" to "Galaxy S10+: install Play Services for AR; world tracking + optional depth",
								),
						)
					}

					else -> result.notImplemented()
				}
			}
	}

	private fun ensureSession(): ArCoreSessionManager {
		val existing = arSession
		if (existing != null) return existing

		val manager = ArCoreSessionManager(this)
		val view = GLSurfaceView(this)
		view.layoutParams = FrameLayout.LayoutParams(64, 64)
		view.alpha = 0f
		// Keep in hierarchy so EGL context stays alive; tiny and transparent.
		addContentView(view, view.layoutParams)
		manager.attachHiddenSurface(view)
		hiddenGlView = view
		arSession = manager
		return manager
	}

	private fun removeHiddenGlView() {
		val view = hiddenGlView ?: return
		val parent = view.parent as? ViewGroup
		parent?.removeView(view)
		hiddenGlView = null
	}

	override fun onResume() {
		super.onResume()
		arSession?.resume()
	}

	override fun onPause() {
		arSession?.pause()
		super.onPause()
	}

	override fun onDestroy() {
		arSession?.dispose()
		arSession = null
		removeHiddenGlView()
		super.onDestroy()
	}
}
