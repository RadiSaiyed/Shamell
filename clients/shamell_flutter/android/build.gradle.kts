import com.android.build.gradle.BaseExtension
import org.gradle.api.tasks.compile.JavaCompile
import org.jetbrains.kotlin.gradle.tasks.KotlinCompile

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")

    // Ensure all Android modules (including plugin modules like :app_links)
    // have BuildConfig generation enabled, which is required when they
    // declare custom BuildConfig fields.
    fun enableBuildConfigIfAndroidModule() {
        val androidExt = extensions.findByName("android")
        if (androidExt is BaseExtension) {
            androidExt.buildFeatures.apply {
                // Keep other flags as-is; only ensure BuildConfig is on.
                buildConfig = true
            }
        }
    }

    // AGP 8 requires namespace for every Android module. Some third-party
    // Flutter plugins still omit it; add a deterministic fallback.
    fun ensureNamespaceIfMissing() {
        val androidExt = extensions.findByName("android") ?: return
        val getter = androidExt.javaClass.methods.firstOrNull {
            it.name == "getNamespace" && it.parameterCount == 0
        } ?: return
        val setter = androidExt.javaClass.methods.firstOrNull {
            it.name == "setNamespace" && it.parameterCount == 1
        } ?: return

        val current = getter.invoke(androidExt) as? String
        if (!current.isNullOrBlank()) return

        val sanitized = project.name
            .replace(Regex("[^A-Za-z0-9_]"), "_")
            .lowercase()
        setter.invoke(androidExt, "dev.shamell.$sanitized")
    }

    // Some third-party Flutter plugins are inconsistent (e.g. Java 1.8 vs Kotlin 17).
    // Force a uniform bytecode target across subprojects to keep AGP/Kotlin tasks compatible.
    fun alignJvmTargets() {
        tasks.withType<JavaCompile>().configureEach {
            sourceCompatibility = JavaVersion.VERSION_17.toString()
            targetCompatibility = JavaVersion.VERSION_17.toString()
        }
        tasks.withType<KotlinCompile>().configureEach {
            kotlinOptions.jvmTarget = JavaVersion.VERSION_17.toString()
        }
    }

    plugins.withId("com.android.application") {
        enableBuildConfigIfAndroidModule()
        ensureNamespaceIfMissing()
        alignJvmTargets()
    }
    plugins.withId("com.android.library") {
        enableBuildConfigIfAndroidModule()
        ensureNamespaceIfMissing()
        alignJvmTargets()
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
