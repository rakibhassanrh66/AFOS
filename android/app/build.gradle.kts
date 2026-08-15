import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import java.util.Properties

// Real release signing material, when it is available.
//
// android/key.properties and *.jks/*.keystore are gitignored (.gitignore:48-50),
// so this file is never in the repo: it is created locally by the maintainer,
// and reconstructed in CI from repo secrets by the release job.
//
// Absent-by-default is deliberate. Every contributor and every CI run that has
// no keystore must still be able to build, so a missing key.properties falls
// back to debug signing rather than failing the build -- what it must NOT do is
// silently fall back for a real release, which is why the release workflow
// prints a loud warning when it ships a debug-signed APK.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        keystorePropertiesFile.inputStream().use { load(it) }
    }
}
val hasReleaseKeystore = keystorePropertiesFile.exists() &&
        keystoreProperties.getProperty("storeFile") != null

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("com.google.gms.google-services")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.afos_v7"
    // This Flutter channel's flutter.compileSdkVersion still defaults to 33, but
    // several transitive androidx deps now require newer: flutter_displaymode
    // (BUG 5) pulls fragment:1.7.1/window:1.2.0 (need 34), androidx.camera 1.5.0
    // needs 35, and androidx.browser 1.9.0 needs 36. Pin 36 (the highest floor,
    // also the current max API). compileSdk only affects which APIs compile;
    // targetSdk/minSdk below are unchanged, so runtime behaviour and device
    // support are untouched.
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlin {
        compilerOptions {
            jvmTarget = JvmTarget.fromTarget(JavaVersion.VERSION_17.toString())
        }
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.afos_v7"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                // storeFile is resolved relative to android/app/ when relative;
                // an absolute path also works.
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // A debug-signed release APK is signed with the publicly-known
            // Android debug key, so anyone can produce a "genuine" update for
            // it and installs can't be trusted to have come from this project.
            // Use the real key whenever one is present.
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }

        // PROFILE BUILDS GET THE RELEASE KEY TOO — and this is not cosmetic.
        //
        // Flutter signs `--profile` with the DEBUG key by default. A profile
        // APK is the one you actually install on a real phone to test
        // performance, so it lands on the same device as a downloaded release
        // build — with a different signature. Android then refuses every later
        // install of either one with "App not installed as package conflicts
        // with an existing package", and the only cure is uninstalling, which
        // signs the user out.
        //
        // That is not a hypothetical: it happened on the maintainer's own
        // phone, took three published versions to diagnose, and none of those
        // versions could have fixed it — Android rejects the package before any
        // app code runs.
        //
        // Signing profile with the release key makes a locally built profile
        // APK install cleanly over a published release and vice versa, because
        // they are then the same signer. Falls back to debug signing when no
        // keystore is present, so a fresh clone still builds.
        //
        // The alternative — `applicationIdSuffix ".debug"` — is the textbook
        // answer and is WRONG for this project: google-services.json registers
        // only `com.example.afos` and `com.example.afos_v7`, so a suffixed ID
        // fails the build with "No matching client found for package name".
        // Fixing that needs a Firebase console change, which is a bigger and
        // more fragile move than signing consistently.
        maybeCreate("profile").apply {
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

// EVERY ARTIFACT OF ONE RELEASE MUST SHARE ONE versionCode.
//
// Flutter's gradle plugin rewrites the versionCode when building
// `--split-per-abi`, as `abiOffset * 1000 + versionCode` — armeabi-v7a 1,
// arm64-v8a 2, x86_64 4. So release 2.8.3 shipped as:
//
//     AFOS-v2.8.3.apk            versionCode   68   (universal)
//     AFOS-v2.8.3-arm64-v8a.apk  versionCode 2068   (split)
//
// That numbering exists for Google Play, which requires a distinct versionCode
// per ABI in one release track. **AFOS is not on Play**, and outside it the
// numbering is actively harmful: a phone that installed the 33 MB arm64 split
// sits on 2068, and the in-app updater downloads the universal build — 68 —
// which Android rejects as a DOWNGRADE. The update button then does nothing,
// forever, on exactly the users who took the smaller download we recommended.
//
// Pinning every output to the plain versionCode makes the split and the
// universal interchangeable: either installs over the other, and the in-app
// updater works regardless of which one a user started from.
// Uses the SAME legacy API Flutter's plugin uses to apply the multiplier, and
// runs after it. `androidComponents.onVariants` looks like the modern answer
// and does nothing here: Flutter sets `versionCodeOverride` on the legacy
// output object, and that override wins. Verified by building both ways —
// with onVariants the splits still came out 2069/1069.
android.applicationVariants.all {
    outputs.all {
        (this as com.android.build.gradle.internal.api.BaseVariantOutputImpl)
            .let { out ->
                val impl = out as? com.android.build.gradle.api.ApkVariantOutput
                impl?.versionCodeOverride = flutter.versionCode
            }
    }
}

flutter {
    source = "../.."
}
