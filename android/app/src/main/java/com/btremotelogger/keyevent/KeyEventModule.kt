package com.btremotelogger.keyevent

import android.os.Handler
import android.os.Looper
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.InputDevice
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReactContextBaseJavaModule
import com.facebook.react.bridge.ReactMethod
import com.facebook.react.modules.core.DeviceEventManagerModule

class KeyEventModule(reactContext: ReactApplicationContext) : ReactContextBaseJavaModule(reactContext) {

  override fun getName(): String = "KeyEventListener"

  private val handler = Handler(Looper.getMainLooper())

  private var hoverStartX = 0f
  private var hoverStartY = 0f
  private var hoverLastX = 0f
  private var hoverLastY = 0f
  private var isTracking = false

  private var pendingVolumeKey = false
  private var pendingClick = false
  private var pendingRunnable: Runnable? = null
  private val DETECT_WINDOW_MS = 400L

  private val SWIPE_THRESHOLD = 100f

  // Cooldown: ignore events for a short period after emitting a button
  private var lastEmitTime = 0L
  private val COOLDOWN_MS = 600L

  @ReactMethod
  fun startListening() {
    instance = this
  }

  @ReactMethod
  fun stopListening() {
    if (instance == this) {
      instance = null
    }
    cancelPending()
  }

  @ReactMethod
  fun addListener(eventName: String) {}

  @ReactMethod
  fun removeListeners(count: Int) {}

  private fun isInCooldown(): Boolean {
    return System.currentTimeMillis() - lastEmitTime < COOLDOWN_MS
  }

  fun handleKeyEvent(keyCode: Int, action: Int, deviceName: String): Boolean {
    if (action != KeyEvent.ACTION_DOWN) return true

    when (keyCode) {
      KeyEvent.KEYCODE_VOLUME_UP, KeyEvent.KEYCODE_VOLUME_DOWN -> {
        if (!isInCooldown()) {
          onVolumeKeyReceived()
        }
        return true
      }
      else -> {
        return false
      }
    }
  }

  fun handleMotionEvent(event: MotionEvent) {
    when (event.actionMasked) {
      MotionEvent.ACTION_HOVER_ENTER -> {
        hoverStartX = event.x
        hoverStartY = event.y
        hoverLastX = event.x
        hoverLastY = event.y
        isTracking = true
      }
      MotionEvent.ACTION_HOVER_MOVE -> {
        if (isTracking) {
          hoverLastX = event.x
          hoverLastY = event.y
        }
      }
      MotionEvent.ACTION_HOVER_EXIT -> {
        if (isTracking) {
          evaluateGesture()
          isTracking = false
        }
      }
      11 -> { // ACTION_BUTTON_PRESS
        if (!isTracking) {
          hoverStartX = event.x
          hoverStartY = event.y
          isTracking = true
        }
      }
      12 -> { // ACTION_BUTTON_RELEASE
        if (isTracking) {
          hoverLastX = event.x
          hoverLastY = event.y
          evaluateGesture()
          isTracking = false
        }
      }
    }
  }

  fun handleTouchEvent(event: MotionEvent) {}

  private fun evaluateGesture() {
    if (isInCooldown()) return

    val deltaX = hoverLastX - hoverStartX
    val deltaY = hoverLastY - hoverStartY
    val absDeltaX = Math.abs(deltaX)
    val absDeltaY = Math.abs(deltaY)

    if (absDeltaX > SWIPE_THRESHOLD || absDeltaY > SWIPE_THRESHOLD) {
      if (absDeltaY >= absDeltaX) {
        if (deltaY < 0) {
          emitButton("ARROW_UP", "Arrow Up")
        } else {
          emitButton("ARROW_DOWN", "Arrow Down")
        }
      } else {
        if (deltaX < 0) {
          emitButton("ARROW_LEFT", "Arrow Left")
        } else {
          emitButton("ARROW_RIGHT", "Arrow Right")
        }
      }
    } else {
      onClickReceived()
    }
  }

  private fun onVolumeKeyReceived() {
    if (pendingClick) {
      cancelPending()
      emitButton("GEAR", "Gear button")
    } else {
      pendingVolumeKey = true
      schedulePendingResolve()
    }
  }

  private fun onClickReceived() {
    if (isInCooldown()) return

    if (pendingVolumeKey) {
      cancelPending()
      emitButton("GEAR", "Gear button")
    } else {
      pendingClick = true
      schedulePendingResolve()
    }
  }

  private fun schedulePendingResolve() {
    if (pendingRunnable != null) return

    pendingRunnable = Runnable {
      if (isInCooldown()) {
        pendingVolumeKey = false
        pendingClick = false
        pendingRunnable = null
        return@Runnable
      }
      if (pendingVolumeKey && !pendingClick) {
        emitButton("CAMERA", "Camera button")
      } else if (pendingClick && !pendingVolumeKey) {
        emitButton("HEART", "Heart / Like button")
      } else if (pendingVolumeKey && pendingClick) {
        emitButton("GEAR", "Gear button")
      }
      pendingVolumeKey = false
      pendingClick = false
      pendingRunnable = null
    }
    handler.postDelayed(pendingRunnable!!, DETECT_WINDOW_MS)
  }

  private fun cancelPending() {
    pendingRunnable?.let {
      handler.removeCallbacks(it)
      pendingRunnable = null
    }
    pendingVolumeKey = false
    pendingClick = false
  }

  private fun emitButton(buttonId: String, label: String) {
    lastEmitTime = System.currentTimeMillis()
    cancelPending()

    val params = Arguments.createMap().apply {
      putString("buttonId", buttonId)
      putString("label", label)
      putDouble("timestamp", System.currentTimeMillis().toDouble())
    }

    try {
      reactApplicationContext
        .getJSModule(DeviceEventManagerModule.RCTDeviceEventEmitter::class.java)
        .emit("onButtonDetected", params)
    } catch (e: Exception) {}
  }

  companion object {
    @JvmStatic
    var instance: KeyEventModule? = null
      private set
  }
}
