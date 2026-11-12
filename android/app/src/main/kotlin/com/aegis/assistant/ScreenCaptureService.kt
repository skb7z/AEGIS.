package com.aegis.assistant

import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import java.io.File
import java.io.FileOutputStream

/** Captures exactly ONE frame, writes a small JPEG to cache, then tears everything down. */
class ScreenCaptureService : Service() {
    private val handler = Handler(Looper.getMainLooper())
    private var projection: MediaProjection? = null
    private var display: VirtualDisplay? = null
    private var reader: ImageReader? = null
    private var finished = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val n = AegisNotif.build(this, "Taking a one-time screenshot")
        try {
            if (Build.VERSION.SDK_INT >= 29) {
                startForeground(4102, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION)
            } else {
                startForeground(4102, n)
            }
        } catch (e: Exception) {
            finish(null, "Cannot start capture service: ${e.message}")
            return START_NOT_STICKY
        }
        val code = intent?.getIntExtra("code", 0) ?: 0
        @Suppress("DEPRECATION")
        val data: Intent? = intent?.getParcelableExtra("data")
        if (data == null) {
            finish(null, "Missing capture permission")
            return START_NOT_STICKY
        }
        // Give the previous app time to come to front.
        handler.postDelayed({ capture(code, data) }, 800)
        return START_NOT_STICKY
    }

    private fun capture(code: Int, data: Intent) {
        try {
            val mpm = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
            val p: MediaProjection = mpm.getMediaProjection(code, data)
                ?: throw IllegalStateException("MediaProjection unavailable")
            projection = p
            p.registerCallback(object : MediaProjection.Callback() {}, handler)
            val m = resources.displayMetrics
            val w = m.widthPixels
            val h = m.heightPixels
            val r = ImageReader.newInstance(w, h, PixelFormat.RGBA_8888, 2)
            reader = r
            display = p.createVirtualDisplay(
                "aegis_cap", w, h, m.densityDpi,
                DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR, r.surface, null, handler
            )
            poll(r, w, h, 0)
        } catch (e: Throwable) {
            finish(null, "Capture failed: ${e.message}")
        }
    }

    private fun poll(r: ImageReader, w: Int, h: Int, attempt: Int) {
        if (finished) return
        handler.postDelayed({
            if (finished) return@postDelayed
            val img = try { r.acquireLatestImage() } catch (_: Exception) { null }
            if (img == null) {
                if (attempt >= 6) finish(null, "No frame received") else poll(r, w, h, attempt + 1)
                return@postDelayed
            }
            try {
                val plane = img.planes[0]
                val rowPadding = plane.rowStride - plane.pixelStride * w
                val full = Bitmap.createBitmap(w + rowPadding / plane.pixelStride, h, Bitmap.Config.ARGB_8888)
                full.copyPixelsFromBuffer(plane.buffer)
                val cropped = Bitmap.createBitmap(full, 0, 0, w, h)
                if (cropped !== full) full.recycle()
                val targetW = if (w > 720) 720 else w
                val targetH = h * targetW / w
                val scaled = if (targetW != w) Bitmap.createScaledBitmap(cropped, targetW, targetH, true) else cropped
                if (scaled !== cropped) cropped.recycle()
                val file = File(cacheDir, "aegis_shot.jpg")
                FileOutputStream(file).use { scaled.compress(Bitmap.CompressFormat.JPEG, 70, it) }
                scaled.recycle()
                img.close()
                finish(file.absolutePath, null)
            } catch (e: Throwable) {
                try { img.close() } catch (_: Exception) {}
                finish(null, "Encode failed: ${e.message}")
            }
        }, 600)
    }

    private fun finish(path: String?, error: String?) {
        if (finished) return
        finished = true
        try { display?.release() } catch (_: Exception) {}
        try { reader?.close() } catch (_: Exception) {}
        try { projection?.stop() } catch (_: Exception) {}
        display = null; reader = null; projection = null
        AegisEvents.onCapture?.invoke(path, error)
        AegisEvents.onCapture = null
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        finish(null, "Capture cancelled")
        super.onDestroy()
    }
}
