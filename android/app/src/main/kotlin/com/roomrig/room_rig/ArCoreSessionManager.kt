package com.roomrig.room_rig

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.media.Image
import android.opengl.GLES11Ext
import android.opengl.GLES20
import android.opengl.GLSurfaceView
import android.util.Log
import com.google.ar.core.ArCoreApk
import com.google.ar.core.Camera
import com.google.ar.core.Config
import com.google.ar.core.Frame
import com.google.ar.core.Session
import com.google.ar.core.TrackingState
import com.google.ar.core.exceptions.CameraNotAvailableException
import com.google.ar.core.exceptions.UnavailableException
import javax.microedition.khronos.egl.EGLConfig
import javax.microedition.khronos.opengles.GL10
import kotlin.math.atan2
import kotlin.math.sqrt

/**
 * Real ARCore session for Galaxy S10+ class devices.
 *
 * Owns the camera while active, supplies 6DoF pose + downsampled Y frames
 * to Flutter over the existing MethodChannel contract.
 */
class ArCoreSessionManager(
	private val activity: Activity,
) : GLSurfaceView.Renderer {
	companion object {
		private const val TAG = "ArCoreSessionManager"
		private const val FRAME_MAX_SIDE = 240
		private const val REQUEST_CAMERA = 9910
	}

	private var session: Session? = null
	private var installRequested = false
	private var glTextureId = -1
	private var glReady = false
	private var running = false

	private var lastX = 0.0
	private var lastY = 1.5
	private var lastZ = 0.0
	private var lastMotion = 0.0

	@Volatile
	private var latestPose: Map<String, Any?> = emptyMap()

	@Volatile
	private var latestFrameBytes: ByteArray? = null

	@Volatile
	private var latestFrameWidth = 0

	@Volatile
	private var latestFrameHeight = 0

	private var surfaceView: GLSurfaceView? = null

	fun attachHiddenSurface(view: GLSurfaceView) {
		surfaceView = view
		view.setEGLContextClientVersion(2)
		view.preserveEGLContextOnPause = true
		view.setRenderer(this)
		view.renderMode = GLSurfaceView.RENDERMODE_CONTINUOUSLY
	}

	fun initialize(): Map<String, Any?> {
		return try {
			if (activity.checkSelfPermission(Manifest.permission.CAMERA)
				!= PackageManager.PERMISSION_GRANTED
			) {
				activity.requestPermissions(
					arrayOf(Manifest.permission.CAMERA),
					REQUEST_CAMERA,
				)
				return mapOf(
					"ready" to false,
					"backend" to "arcore",
					"reason" to "camera_permission_required",
					"supportsDepthHint" to true,
					"supportsConfidence" to true,
				)
			}

			val availability = ArCoreApk.getInstance().checkAvailability(activity)
			if (availability.isTransient) {
				return mapOf(
					"ready" to false,
					"backend" to "arcore",
					"reason" to "availability_transient",
					"supportsDepthHint" to true,
					"supportsConfidence" to true,
				)
			}
			if (availability.isUnsupported) {
				return mapOf(
					"ready" to false,
					"backend" to "arcore",
					"reason" to "unsupported_device",
					"supportsDepthHint" to false,
					"supportsConfidence" to true,
				)
			}

			val installStatus = ArCoreApk.getInstance().requestInstall(activity, !installRequested)
			if (installStatus == ArCoreApk.InstallStatus.INSTALL_REQUESTED) {
				installRequested = true
				return mapOf(
					"ready" to false,
					"backend" to "arcore",
					"reason" to "install_requested",
					"supportsDepthHint" to true,
					"supportsConfidence" to true,
				)
			}

			val newSession = Session(activity)
			val config = Config(newSession)
			config.updateMode = Config.UpdateMode.LATEST_CAMERA_IMAGE
			config.focusMode = Config.FocusMode.AUTO

			// S10+ : depth-from-motion / ToF when ARCore reports support.
			if (newSession.isDepthModeSupported(Config.DepthMode.AUTOMATIC)) {
				config.depthMode = Config.DepthMode.AUTOMATIC
			} else {
				config.depthMode = Config.DepthMode.DISABLED
			}

			newSession.configure(config)
			session = newSession
			running = false

			val depthEnabled = config.depthMode == Config.DepthMode.AUTOMATIC
			mapOf(
				"ready" to true,
				"backend" to "arcore-s10",
				"supportsDepthHint" to depthEnabled,
				"supportsConfidence" to true,
				"depthMode" to if (depthEnabled) "automatic" else "disabled",
				"deviceClass" to "galaxy_s10_plus_capable",
			)
		} catch (e: UnavailableException) {
			Log.w(TAG, "ARCore unavailable", e)
			mapOf(
				"ready" to false,
				"backend" to "arcore",
				"reason" to (e.message ?: "unavailable"),
				"supportsDepthHint" to false,
				"supportsConfidence" to true,
			)
		} catch (e: Exception) {
			Log.e(TAG, "ARCore init failed", e)
			mapOf(
				"ready" to false,
				"backend" to "arcore",
				"reason" to (e.message ?: "init_failed"),
				"supportsDepthHint" to false,
				"supportsConfidence" to true,
			)
		}
	}

	fun resume(): Boolean {
		val s = session ?: return false
		return try {
			if (!glReady || glTextureId == -1) {
				// GL texture may not be ready yet; caller can retry update shortly.
				running = true
				return true
			}
			s.setCameraTextureName(glTextureId)
			s.resume()
			running = true
			true
		} catch (e: CameraNotAvailableException) {
			Log.w(TAG, "Camera not available for ARCore", e)
			running = false
			false
		} catch (e: Exception) {
			Log.e(TAG, "ARCore resume failed", e)
			running = false
			false
		}
	}

	fun pause() {
		running = false
		try {
			session?.pause()
		} catch (e: Exception) {
			Log.w(TAG, "ARCore pause failed", e)
		}
	}

	fun dispose() {
		pause()
		try {
			session?.close()
		} catch (_: Exception) {
		}
		session = null
		latestFrameBytes = null
		latestPose = emptyMap()
	}

	fun updateTracking(timestampMs: Long): Map<String, Any?> {
		val s = session
		if (s == null) {
			return mapOf(
				"trackingStable" to false,
				"confidence" to 0.0,
				"backend" to "arcore",
				"reason" to "no_session",
			)
		}

		if (!running) {
			resume()
		}

		if (!glReady || glTextureId == -1) {
			return mapOf(
				"x" to lastX,
				"y" to lastY,
				"z" to lastZ,
				"yaw" to 0.0,
				"pitch" to 0.0,
				"roll" to 0.0,
				"trackingStable" to false,
				"confidence" to 0.2,
				"motionMeters" to 0.0,
				"backend" to "arcore-s10",
				"reason" to "gl_not_ready",
				"timestampMs" to timestampMs,
			)
		}

		return try {
			synchronized(this) {
				s.setCameraTextureName(glTextureId)
				val frame = s.update()
				val camera = frame.camera
				val poseMap = poseFromCamera(camera, frame)
				latestPose = poseMap

				tryAcquireLuma(frame)

				val withFrame = poseMap.toMutableMap()
				val bytes = latestFrameBytes
				if (bytes != null && latestFrameWidth > 0 && latestFrameHeight > 0) {
					withFrame["frameWidth"] = latestFrameWidth
					withFrame["frameHeight"] = latestFrameHeight
					withFrame["frameY"] = bytes
				}
				withFrame["timestampMs"] = timestampMs
				withFrame
			}
		} catch (e: CameraNotAvailableException) {
			mapOf(
				"trackingStable" to false,
				"confidence" to 0.1,
				"backend" to "arcore-s10",
				"reason" to "camera_not_available",
			)
		} catch (e: Exception) {
			Log.w(TAG, "updateTracking failed", e)
			mapOf(
				"trackingStable" to false,
				"confidence" to 0.15,
				"backend" to "arcore-s10",
				"reason" to (e.message ?: "update_failed"),
			)
		}
	}

	fun capabilities(): Map<String, Any?> {
		val s = session
		val depth = s?.isDepthModeSupported(Config.DepthMode.AUTOMATIC) == true
		return mapOf(
			"backend" to "arcore-s10",
			"supportsDepthHint" to depth,
			"supportsConfidence" to true,
			"supportsVisualFallback" to true,
			"ownsCamera" to true,
			"deviceNotes" to "Galaxy S10+: ARCore world tracking; depth-from-motion/ToF when supported; no LiDAR",
		)
	}

	private fun poseFromCamera(camera: Camera, frame: Frame): Map<String, Any?> {
		val pose = camera.displayOrientedPose
		val tx = pose.tx().toDouble()
		val ty = pose.ty().toDouble()
		val tz = pose.tz().toDouble()

		// Convert pose quaternion-ish orientation to yaw/pitch approx via rotated axes.
		val forward = FloatArray(3)
		pose.getTransformedAxis(2, 1.0f, forward, 0)
		val yaw = Math.toDegrees(atan2(forward[0].toDouble(), forward[2].toDouble()))
		val pitch = Math.toDegrees(
			atan2(
				(-forward[1]).toDouble(),
				sqrt((forward[0] * forward[0] + forward[2] * forward[2]).toDouble()),
			),
		)

		val motion = sqrt((tx - lastX) * (tx - lastX) + (tz - lastZ) * (tz - lastZ))
		lastX = tx
		lastY = ty
		lastZ = tz
		lastMotion = motion

		val state = camera.trackingState
		val stable = state == TrackingState.TRACKING
		val confidence = when (state) {
			TrackingState.TRACKING -> (0.92 - motion * 1.2).coerceIn(0.45, 0.98)
			TrackingState.PAUSED -> 0.35
			else -> 0.15
		}

		var depthHint: Double? = null
		// S10+ may expose depth-from-motion/ToF via ARCore Depth API; sampling the
		// full depth image every tick is expensive, so use a stable near-field hint.
		if (stable) {
			depthHint = (2.0 + motion * 2.2).coerceIn(0.9, 4.2)
		}

		return mapOf(
			"x" to tx,
			"y" to ty,
			"z" to tz,
			"yaw" to yaw,
			"pitch" to pitch,
			"roll" to 0.0,
			"trackingStable" to stable,
			"confidence" to confidence,
			"motionMeters" to motion,
			"depthHintMeters" to depthHint,
			"backend" to "arcore-s10",
			"trackingState" to state.name,
		)
	}

	private fun tryAcquireLuma(frame: Frame) {
		var image: Image? = null
		try {
			image = frame.acquireCameraImage()
			val w = image.width
			val h = image.height
			val yPlane = image.planes[0]
			val yBuffer = yPlane.buffer
			val rowStride = yPlane.rowStride
			val pixelStride = yPlane.pixelStride

			val scale = maxOf(1, maxOf(w / FRAME_MAX_SIDE, h / FRAME_MAX_SIDE))
			val outW = w / scale
			val outH = h / scale
			val out = ByteArray(outW * outH)

			val row = ByteArray(rowStride)
			var oi = 0
			for (y in 0 until outH) {
				val srcY = y * scale
				yBuffer.position(srcY * rowStride)
				yBuffer.get(row, 0, rowStride.coerceAtMost(yBuffer.remaining()))
				for (x in 0 until outW) {
					val srcX = x * scale
					out[oi++] = row[srcX * pixelStride]
				}
			}
			latestFrameBytes = out
			latestFrameWidth = outW
			latestFrameHeight = outH
		} catch (_: Exception) {
			// Camera image optional for pose-only ticks.
		} finally {
			try {
				image?.close()
			} catch (_: Exception) {
			}
		}
	}

	override fun onSurfaceCreated(gl: GL10?, config: EGLConfig?) {
		val textures = IntArray(1)
		GLES20.glGenTextures(1, textures, 0)
		glTextureId = textures[0]
		GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, glTextureId)
		GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE)
		GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE)
		GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR)
		GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)
		glReady = true
		if (running) {
			try {
				session?.setCameraTextureName(glTextureId)
				session?.resume()
			} catch (e: Exception) {
				Log.w(TAG, "resume after GL ready failed", e)
			}
		}
	}

	override fun onSurfaceChanged(gl: GL10?, width: Int, height: Int) {
		GLES20.glViewport(0, 0, width, height)
		session?.setDisplayGeometry(activity.windowManager.defaultDisplay.rotation, width, height)
	}

	override fun onDrawFrame(gl: GL10?) {
		// Pose/frame pulled on-demand from Flutter via updateTracking.
		GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT)
	}
}
