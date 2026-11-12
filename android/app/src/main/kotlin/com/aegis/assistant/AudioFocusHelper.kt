package com.aegis.assistant

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager

/** Ducks other audio (e.g. a game) while AEGIS listens or speaks, restores it afterwards. */
class AudioFocusHelper(ctx: Context) {
    private val am = ctx.applicationContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private var req: AudioFocusRequest? = null

    @Synchronized
    fun request() {
        if (req != null) return
        val attrs = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ASSISTANT)
            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
            .build()
        val r = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
            .setAudioAttributes(attrs)
            .setWillPauseWhenDucked(false)
            .setOnAudioFocusChangeListener { }
            .build()
        am.requestAudioFocus(r)
        req = r
    }

    @Synchronized
    fun abandon() {
        req?.let { am.abandonAudioFocusRequest(it) }
        req = null
    }
}
