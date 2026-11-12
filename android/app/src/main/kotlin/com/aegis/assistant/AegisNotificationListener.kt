package com.aegis.assistant

import android.app.Notification
import android.app.RemoteInput
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

/**
 * Reads notifications ONLY for packages the user whitelisted. The whitelist check is the very first
 * thing done for every notification, before any content is touched.
 */
class AegisNotificationListener : NotificationListenerService() {
    companion object {
        private val lastActions = HashMap<String, Notification.Action>()

        fun reply(ctx: Context, pkg: String, text: String): Boolean {
            if (!NativePrefs.whitelist(ctx).contains(pkg)) return false
            val action = synchronized(lastActions) { lastActions[pkg] } ?: return false
            val inputs = action.remoteInputs ?: return false
            if (inputs.isEmpty()) return false
            return try {
                val intent = Intent()
                val results = Bundle()
                results.putCharSequence(inputs[0].resultKey, text)
                RemoteInput.addResultsToIntent(inputs, intent, results)
                action.actionIntent.send(ctx, 0, intent)
                true
            } catch (_: Exception) {
                false
            }
        }
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (sbn == null) return
        val pkg = sbn.packageName ?: return
        if (pkg == packageName) return
        if (!NativePrefs.whitelist(this).contains(pkg)) return
        val n = sbn.notification ?: return
        if (n.flags and Notification.FLAG_GROUP_SUMMARY != 0) return

        val extras = n.extras
        val title = extras?.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: ""
        val text = extras?.getCharSequence(Notification.EXTRA_TEXT)?.toString() ?: ""
        if (title.isBlank() && text.isBlank()) return

        try {
            val all = ArrayList<Notification.Action>()
            n.actions?.let { all.addAll(it) }
            all.addAll(Notification.WearableExtender(n).actions)
            val replyAction = all.firstOrNull { a -> a.remoteInputs?.isNotEmpty() == true }
            synchronized(lastActions) {
                if (replyAction != null) lastActions[pkg] = replyAction else lastActions.remove(pkg)
            }
        } catch (_: Exception) {
        }

        val label = try {
            packageManager.getApplicationLabel(packageManager.getApplicationInfo(pkg, 0)).toString()
        } catch (_: Exception) { pkg }

        AegisEvents.emit("notification", mapOf("pkg" to pkg, "app" to label, "title" to title, "text" to text))
    }
}
