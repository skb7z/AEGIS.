package com.aegis.assistant

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager

object AegisNotif {
    const val CHANNEL = "aegis_service"

    fun ensureChannel(ctx: Context) {
        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (nm.getNotificationChannel(CHANNEL) == null) {
            val ch = NotificationChannel(CHANNEL, "Aegis background", NotificationManager.IMPORTANCE_LOW)
            ch.setShowBadge(false)
            nm.createNotificationChannel(ch)
        }
    }

    fun build(ctx: Context, text: String): Notification {
        ensureChannel(ctx)
        val pi = PendingIntent.getActivity(
            ctx, 0, Intent(ctx, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        return Notification.Builder(ctx, CHANNEL)
            .setContentTitle("Aegis")
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setOngoing(true)
            .setContentIntent(pi)
            .build()
    }
}

class AegisForegroundService : Service() {
    companion object {
        @Volatile var running = false
        private const val ID = 4101
    }

    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        try {
            val n = AegisNotif.build(this, "Aegis is listening")
            // The microphone service type only exists from Android 11 (API 30).
            if (Build.VERSION.SDK_INT >= 30) {
                startForeground(ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
            } else {
                startForeground(ID, n)
            }
            running = true
            if (wakeLock == null) {
                val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "aegis:wake").apply {
                    setReferenceCounted(false)
                    acquire()
                }
            }
            VoskEngine.start(applicationContext, VoskEngine.Mode.WAKE)
        } catch (e: Exception) {
            postResumeNotification(applicationContext)
            running = false
            stopSelf()
        }
        return START_STICKY
    }

    override fun onDestroy() {
        running = false
        try { wakeLock?.let { if (it.isHeld) it.release() } } catch (_: Exception) {}
        wakeLock = null
        VoskEngine.shutdown()
        super.onDestroy()
    }
}
