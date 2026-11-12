package com.aegis.assistant

import android.content.Context
import android.content.Intent
import android.content.SharedPreferences

/** Shared in-process state between services and the Flutter activity. */
object AegisEvents {
    @Volatile var emitter: ((String, Any?) -> Unit)? = null
    @Volatile var dartReady = false
    @Volatile var activityResumed = false
    @Volatile var pendingWake = false
    @Volatile var onCapture: ((String?, String?) -> Unit)? = null

    fun emit(name: String, args: Any? = null): Boolean {
        val e = emitter ?: return false
        if (!dartReady) return false
        e(name, args)
        return true
    }

    /** Wake word heard. If Flutter is alive we handle it headless (so a running game is not interrupted). */
    fun handleWake(app: Context) {
        if (emit("wake")) return
        pendingWake = true
        try {
            val i = Intent(app, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                .putExtra("wake", true)
            app.startActivity(i)
        } catch (_: Exception) {
        }
    }
}

object NativePrefs {
    fun get(ctx: Context): SharedPreferences =
        ctx.applicationContext.getSharedPreferences("aegis_native", Context.MODE_PRIVATE)

    fun whitelist(ctx: Context): Set<String> =
        get(ctx).getStringSet("whitelist", emptySet()) ?: emptySet()

    fun wakeEnabled(ctx: Context): Boolean = get(ctx).getBoolean("wake_enabled", false)
}
