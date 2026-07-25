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
    }
}

flutter {
    source = "../.."
}
