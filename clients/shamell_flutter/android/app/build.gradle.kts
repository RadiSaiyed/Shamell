import org.gradle.api.GradleException
import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import java.util.Base64

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

fun gradlePropOrEnv(name: String): String? {
    val fromGradle = providers.gradleProperty(name).orNull?.trim()
    if (!fromGradle.isNullOrEmpty()) return fromGradle
    val fromEnv = System.getenv(name)?.trim()
    if (!fromEnv.isNullOrEmpty()) return fromEnv
    return null
}

fun normalizeSha256HexFingerprint(raw: String): String {
    val normalized = raw
        .trim()
        .lowercase()
        .replace(":", "")
        .replace(Regex("[^0-9a-f]"), "")
    if (!Regex("^[0-9a-f]{64}$").matches(normalized)) {
        throw GradleException(
            "expected SHA-256 fingerprint (64 hex chars, optional colons), got: $raw"
        )
    }
    return normalized
}

fun flutterDartDefines(): Map<String, String> {
    val raw = providers.gradleProperty("dart-defines").orNull?.trim().orEmpty()
    if (raw.isEmpty()) return emptyMap()
    val decoded = linkedMapOf<String, String>()
    for (entry in raw.split(',')) {
        val token = entry.trim()
        if (token.isEmpty()) continue
        val padded = token + "=".repeat((4 - token.length % 4) % 4)
        val plain = runCatching {
            String(Base64.getDecoder().decode(padded))
        }.getOrNull() ?: continue
        val idx = plain.indexOf('=')
        if (idx <= 0) continue
        decoded[plain.substring(0, idx)] = plain.substring(idx + 1)
    }
    return decoded
}

val firebasePackageNameByFlavor = linkedMapOf(
    "user" to "online.shamell.app",
    "ride" to "online.shamell.ride",
    "driver" to "online.shamell.driver",
    "operator" to "online.shamell.operator",
    "busOperator" to "online.shamell.busoperator",
    "syrcom" to "online.shamell.syrcom",
)

fun requestedFirebaseFlavorNames(): Set<String> {
    val requested = linkedSetOf<String>()
    for (taskName in gradle.startParameter.taskNames) {
        val normalizedTask = taskName.lowercase()
        for (flavor in firebasePackageNameByFlavor.keys) {
            if (normalizedTask.contains(flavor)) {
                requested += flavor
            }
        }
    }
    return requested
}

fun googleServicesLooksPlaceholder(raw: String): Boolean {
    val normalized = raw.lowercase()
    return normalized.contains("replace_with_firebase_api_key") ||
        normalized.contains("000000000000-placeholder") ||
        normalized.contains("\"project_number\": \"000000000000\"") ||
        normalized.contains("1:000000000000:android:")
}

fun googleServicesCandidatesForFlavor(flavor: String): List<java.io.File> =
    listOf(
        file("google-services.json"),
        file("src/main/google-services.json"),
        file("src/$flavor/google-services.json"),
    )

fun googleServicesFileSupportsPackage(file: java.io.File, packageName: String): Boolean {
    if (!file.isFile) return false
    val raw = runCatching { file.readText() }.getOrElse { return false }
    if (googleServicesLooksPlaceholder(raw)) return false
    return raw.contains("\"package_name\": \"$packageName\"")
}

fun hasUsableGoogleServicesForFlavor(flavor: String): Boolean {
    val packageName = firebasePackageNameByFlavor[flavor] ?: return false
    return googleServicesCandidatesForFlavor(flavor).any { candidate ->
        googleServicesFileSupportsPackage(candidate, packageName)
    }
}

val requestedGoogleServicesFlavors = requestedFirebaseFlavorNames()
val enableGoogleServicesPlugin = if (requestedGoogleServicesFlavors.isEmpty()) {
    firebasePackageNameByFlavor.keys.all(::hasUsableGoogleServicesForFlavor)
} else {
    requestedGoogleServicesFlavors.all(::hasUsableGoogleServicesForFlavor)
}

