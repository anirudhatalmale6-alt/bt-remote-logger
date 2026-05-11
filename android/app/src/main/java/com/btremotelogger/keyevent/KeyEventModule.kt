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

  private var pendingHeartRunnable: Runnable? = null
  private var lastVolumeKeyTime = 0L

  private val SWIPE_THRESHOLD = 100f
  private val HEART_DELAY_MS = 300L

  @ReactMethod
  fun startListening() {
    instance = this
  }

  @ReactMethod
  fun stopListening() {
    if (instance == this) {
      instance = null
    }
    cancelPendingHeart()
  }

  @ReactMethod
  fun addListener(eventName: String) {}

  @ReactMethod
  fun removeListeners(count: Int) {}

  fun handleKeyEvent(keyCode: Int, action: Int, deviceName: String): Boolean {
    if (action != KeyEvent.ACTION_DOWN) return true

    when (keyCode) {
      KeyEvent.KEYCODE_VOLUME_UP -> {
        lastVolumeKeyTime = System.currentTimeMillis()
        cancelPendingHeart()
        emitButton("GEAR", "Gear button (Volume Up)")
        return true
      }
      KeyEvent.KEYCODE_VOLUME_DOWN -> {
        lastVolumeKeyTime = System.currentTimeMillis()
        cancelPendingHeart()
        emitButton("CAMERA", "Camera button (Volume Down)")
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

  fun handleTouchEvent(event: MotionEvent) {
    // External touch events are consumed in MainActivity.
    // No additional detection needed here.
  }

  private fun evaluateGesture() {
    val deltaX = hoverLastX - hoverStartX
    val deltaY = hoverLastY - hoverStartY
    val absDeltaX = Math.abs(deltaX)
    val absDeltaY = Math.abs(deltaY)

    if (absDeltaX > SWIPE_THRESHOLD || absDeltaY > SWIPE_THRESHOLD) {
      if (absDeltaY >= absDeltaX) {
        if (deltaY < 0) {
          emitButton("ARROW_UP", "Arrow Up (swipe up)")
        } else {
          emitButton("ARROW_DOWN", "Arrow Down (swipe down)")
        }
      } else {
        if (deltaX < 0) {
          emitButton("ARROW_LEFT", "Arrow Left (swipe left)")
        } else {
          emitButton("ARROW_RIGHT", "Arrow Right (swipe right)")
        }
      }
    } else {
      val timeSinceVolume = System.currentTimeMillis() - lastVolumeKeyTime
      if (timeSinceVolume < HEART_DELAY_MS) {
        return
      }
      cancelPendingHeart()
      pendingHeartRunnable = Runnable {
        val timeSinceVol = System.currentTimeMillis() - lastVolumeKeyTime
        if (timeSinceVol >= HEART_DELAY_MS) {
          emitButton("HEART", "Heart / Like button")
        }
        pendingHeartRunnable = null
      }
      handler.postDelayed(pendingHeartRunnable!!, HEART_DELAY_MS)
    }
  }

  private fun cancelPendingHeart() {
    pendingHeartRunnable?.let {
      handler.removeCallbacks(it)
      pendingHeartRunnable = null
    }
  }

  private fun emitButton(buttonId: String, label: String) {
    val params = Arguments.createMap().apply {
      putString("buttonId", buttonId)
      putString("label", label)
      putDouble("timestamp", System.currentTimeMillis().toDouble())
    }

    try {
      reactApplicationContext
        .getJSModule(DeviceEventManagerModule.RCTDeviceEventEmitter::class.java)
        .emit("onButtonDetected", params)
    } catch (e: Exception) {
      // Context may not be ready
    }
  }

  companion object {
    @JvmStatic
    var instance: KeyEventModule? = null
      private set
  }
}
