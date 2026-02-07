plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Expose the TomTom API key defined in gradle.properties
val tomtomApiKey: String by project

android {
    namespace = "com.syriasuperapp.superapp"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    flavorDimensions += "app"

    productFlavors {
        create("user") {
            dimension = "app"
            applicationId = "com.syriasuperapp.superapp"
            resValue("string", "app_name", "Shamell")
        }
        create("operator") {
            dimension = "app"
            applicationId = "com.syriasuperapp.superapp.operator"
            resValue("string", "app_name", "Shamell Operator")
        }
        create("admin") {
            dimension = "app"
            applicationId = "com.syriasuperapp.superapp.admin"
            resValue("string", "app_name", "Shamell Admin")
        }
    }

    defaultConfig {
        // Base config; per-flavor applicationId is set in productFlavors above.
        minSdk = maxOf(flutter.minSdkVersion, 26)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildFeatures {
        buildConfig = true
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
        // Expose the TomTom API key as a BuildConfig field for all build types.
        buildTypes.configureEach {
            buildConfigField("String", "TOMTOM_API_KEY", "\"$tomtomApiKey\"")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")

    // TomTom Maps SDK – Map Display module
    val tomTomMapsVersion = "1.26.3"
    implementation("com.tomtom.sdk.maps:map-display:$tomTomMapsVersion")
}
