package bd.edu.diu.afos

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

/**
 * Brings AFOS back after the in-app updater has replaced it.
 *
 * THE PROBLEM. `AppUpdateService.downloadAndInstall` hands the APK to Android's
 * package installer. The installer replaces the app, which kills this app's
 * process — so from the user's side they tap Update, watch an install, and are
 * left staring at the installer's own "Done" screen with AFOS gone. Every time.
 *
 * WHAT ANDROID ACTUALLY ALLOWS. `ACTION_MY_PACKAGE_REPLACED` is broadcast to an
 * app right after it is updated, and a manifest-registered receiver does get it
 * (an app is taken out of the "stopped" state by its own update, so the usual
 * stopped-app broadcast exclusion does not apply here).
 *
 * What is NOT allowed is the obvious next step. Since Android 10, starting an
 * activity from the background is blocked unless the app is on an exemption
 * list, and "was just updated" is not on it. The block is SILENT — startActivity
 * returns normally and simply does nothing — so there is no failure to catch and
 * no way to detect it from here.
 *
 * SO THIS DOES BOTH, in the order that makes the good case fastest:
 *
 *   1. Attempts the direct relaunch. This genuinely works on Android 9 and
 *      below, and on a number of OEM builds that relax the restriction.
 *   2. Posts a high-priority "AFOS is up to date — tap to open" notification,
 *      which always works and needs no exemption.
 *
 * When (1) succeeds, [MainActivity] cancels the notification as it starts, so
 * the user never sees a stray tap-to-open for an app already in front of them.
 * When (1) is blocked, the notification is the whole mechanism: one tap, app is
 * back. That is the honest maximum on modern Android — an app cannot pull itself
 * to the foreground unprompted, and any library claiming otherwise is relying on
 * the same OEM leniency as (1).
 */
class UpdateRelaunchReceiver : BroadcastReceiver() {

    companion object {
        const val CHANNEL_ID = "afos_app_update"
        const val NOTIFICATION_ID = 0xAF05
    }

    override fun onReceive(context: Context, intent: Intent) {
        // MY_PACKAGE_REPLACED only. PACKAGE_REPLACED (no MY_) fires for other
        // apps too and would relaunch AFOS whenever anything on the device
        // updated.
        if (intent.action != Intent.ACTION_MY_PACKAGE_REPLACED) return

        val launch = context.packageManager
            .getLaunchIntentForPackage(context.packageName)
            ?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            ?: return

        // 1. The optimistic path. Wrapped because a SecurityException here must
        //    not take the notification down with it — that is the fallback.
        try {
            context.startActivity(launch)
        } catch (_: Exception) {
        }

        // 2. The path that always works.
        try {
            notifyUpdated(context, launch)
        } catch (_: Exception) {
        }
    }

    private fun notifyUpdated(context: Context, launch: Intent) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "App updates",
                // HIGH so it surfaces as a heads-up banner. This is the direct
                // result of an action the user took seconds ago, not an
                // unsolicited interruption.
                NotificationManager.IMPORTANCE_HIGH,
            ).apply { description = "Tells you when AFOS has finished updating." }
            context.getSystemService(NotificationManager::class.java)
                ?.createNotificationChannel(channel)
        }

        val pending = PendingIntent.getActivity(
            context,
            0,
            launch,
            // FLAG_IMMUTABLE is mandatory from Android 12; without it the
            // PendingIntent constructor throws outright.
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_download_done)
            .setContentTitle("AFOS is up to date")
            .setContentText("Tap to open the new version.")
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(pending)
            .build()

        // On Android 13+ this silently no-ops without POST_NOTIFICATIONS. The
        // app already requests that at startup for OneSignal, so by the time
        // anyone can reach the in-app updater the permission has been asked
        // for — and a user who denied notifications outright is not someone to
        // route around.
        NotificationManagerCompat.from(context).notify(NOTIFICATION_ID, notification)
    }
}
