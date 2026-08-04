package com.example.afos_v7

import android.os.Bundle
import androidx.core.app.NotificationManagerCompat
import io.flutter.embedding.android.FlutterFragmentActivity

// FlutterFragmentActivity (not FlutterActivity) is required by local_auth so
// the OS biometric prompt can attach to a FragmentActivity host.
class MainActivity : FlutterFragmentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Clears the "AFOS is up to date — tap to open" notification that
        // UpdateRelaunchReceiver posts after an in-app update.
        //
        // That notification is a FALLBACK for the case where Android blocks the
        // receiver's direct relaunch (background activity launch, Android 10+).
        // When the direct relaunch does work, or when the user opens the app
        // themselves, it would otherwise sit in the shade inviting them to open
        // an app that is already open. Cancelling it here means exactly one of
        // the two paths is ever visible.
        //
        // Unconditional and cheap: cancelling an ID that was never posted is a
        // no-op, so this needs no state tracking to decide whether to run.
        try {
            NotificationManagerCompat.from(this)
                .cancel(UpdateRelaunchReceiver.NOTIFICATION_ID)
        } catch (_: Exception) {
        }
    }
}
