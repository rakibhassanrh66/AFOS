# R8 keep rules for AFOS release/profile builds.
#
# Most plugins below already ship their own consumer ProGuard rules inside
# their AAR (confirmed for mobile_scanner and flutter_background_service_android,
# both wired via `consumerProguardFiles` and auto-merged by AGP regardless of
# this file). The rest do not, and none of it is guaranteed to survive a
# future plugin bump -- these are explicit, belt-and-suspenders keeps for
# every reflection/platform-channel-heavy plugin this app ships, so
# `isMinifyEnabled`/`isShrinkResources` (build.gradle.kts) cannot silently
# strip one with zero signal from `flutter analyze` or the test suite.
# A manual smoke test (login, QR scan, GPS, biometric unlock, background
# SOS, push) is still required before a shrunk build is trusted in a tagged
# release -- see the release runbook (kept on the maintainer's machine,
# not published with this repo).

# --- Flutter framework ---
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# --- flutter_secure_storage (Supabase session storage) ---
#
# THE ACTUAL FREEZE CAUSE, found live: bootstrap.dart awaits
# Supabase.initialize() with NO try/catch -- the one unguarded await in the
# whole startup sequence -- and that goes straight into
# SecureSessionLocalStorage (secure_session_storage.dart), which uses this
# plugin with `encryptedSharedPreferences: true`. Its Android build.gradle
# depends directly on androidx.security:security-crypto AND
# com.google.crypto.tink:tink-android -- Tink registers its crypto key
# managers via reflection (Registry.registerKeyManager by class name), so R8
# stripping those classes without explicit keeps is a well-documented cause
# of EncryptedSharedPreferences hanging/throwing at init, not just failing
# cleanly. This plugin ships no consumer proguard rules of its own (checked:
# no proguard-rules.pro in its published package) -- these keeps are
# required, not optional.
-keep class com.it_nomads.fluttersecurestorage.** { *; }
-keep class androidx.security.crypto.** { *; }
-keep class com.google.crypto.tink.** { *; }
-keepclassmembers class com.google.crypto.tink.** { *; }
-dontwarn com.google.crypto.tink.**
-dontwarn com.google.errorprone.annotations.**

# --- geolocator (GPS capture: profile completion, transport, SOS) ---
-keep class com.baseflow.geolocator.** { *; }

# --- local_auth (biometric unlock) ---
-keep class io.flutter.plugins.localauth.** { *; }
-keep class androidx.biometric.** { *; }

# --- mobile_scanner (VR-ID QR scan) — mirrors its own bundled rules ---
-keep class dev.steenbakker.mobile_scanner.** { *; }
-keep class com.google.mlkit.* { *; }
-keep class com.google.android.libraries.barhopper.** { *; }
-keep class com.google.photos.* { *; }

# --- onesignal_flutter (push notifications) ---
-keep class com.onesignal.** { *; }
-dontwarn com.onesignal.**

# --- flutter_background_service (background SOS location sharing) ---
-keep class id.flutter.flutter_background_service.** { *; }

# --- record (voice notes / feedback recording) ---
-keep class com.llfbandit.record.** { *; }

# --- audioplayers ---
-keep class xyz.luan.audioplayers.** { *; }

# --- webview_flutter (embedded payment webview) ---
-keep class io.flutter.plugins.webviewflutter.** { *; }

# Enums are reflection-accessed by name in a few places (category/state
# switches); values()/valueOf() must survive shrinking everywhere, not just
# inside the plugins above.
-keepclassmembers class * extends java.lang.Enum {
    <fields>;
    public static **[] values();
    public static ** valueOf(java.lang.String);
}
