plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Firebase (reads google-services.json → FCM config for com.vido.food).
    id("com.google.gms.google-services")
}

android {
    namespace = "com.vido.food"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // flutter_local_notifications 18.x needs core-library desugaring.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Matches google-services.json (reuses the existing Firebase Android app).
        applicationId = "com.vido.food"
        // firebase_messaging / firebase_core require Android API 23+.
        minSdk = maxOf(flutter.minSdkVersion, 23)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // PAX PosLink Android SDK (real card terminal) + its runtime deps.
    implementation(files("libs/PAX_POSLinkAndroid_20260202.aar"))
    implementation(files("libs/gson-2.8.6.jar"))
    implementation(files("libs/jsch-0.1.55.jar"))
    implementation(files("libs/okhttp-4.9.0.jar"))
    implementation(files("libs/okio-2.8.0.jar"))
    implementation(files("libs/zxing-core-3.3.3.jar"))
}
