package com.aegis.assistant

import android.content.Context
import android.content.res.AssetManager
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import org.json.JSONArray
import org.json.JSONObject
import org.vosk.Model
import org.vosk.Recognizer
import org.vosk.android.RecognitionListener
import org.vosk.android.SpeechService
import java.io.File
import java.io.FileOutputStream

/** Offline wake-word engine. WAKE listens for "aegis" (+ the user's nickname), STOP for stop words. */
object VoskEngine {
    enum class Mode { WAKE, STOP }

    private val main = Handler(Looper.getMainLooper())
    private var model: Model? = null
    private var loading = false
    private var speech: SpeechService? = null
    private var wantMode: Mode? = null
    private var lastFire = 0L
    private val stopWords = listOf("stop", "thamo", "tamo", "thumb")
    @Volatile private var activeWords: Set<String> = setOf("aegis")

    @Volatile var status: String = "idle"

    private fun wakeWords(app: Context): List<String> {
        val out = arrayListOf("aegis")
        val nick = NativePrefs.get(app).getString("nickname", "")?.trim()?.lowercase() ?: ""
        val w = nick.split(Regex("\\s+")).firstOrNull { it.matches(Regex("[a-z]{2,20}")) }
        if (w != null && w != "aegis") out.add(w)
        return out
    }

    @Synchronized
    fun start(ctx: Context, mode: Mode) {
        val app = ctx.applicationContext
        wantMode = mode
        releaseSpeech()
        if (model == null) {
            loadModel(app)
            return
        }
        begin(app, mode)
    }

    @Synchronized
    fun restart(ctx: Context) {
        val m = wantMode ?: return
        start(ctx, m)
    }

    @Synchronized
    fun pause() {
        wantMode = null
        releaseSpeech()
    }

    @Synchronized
    fun shutdown() {
        pause()
        try { model?.close() } catch (_: Throwable) {}
        model = null
        status = "idle"
    }

    private fun releaseSpeech() {
        try {
            speech?.stop()
            speech?.shutdown()
        } catch (_: Throwable) {
        }
        speech = null
    }

    private fun fail(t: Throwable) {
        val root = generateSequence(t) { it.cause }.last()
        updateStatus("error: ${t.javaClass.simpleName}: ${t.message ?: root.message ?: ""}")
    }

    private fun begin(app: Context, mode: Mode) {
        val m = model ?: return
        try {
            val words = if (mode == Mode.WAKE) wakeWords(app) else stopWords
            activeWords = words.toSet()
            val grammar = JSONArray(words + "[unk]").toString()
            val rec = Recognizer(m, 16000.0f, grammar)
            val s = SpeechService(rec, 16000.0f)
            s.startListening(listener(app, mode))
            speech = s
            updateStatus("ready")
        } catch (e: Throwable) {
            fail(e)
        }
    }

    private fun listener(app: Context, mode: Mode) = object : RecognitionListener {
        override fun onPartialResult(hypothesis: String?) = check(hypothesis, app, mode)
        override fun onResult(hypothesis: String?) = check(hypothesis, app, mode)
        override fun onFinalResult(hypothesis: String?) = check(hypothesis, app, mode)
        override fun onError(exception: Exception?) {
            updateStatus("error: ${exception?.javaClass?.simpleName}: ${exception?.message}")
        }
        override fun onTimeout() {}
    }

    private fun check(json: String?, app: Context, mode: Mode) {
        if (json == null) return
        val text = try {
            val o = JSONObject(json)
            o.optString("partial", o.optString("text", ""))
        } catch (_: Exception) { "" }
        if (text.isBlank()) return
        val words = text.lowercase().split(" ")
        if (!words.any { it in activeWords }) return
        val now = SystemClock.elapsedRealtime()
        if (now - lastFire < 2500) return
        lastFire = now
        main.post {
            if (mode == Mode.WAKE) {
                pause()
                AegisEvents.handleWake(app)
            } else {
                AegisEvents.emit("stopWord")
            }
        }
    }

    private fun updateStatus(s: String) {
        status = s
        AegisEvents.emit("voskStatus", s)
    }

    private fun loadModel(app: Context) {
        if (loading) return
        loading = true
        updateStatus("loading")
        Thread {
            try {
                val dir = File(app.filesDir, "vosk-model")
                val marker = File(dir, ".ok")
                if (!marker.exists()) {
                    val names = app.assets.list("model")
                    if (names == null || names.isEmpty()) {
                        updateStatus("missing")
                        loading = false
                        return@Thread
                    }
                    dir.deleteRecursively()
                    copyAssets(app.assets, "model", dir)
                    marker.writeText("1")
                }
                val m = Model(dir.absolutePath)
                synchronized(this) { model = m }
                loading = false
                updateStatus("ready")
                main.post { wantMode?.let { begin(app, it) } }
            } catch (t: Throwable) {
                loading = false
                fail(t)
            }
        }.start()
    }

    private fun copyAssets(am: AssetManager, src: String, dst: File) {
        val list = am.list(src) ?: emptyArray()
        if (list.isEmpty()) {
            try {
                dst.parentFile?.mkdirs()
                am.open(src).use { i -> FileOutputStream(dst).use { o -> i.copyTo(o) } }
            } catch (_: Exception) {
                dst.mkdirs()
            }
            return
        }
        dst.mkdirs()
        for (n in list) copyAssets(am, "$src/$n", File(dst, n))
    }
}
