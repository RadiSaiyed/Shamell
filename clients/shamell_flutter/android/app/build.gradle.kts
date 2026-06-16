import org.gradle.api.GradleException
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Expose the TomTom API key defined in gradle.properties
val tomtomApiKey: String by project
// Optional: Google Maps Android API key (if used by plugins/components).
val googleMapsApiKey: String by project
// Optional: Play Integrity Cloud project number (digits).
val playIntegrityCloudProjectNumber: String by project

fun gradlePropOrEnv(name: String): String? {
    val fromGradle = providers.gradleProperty(name).orNull?.trim()
    if (!fromGradle.isNullOrEmpty()) return fromGradle
    val fromEnv = System.getenv(name)?.trim()
    if (!fromEnv.isNullOrEmpty()) return fromEnv
    return null
}

val releaseStoreFile = gradlePropOrEnv("SHAMELL_RELEASE_STORE_FILE")
val releaseStorePassword = gradlePropOrEnv("SHAMELL_RELEASE_STORE_PASSWORD")
val releaseKeyAlias = gradlePropOrEnv("SHAMELL_RELEASE_KEY_ALIAS")
val releaseKeyPassword = gradlePropOrEnv("SHAMELL_RELEASE_KEY_PASSWORD")
val hasReleaseSigning = !releaseStoreFile.isNullOrEmpty() &&
    !releaseStorePassword.isNullOrEmpty() &&
    !releaseKeyAlias.isNullOrEmpty() &&
    !releaseKeyPassword.isNullOrEmpty()
val allowDebugReleaseSigning = (
    gradlePropOrEnv("SHAMELL_ALLOW_DEBUG_RELEASE_SIGNING")
        ?.equals("true", ignoreCase = true)
    ) == true
val releaseTaskRequested = gradle.startParameter.taskNames.any {
    it.contains("release", ignoreCase = true)
}

android {
    namespace = "online.shamell.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    flavorDimensions += "app"

    productFlavors {
        create("user") {
            dimension = "app"
            applicationId = "online.shamell.app"
            resValue("string", "app_name", "Shamell")
        }
        create("operator") {
            dimension = "app"
            applicationId = "online.shamell.app.operator"
            resValue("string", "app_name", "Shamell Operator")
        }
        create("admin") {
            dimension = "app"
            applicationId = "online.shamell.app.admin"
            resValue("string", "app_name", "Shamell Admin")
        }
    }

    defaultConfig {
        // Base config; per-flavor applicationId is set in productFlavors above.
        minSdk = maxOf(flutter.minSdkVersion, 26)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Provide AndroidManifest.xml placeholders.
        manifestPlaceholders["GOOGLE_MAPS_API_KEY"] =
            if (googleMapsApiKey.startsWith("CHANGE_ME")) "" else googleMapsApiKey
    }

    buildFeatures {
        buildConfig = true
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = file(releaseStoreFile!!)
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            if (hasReleaseSigning) {
                signingConfig = signingConfigs.getByName("release")
            } else if (allowDebugReleaseSigning) {
                // Escape hatch for temporary CI/dev release builds only.
                signingConfig = signingConfigs.getByName("debug")
            } else if (releaseTaskRequested) {
                throw GradleException(
                    "Release signing is not configured. " +
                        "Set SHAMELL_RELEASE_STORE_FILE, SHAMELL_RELEASE_STORE_PASSWORD, " +
                        "SHAMELL_RELEASE_KEY_ALIAS, SHAMELL_RELEASE_KEY_PASSWORD " +
                        "or explicitly opt in to debug signing with " +
                        "SHAMELL_ALLOW_DEBUG_RELEASE_SIGNING=true."
                )
            }
        }
        // Expose the TomTom API key as a BuildConfig field for all build types.
        buildTypes.configureEach {
            buildConfigField("String", "TOMTOM_API_KEY", "\"$tomtomApiKey\"")
            buildConfigField(
                "long",
                "PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER",
                playIntegrityCloudProjectNumber
            )
        }
    }
}

androidComponents {
    beforeVariants(selector().all()) { variant ->
        val appFlavor = variant.productFlavors
            .firstOrNull { it.first == "app" }
            ?.second
        if (appFlavor != "user") {
            variant.enable = false
        }
    }
}

flutter {
    source = "../.."
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")

    // TomTom Maps SDK – Map Display module
    val tomTomMapsVersion = "1.26.3"
    implementation("com.tomtom.sdk.maps:map-display:$tomTomMapsVersion")

    // Google Play Integrity API (hardware-backed attestation layer).
    implementation("com.google.android.play:integrity:1.3.0")
}
