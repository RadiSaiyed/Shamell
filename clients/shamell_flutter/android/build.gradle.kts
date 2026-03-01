import com.android.build.gradle.BaseExtension
import org.gradle.api.tasks.compile.JavaCompile
import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.tasks.KotlinCompile

allprojects {
    repositories {
        google()
        mavenCentral()
        maven(url = uri("https://storage.googleapis.com/download.flutter.io"))
        maven(url = uri("https://jitpack.io"))
        maven(url = uri("https://repositories.tomtom.com/artifactory/maven"))
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

    // Some third-party Flutter plugins set mismatched Java/Kotlin JVM targets
    // (for example Java 1.8 with Kotlin 17). Match Kotlin to the module's
    // Java compile target to avoid Gradle target-validation failures.
    fun alignKotlinJvmTargetToJavaNow() {
        tasks.withType<KotlinCompile>().configureEach {
            val javaTaskName = name.replace("Kotlin", "JavaWithJavac")
            val moduleJavaTask = tasks.findByName(javaTaskName) as? JavaCompile
            val fallbackJavaTask = tasks.withType<JavaCompile>().firstOrNull()
            val javaTarget = (
                moduleJavaTask?.targetCompatibility
                    ?: fallbackJavaTask?.targetCompatibility
                )?.trim()
            if (!javaTarget.isNullOrEmpty()) {
                runCatching { JvmTarget.fromTarget(javaTarget) }
                    .onSuccess { compilerOptions.jvmTarget.set(it) }
            }
        }
    }

    fun alignKotlinJvmTargetWhenReady() {
        if (state.executed) {
            alignKotlinJvmTargetToJavaNow()
        } else {
            afterEvaluate {
                alignKotlinJvmTargetToJavaNow()
            }
        }
    }

    plugins.withId("com.android.application") {
        enableBuildConfigIfAndroidModule()
        ensureNamespaceIfMissing()
        alignKotlinJvmTargetWhenReady()
    }
    plugins.withId("com.android.library") {
        enableBuildConfigIfAndroidModule()
        ensureNamespaceIfMissing()
        alignKotlinJvmTargetWhenReady()
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
