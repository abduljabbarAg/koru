// Imports have to come first, and `Properties` has to be imported by name:
// inside the android block `java` resolves to the JavaPluginExtension rather
// than the java package, so `java.util.Properties()` does not compile.
import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing is opt-in, and a missing keystore now stops the build.
//
// It used to fall back to the debug key so CI stayed green, which is worse than
// the alternative: the build succeeded, produced an APK called "release", and
// nothing said otherwise. A debug-signed APK cannot be upgraded in place by
// anyone who installed it from a store, so shipping one by accident is not a
// cosmetic problem.
//
// Set `koru.allowDebugSigning=true` in gradle.properties (or pass -P) to opt
// back in for local builds and CI. It is deliberately not the default.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

val allowDebugSigning: Boolean =
    (project.findProperty("koru.allowDebugSigning") as String?)?.toBoolean() ?: false

if (!hasReleaseKeystore && !allowDebugSigning) {
    throw GradleException(
        "No release keystore at ${keystorePropertiesFile.path}, so the release " +
            "build would be signed with the debug key and could never be " +
            "upgraded in place. Add android/key.properties, or set " +
            "-Pkoru.allowDebugSigning=true to sign with debug on purpose."
    )
}

android {
    namespace = "com.abduljabbar.koru"
    compileSdk = flutter.compileSdkVersion
    // Pinned above flutter.ndkVersion (23.x) because path_provider_android and
    // sqflite_android both require 27.0.12077973. NDK versions are backward
    // compatible, so using the highest one is the supported answer.
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        applicationId = "com.abduljabbar.koru"
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // The bundled engine has to exist as a file on disk, because the app execs
    // it. Since Android 6 the default is to map native libraries straight out of
    // the APK and never extract them, which leaves nothing to exec: the app
    // reported "no bundled model" while the binary was plainly in the package.
    //
    // Legacy packaging restores extraction into nativeLibraryDir, which is the
    // one location an app can still run a binary from on a modern Android. The
    // cost is install size and a slightly slower install.
    packagingOptions {
        jniLibs {
            useLegacyPackaging = true
        }
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = keystoreProperties["storeFile"]?.let { rootProject.file(it) }
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

flutter {
    source = "../.."
}
