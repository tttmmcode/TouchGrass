import com.google.firebase.crashlytics.buildtools.gradle.CrashlyticsExtension
import groovy.json.JsonSlurper
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

// ── Release gates (Phase 6) ────────────────────────────────────────────────────
// A build fails early, saying exactly what to fix, instead of producing an
// app that can't work or isn't really signed:
// - every build: android/app/google-services.json must contain a Firebase
//   app registered for this application ID (audit X-5);
// - release builds: must be signed with the real upload key from
//   android/key.properties — there is NO fallback to the debug key (X-6) —
//   and need the Maps key in android/local.properties.
// Nothing here prints a secret value. See PHASE_6_RELEASE_RUNBOOK.md.
val expectedApplicationId = "com.touchgrass.app"

fun firebaseConfigProblems(): List<String> {
    val config = file("google-services.json")
    if (!config.exists()) return listOf("android/app/google-services.json is missing")
    val json = try {
        JsonSlurper().parse(config) as? Map<*, *>
    } catch (e: Exception) {
        null
    } ?: return listOf("android/app/google-services.json is not valid JSON")
    val packages = (json["client"] as? List<*>).orEmpty().mapNotNull { client ->
        (((client as? Map<*, *>)?.get("client_info") as? Map<*, *>)
            ?.get("android_client_info") as? Map<*, *>)?.get("package_name") as? String
    }
    return if (expectedApplicationId in packages) emptyList() else listOf(
        "android/app/google-services.json has no Firebase app for '$expectedApplicationId' " +
            "(it has: ${packages.joinToString().ifEmpty { "none" }}). Register the Android app " +
            "'$expectedApplicationId' in the Firebase console, add its SHA fingerprints, and " +
            "download its google-services.json (PHASE_6_RELEASE_RUNBOOK.md, step 1).",
    )
}

fun releaseSigningProblems(): List<String> {
    if (!rootProject.file("key.properties").exists()) {
        return listOf(
            "android/key.properties is missing, so this release can't be signed with the " +
                "upload key (there is no debug-key fallback). Create it as described in " +
                "PHASE_6_RELEASE_RUNBOOK.md, step 3.",
        )
    }
    val problems = mutableListOf<String>()
    for (key in listOf("storeFile", "storePassword", "keyAlias", "keyPassword")) {
        if (keyProperties.getProperty(key).isNullOrBlank()) problems += "android/key.properties has no '$key'"
    }
    val store = keyProperties.getProperty("storeFile")
    if (!store.isNullOrBlank() && !file(store).exists()) {
        problems += "the keystore named by storeFile doesn't exist (a relative path is resolved from android/app)"
    }
    if (localProperties.getProperty("MAPS_API_KEY").isNullOrBlank()) {
        problems += "android/local.properties has no MAPS_API_KEY, so the map would not load"
    }
    return problems
}

gradle.taskGraph.whenReady {
    val ours = allTasks.filter { it.project == project }
    val building = ours.any { it.name.startsWith("assemble") || it.name.startsWith("bundle") }
    val release = ours.any { it.name.contains("Release") }
    val problems = (if (building) firebaseConfigProblems() else emptyList()) +
        (if (release) releaseSigningProblems() else emptyList())
    if (problems.isNotEmpty()) {
        throw GradleException(
            "TouchGrass build stopped:\n" + problems.joinToString("\n") { "  • $it" },
        )
    }
    // Debug builds don't need the Maps key to run, but say why the map is blank.
    if (building && !release && localProperties.getProperty("MAPS_API_KEY").isNullOrBlank()) {
        logger.warn(
            "TouchGrass: android/local.properties has no MAPS_API_KEY, so this build's map " +
                "will not load (use the Android-restricted key; PHASE_7A_RELEASE_RUNBOOK.md).",
        )
    }
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
            // Always the upload key — the release gate above stops the build
            // when key.properties is missing or incomplete.
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
            // Uploading the R8 mapping file contacts the production Firebase
            // project, so it's off for local builds. For a store build, pass
            // `-PuploadCrashlyticsMapping=true` (flutter: `-P uploadCrashlyticsMapping=true`).
            configure<CrashlyticsExtension> {
                mappingFileUploadEnabled =
                    (project.findProperty("uploadCrashlyticsMapping") as String?) == "true"
            }
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
