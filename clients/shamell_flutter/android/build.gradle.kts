import com.android.build.gradle.BaseExtension
import org.gradle.api.JavaVersion
import org.gradle.api.tasks.compile.JavaCompile
import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.tasks.KotlinCompile

val shamellForcedAgpVersion = "8.9.1"
val shamellForcedKgpVersion = "2.2.21"

// Third-party Flutter Android plugins often pin their own AGP/KGP versions in
// buildscript classpaths. Force a single toolchain early to avoid pulling
// multiple incompatible Android build stacks during one app build.
gradle.beforeProject {
    buildscript.configurations.configureEach {
        resolutionStrategy.eachDependency {
            if (requested.group == "com.android.tools.build" &&
                requested.name == "gradle"
            ) {
                useVersion(shamellForcedAgpVersion)
                because("Align Flutter plugin AGP versions with Shamell")
            }
            if (requested.group == "org.jetbrains.kotlin" &&
                requested.name == "kotlin-gradle-plugin"
            ) {
                useVersion(shamellForcedKgpVersion)
                because("Align Flutter plugin Kotlin Gradle plugin versions with Shamell")
            }
        }
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
        maven(url = uri("https://storage.googleapis.com/download.flutter.io"))
        maven(url = uri("https://jitpack.io"))
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

    // Keep all Android plugin Java compilation on the JDK available in this
    // workspace. Some plugins request Java 21 by default, but the app and CI
    // are configured around Java 17.
    tasks.withType<JavaCompile>().configureEach {
        sourceCompatibility = JavaVersion.VERSION_17.toString()
        targetCompatibility = JavaVersion.VERSION_17.toString()
    }

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
