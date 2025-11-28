pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        // Prefer official repositories for Android/Flutter artifacts
        google()
        mavenCentral()
        gradlePluginPortal()
        // Required for Flutter engine/artifacts
        maven(url = uri("https://storage.googleapis.com/download.flutter.io"))
        // TomTom Android SDK
        maven(url = uri("https://repositories.tomtom.com/artifactory/maven"))
    }
}

// Ensure all builds (including included Flutter gradle plugin project) use these repos
import org.gradle.api.initialization.resolve.RepositoriesMode
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.PREFER_SETTINGS)
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
        // Required for Flutter engine/artifacts
        maven(url = uri("https://storage.googleapis.com/download.flutter.io"))
        // TomTom Android SDK
        maven(url = uri("https://repositories.tomtom.com/artifactory/maven"))
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.7.2" apply false
    id("org.jetbrains.kotlin.android") version "2.1.0" apply false
    id("com.google.gms.google-services") version "4.4.2" apply false
}

include(":app")
