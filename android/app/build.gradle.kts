import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// ── Read secrets from local.properties (never committed to source control) ────
val localProperties = Properties().also { props ->
    val file = rootProject.file("local.properties")
    if (file.exists()) file.inputStream().use { props.load(it) }
}

// ── Read signing config from key.properties (never committed) ─────────────────
val keyProperties = Properties().also { props ->
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { props.load(it) }
}

android {
    namespace = "com.touchgrass.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.touchgrass.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Inject Maps API key; falls back to empty string if local.properties is absent.
        manifestPlaceholders["MAPS_API_KEY"] =
            localProperties.getProperty("MAPS_API_KEY") ?: ""
    }

    signingConfigs {
        create("release") {
            // Populated from key.properties — see RELEASE_GUIDE.md for setup.
            keyAlias     = keyProperties["keyAlias"]     as String? ?: ""
            keyPassword  = keyProperties["keyPassword"]  as String? ?: ""
            storeFile    = keyProperties["storeFile"]?.let { file(it as String) }
            storePassword= keyProperties["storePassword"] as String? ?: ""
        }
    }

    buildTypes {
        release {
            signingConfig = if (keyProperties["storeFile"] != null)
                signingConfigs.getByName("release")
            else
                signingConfigs.getByName("debug") // fallback for local builds without keystore
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
        debug {
            defaultConfig.manifestPlaceholders["MAPS_API_KEY"] =
                localProperties.getProperty("MAPS_API_KEY") ?: ""
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
