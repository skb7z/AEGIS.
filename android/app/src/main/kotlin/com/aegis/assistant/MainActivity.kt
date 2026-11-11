package com.aegis.assistant

import android.app.Activity
import android.content.ComponentName
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.Drawable
import android.media.projection.MediaProjectionManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.AlarmClock
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var pendingShot: MethodChannel.Result? = null
    private val reqShot = 7101
    private val main = Handler(Looper.getMainLooper())
    private lateinit var focus: AudioFocusHelper

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        focus = AudioFocusHelper(applicationContext)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "aegis/system")
        channel = ch
        AegisEvents.emitter = { name, args -> main.post { try { ch.invokeMethod(name, args) } catch (_: Exception) {} } }
        ch.setMethodCallHandler { call, result ->
            try {
                handle(call, result)
            } catch (e: Exception) {
                result.error("native", e.message, null)
            }
        }
        if (intent?.getBooleanExtra("wake", false) == true) AegisEvents.pendingWake = true
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.getBooleanExtra("wake", false)) AegisEvents.pendingWake = true
    }

    override fun onResume() {
        super.onResume()
        AegisEvents.activityResumed = true
        if (AegisEvents.dartReady && AegisEvents.pendingWake) {
            AegisEvents.pendingWake = false
            AegisEvents.emit("wake")
        }
    }

    override fun onPause() {
        AegisEvents.activityResumed = false
        super.onPause()
    }

    override fun onDestroy() {
        AegisEvents.emitter = null
        AegisEvents.dartReady = false
        if (::focus.isInitialized) focus.abandon()
        super.onDestroy()
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "ready" -> {
                AegisEvents.dartReady = true
                val p = AegisEvents.pendingWake
                AegisEvents.pendingWake = false
                result.success(p)
            }
            "getApps" -> loadApps(result)
            "setWhitelist" -> {
                val pkgs = call.argument<List<String>>("pkgs") ?: emptyList()
                NativePrefs.get(this).edit().putStringSet("whitelist", pkgs.toSet()).apply()
                result.success(true)
            }
            "status" -> result.success(status())
            "openSetting" -> {
                openSetting(call.argument<String>("which") ?: "appinfo")
                result.success(true)
            }
            "startService" -> {
                NativePrefs.get(this).edit().putBoolean("wake_enabled", true).apply()
                startForegroundService(Intent(this, AegisForegroundService::class.java))
                result.success(true)
            }
            "stopService" -> {
                NativePrefs.get(this).edit().putBoolean("wake_enabled", false).apply()
                stopService(Intent(this, AegisForegroundService::class.java))
                VoskEngine.shutdown()
                result.success(true)
            }
            "pauseWake" -> { VoskEngine.pause(); result.success(true) }
            "resumeWake" -> {
                if (NativePrefs.wakeEnabled(this)) VoskEngine.start(applicationContext, VoskEngine.Mode.WAKE)
                result.success(true)
            }
            "startStopListener" -> { VoskEngine.start(applicationContext, VoskEngine.Mode.STOP); result.success(true) }
            "duck" -> { focus.request(); result.success(true) }
            "abandonFocus" -> { focus.abandon(); result.success(true) }
            "globalAction" -> {
                val svc = AegisAccessibilityService.instance
                result.success(svc?.perform(call.argument<String>("name") ?: "") ?: false)
            }
            "replyToNotification" -> {
                val pkg = call.argument<String>("pkg") ?: ""
                val text = call.argument<String>("text") ?: ""
                result.success(AegisNotificationListener.reply(applicationContext, pkg, text))
            }
            "captureScreenshot" -> {
                if (pendingShot != null) {
                    result.error("busy", "A capture is already in progress", null)
                    return
                }
                pendingShot = result
                val mpm = getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
                @Suppress("DEPRECATION")
                startActivityForResult(mpm.createScreenCaptureIntent(), reqShot)
            }
            "setNickname" -> {
                NativePrefs.get(this).edit().putString("nickname", call.argument<String>("name") ?: "").apply()
                if (AegisForegroundService.running) VoskEngine.restart(applicationContext)
                result.success(true)
            }
            "openApp" -> {
                val pkg = call.argument<String>("pkg") ?: ""
                val li = packageManager.getLaunchIntentForPackage(pkg)
                if (li != null) {
                    li.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    startActivity(li)
                    result.success(true)
                } else result.success(false)
            }
            "setTimer" -> {
                val secs = call.argument<Int>("seconds") ?: 60
                val i = Intent(AlarmClock.ACTION_SET_TIMER)
                    .putExtra(AlarmClock.EXTRA_LENGTH, secs)
                    .putExtra(AlarmClock.EXTRA_MESSAGE, "Aegis")
                    .putExtra(AlarmClock.EXTRA_SKIP_UI, true)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                result.success(try { startActivity(i); true } catch (_: Exception) { false })
            }
            "setAlarm" -> {
                val i = Intent(AlarmClock.ACTION_SET_ALARM)
                    .putExtra(AlarmClock.EXTRA_HOUR, call.argument<Int>("hour") ?: 7)
                    .putExtra(AlarmClock.EXTRA_MINUTES, call.argument<Int>("minute") ?: 0)
                    .putExtra(AlarmClock.EXTRA_MESSAGE, "Aegis")
                    .putExtra(AlarmClock.EXTRA_SKIP_UI, true)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                result.success(try { startActivity(i); true } catch (_: Exception) { false })
            }
            else -> result.notImplemented()
        }
    }

    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == reqShot) {
            val res = pendingShot
            pendingShot = null
            if (resultCode == Activity.RESULT_OK && data != null) {
                AegisEvents.onCapture = { path, err ->
                    main.post {
                        if (path != null) res?.success(path) else res?.error("capture", err ?: "Capture failed", null)
                    }
                }
                if (AegisEvents.activityResumed) moveTaskToBack(true)
                val i = Intent(this, ScreenCaptureService::class.java)
                    .putExtra("code", resultCode)
                    .putExtra("data", data)
                startForegroundService(i)
            } else {
                res?.error("denied", "Screenshot permission was denied", null)
            }
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    /** Loads the app list (with icons) on a background thread so the UI never freezes. */
    private fun loadApps(result: MethodChannel.Result) {
        Thread {
            val list = try {
                listApps()
            } catch (e: Throwable) {
                emptyList<Map<String, Any>>()
            }
            runOnUiThread { result.success(list) }
        }.start()
    }

    private fun listApps(): List<Map<String, Any>> {
        val pm = packageManager
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val seen = HashSet<String>()
        val out = ArrayList<Map<String, Any>>()
        for (ri in pm.queryIntentActivities(intent, 0)) {
            val pkg = ri.activityInfo.packageName
            if (pkg == packageName || !seen.add(pkg)) continue
            val entry = HashMap<String, Any>()
            entry["name"] = ri.loadLabel(pm).toString()
            entry["pkg"] = pkg
            try {
                entry["icon"] = iconBytes(ri.loadIcon(pm))
            } catch (_: Throwable) {
            }
            out.add(entry)
        }
        out.sortBy { (it["name"] as String).lowercase() }
        return out
    }

    private fun iconBytes(d: Drawable): ByteArray {
        val size = 72
        val bmp = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bmp)
        d.setBounds(0, 0, size, size)
        d.draw(canvas)
        val bos = ByteArrayOutputStream()
        bmp.compress(Bitmap.CompressFormat.PNG, 100, bos)
        bmp.recycle()
        return bos.toByteArray()
    }

    private fun status(): Map<String, Any> {
        val pm = getSystemService(POWER_SERVICE) as PowerManager
        val acc = Settings.Secure.getString(contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES) ?: ""
        val nl = Settings.Secure.getString(contentResolver, "enabled_notification_listeners") ?: ""
        return mapOf(
            "battery" to pm.isIgnoringBatteryOptimizations(packageName),
            "overlay" to Settings.canDrawOverlays(this),
            "accessibility" to acc.contains("AegisAccessibilityService"),
            "notification" to nl.contains(packageName),
            "service" to AegisForegroundService.running,
            "engine" to VoskEngine.status,
            "sdk" to Build.VERSION.SDK_INT
        )
    }

    /** Tries the brand-specific screens first, then falls back to the plain App info page. */
    private fun openSetting(which: String) {
        val uri = Uri.parse("package:$packageName")
        val tries = ArrayList<Intent>()
        when (which) {
            "battery" -> {
                tries.add(Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, uri))
                tries.add(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
            }
            "overlay" -> tries.add(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, uri))
            "accessibility" -> tries.add(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
            "notification" -> tries.add(Intent("android.settings.ACTION_NOTIFICATION_LISTENER_SETTINGS"))
            "autostart" -> {
                val comps = listOf(
                    "com.miui.securitycenter" to "com.miui.permcenter.autostart.AutoStartManagementActivity",
                    "com.coloros.safecenter" to "com.coloros.safecenter.permission.startup.StartupAppListActivity",
                    "com.coloros.safecenter" to "com.coloros.safecenter.startupapp.StartupAppListActivity",
                    "com.oppo.safe" to "com.oppo.safe.permission.startup.StartupAppListActivity",
                    "com.vivo.permissionmanager" to "com.vivo.permissionmanager.activity.BgStartUpManagerActivity",
                    "com.iqoo.secure" to "com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity",
                    "com.transsion.phonemaster" to "com.cyin.himgr.autostart.AutoStartActivity",
                    "com.huawei.systemmanager" to "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity",
                    "com.samsung.android.lool" to "com.samsung.android.sm.ui.battery.BatteryActivity"
                )
                for ((p, c) in comps) tries.add(Intent().setComponent(ComponentName(p, c)))
            }
        }
        tries.add(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, uri))
        for (t in tries) {
            try {
                t.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(t)
                return
            } catch (_: Exception) {
            }
        }
    }
}