if (enableGoogleServicesPlugin) {
    logger.lifecycle(
        "Shamell mobile Firebase: enabling google-services plugin for " +
            if (requestedGoogleServicesFlavors.isEmpty()) {
                "all configured flavors"
            } else {
                requestedGoogleServicesFlavors.joinToString(", ")
            }
    )
    apply(plugin = "com.google.gms.google-services")
} else {
    logger.lifecycle(
        "Shamell mobile Firebase: google-services plugin disabled; " +
            "no usable non-placeholder google-services.json found for " +
            if (requestedGoogleServicesFlavors.isEmpty()) {
                "one or more flavors"
            } else {
                requestedGoogleServicesFlavors.joinToString(", ")
            }
    )
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
val requireProductionSigning = (
    gradlePropOrEnv("REQUIRE_PRODUCTION_SIGNING")
        ?.equals("true", ignoreCase = true)
    ) == true
val releaseTaskRequested = gradle.startParameter.taskNames.any {
    it.contains("release", ignoreCase = true)
}
val playIntegrityCloudProjectNumberRaw = gradlePropOrEnv("playIntegrityCloudProjectNumber")
    ?: gradlePropOrEnv("SHAMELL_PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER")
    ?: "0"
val dartDefines = flutterDartDefines()
val trustedTlsCertificatesDerBase64 = gradlePropOrEnv("TRUSTED_TLS_CERTIFICATES_DER_BASE64")
    ?: dartDefines["TRUSTED_TLS_CERTIFICATES_DER_BASE64"]
    ?: ""
val playIntegrityCloudProjectNumber = playIntegrityCloudProjectNumberRaw.toLongOrNull()
    ?: throw GradleException(
        "playIntegrityCloudProjectNumber must be an integer, got: " +
            playIntegrityCloudProjectNumberRaw
    )

if (requireProductionSigning && releaseTaskRequested && playIntegrityCloudProjectNumber <= 0L) {
    throw GradleException(
        "Production Android release builds require a positive Play Integrity " +
            "cloud project number. Set Gradle property " +
            "playIntegrityCloudProjectNumber or " +
            "SHAMELL_PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER."
    )
}
if (requireProductionSigning && releaseTaskRequested && allowDebugReleaseSigning) {
    throw GradleException(
        "SHAMELL_ALLOW_DEBUG_RELEASE_SIGNING must be false when REQUIRE_PRODUCTION_SIGNING=true."
    )
}
if (requireProductionSigning && releaseTaskRequested && !hasReleaseSigning) {
    throw GradleException(
        "Production Android release builds require release-keystore signing. " +
            "Set SHAMELL_RELEASE_STORE_FILE, SHAMELL_RELEASE_STORE_PASSWORD, " +
            "SHAMELL_RELEASE_KEY_ALIAS, and SHAMELL_RELEASE_KEY_PASSWORD."
    )
}
if (releaseTaskRequested && trustedTlsCertificatesDerBase64.isBlank()) {
    throw GradleException(
        "Android release builds require TRUSTED_TLS_CERTIFICATES_DER_BASE64 " +
            "to keep mobile TLS pinning fail-closed."
    )
}
val expectedSigningCertSha256 = gradlePropOrEnv("androidSigningCertSha256")
    ?: gradlePropOrEnv("SHAMELL_ANDROID_SIGNING_CERT_SHA256")
    ?: ""
val normalizedExpectedSigningCertSha256 = if (expectedSigningCertSha256.isBlank()) {
    ""
} else {
    normalizeSha256HexFingerprint(expectedSigningCertSha256)
}
if (releaseTaskRequested && normalizedExpectedSigningCertSha256.isBlank()) {
    throw GradleException(
        "Android release builds require SHAMELL_ANDROID_SIGNING_CERT_SHA256 " +
            "(or androidSigningCertSha256) to enable runtime signing-certificate verification."
    )
}
val allowEmulatorQaRuntimeIntegrityBypass = (
    gradlePropOrEnv("SHAMELL_ALLOW_EMULATOR_QA_RUNTIME_INTEGRITY_BYPASS")
        ?.equals("true", ignoreCase = true)
    ) == true
if (requireProductionSigning && releaseTaskRequested && allowEmulatorQaRuntimeIntegrityBypass) {
    throw GradleException(
        "SHAMELL_ALLOW_EMULATOR_QA_RUNTIME_INTEGRITY_BYPASS must be false " +
            "when REQUIRE_PRODUCTION_SIGNING=true."
    )
}
val releaseUsesDebugSigningEscapeHatch = releaseTaskRequested &&
    allowDebugReleaseSigning &&
    !hasReleaseSigning
val runtimeIntegrityFailClosed = !releaseUsesDebugSigningEscapeHatch

android {
    namespace = "online.shamell.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "28.1.13356709"

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
            resValue("string", "app_name", "SyrChat")
        }
        create("ride") {
            dimension = "app"
            applicationId = "online.shamell.ride"
            resValue("string", "app_name", "SyrChat Ride")
        }
        create("driver") {
            dimension = "app"
            applicationId = "online.shamell.driver"
            resValue("string", "app_name", "SyrChat Driver")
        }
        create("operator") {
            dimension = "app"
            applicationId = "online.shamell.operator"
            resValue("string", "app_name", "SyrChat Control")
        }
        create("busOperator") {
            dimension = "app"
            applicationId = "online.shamell.busoperator"
            resValue("string", "app_name", "SyrChat Bus")
        }
        create("hotelOperator") {
            dimension = "app"
            applicationId = "online.shamell.hoteloperator"
            resValue("string", "app_name", "SyrChat Hotels")
        }
        create("syrcom") {
            dimension = "app"
            applicationId = "online.shamell.syrcom"
            resValue("string", "app_name", "SyrCom")
        }
        create("admin") {
            dimension = "app"
            applicationId = "online.shamell.app.admin"
            resValue("string", "app_name", "SyrChat Admin")
        }
    }

    defaultConfig {
        // Base config; per-flavor applicationId is set in productFlavors above.
        minSdk = maxOf(flutter.minSdkVersion, 26)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    packaging {
        jniLibs {
            useLegacyPackaging = false
        }
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
            isDebuggable = false
            isJniDebuggable = false
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
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
        buildTypes.configureEach {
            buildConfigField(
                "long",
                "PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER",
                playIntegrityCloudProjectNumber.toString()
            )
            buildConfigField(
                "String",
                "EXPECTED_SIGNING_CERT_SHA256",
                "\"$normalizedExpectedSigningCertSha256\""
            )
            buildConfigField(
                "boolean",
                "RUNTIME_INTEGRITY_FAIL_CLOSED",
                runtimeIntegrityFailClosed.toString()
            )
            buildConfigField(
                "boolean",
                "ALLOW_EMULATOR_QA_RUNTIME_INTEGRITY_BYPASS",
                allowEmulatorQaRuntimeIntegrityBypass.toString()
            )
        }
    }
}

androidComponents {
    beforeVariants(selector().all()) { variant ->
        val appFlavor = variant.productFlavors
            .firstOrNull { it.first == "app" }
            ?.second
        if (appFlavor != "user" &&
            appFlavor != "ride" &&
            appFlavor != "driver" &&
            appFlavor != "operator" &&
            appFlavor != "busOperator" &&
            appFlavor != "syrcom"
        ) {
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

    // Google Play Integrity API (hardware-backed attestation layer).
    implementation("com.google.android.play:integrity:1.3.0")
}
