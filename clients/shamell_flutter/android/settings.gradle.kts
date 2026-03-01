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
        // JitPack hosts some Flutter Android transitive deps (e.g. com.github.*)
        maven(url = uri("https://jitpack.io")) {
            content {
                includeGroupByRegex("com\\.github(\\..*)?")
            }
        }
        // TomTom Android SDK
        maven(url = uri("https://repositories.tomtom.com/artifactory/maven")) {
            content {
                includeGroupByRegex("com\\.tomtom(\\..*)?")
            }
        }
    }
}

// Ensure all builds (including included Flutter gradle plugin project) use these repos
import org.gradle.api.initialization.resolve.RepositoriesMode
dependencyResolutionManagement {
    // Many third-party Flutter Android plugins still inject project-level
    // repositories; prefer project repos to avoid build-log warning floods.
    repositoriesMode.set(RepositoriesMode.PREFER_PROJECT)
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
        // Required for Flutter engine/artifacts
        maven(url = uri("https://storage.googleapis.com/download.flutter.io"))
        // JitPack hosts some Flutter Android transitive deps (e.g. com.github.*)
        maven(url = uri("https://jitpack.io")) {
            content {
                includeGroupByRegex("com\\.github(\\..*)?")
            }
        }
        // TomTom Android SDK
        maven(url = uri("https://repositories.tomtom.com/artifactory/maven")) {
            content {
                includeGroupByRegex("com\\.tomtom(\\..*)?")
            }
        }
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.9.1" apply false
    // Keep KGP on 2.0.x until flutter_webrtc supports KGP >= 2.1 reliably.
    id("org.jetbrains.kotlin.android") version "2.0.21" apply false
    id("com.google.gms.google-services") version "4.4.2" apply false
}

include(":app")
