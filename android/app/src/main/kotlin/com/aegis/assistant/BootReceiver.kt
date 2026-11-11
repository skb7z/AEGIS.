package com.aegis.assistant

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** Shown when Android refuses to start the microphone service from the background (Android 14+). */
fun postResumeNotification(ctx: Context) {
    try {
        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (nm.getNotificationChannel("aegis_resume") == null) {
            nm.createNotificationChannel(
                NotificationChannel("aegis_resume", "Aegis resume", NotificationManager.IMPORTANCE_HIGH)
            )
        }
        val pi = PendingIntent.getActivity(
            ctx, 1,
            Intent(ctx, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        val n = Notification.Builder(ctx, "aegis_resume")
            .setContentTitle("Aegis")
            .setContentText("Tap to turn Aegis back on")
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setContentIntent(pi)
            .setAutoCancel(true)
            .build()
        nm.notify(4103, n)
    } catch (_: Exception) {
    }
}

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (!NativePrefs.wakeEnabled(context)) return
        try {
            context.startForegroundService(Intent(context, AegisForegroundService::class.java))
        } catch (_: Exception) {
            postResumeNotification(context)
        }
    }
}
