package online.shamell.app

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Bundle
import android.os.Build
import android.os.Debug
import android.os.PowerManager
import android.os.Process
import android.provider.Settings
import android.util.Log
import android.view.WindowManager
import androidx.annotation.NonNull
import com.google.android.play.core.integrity.IntegrityManagerFactory
import com.google.android.play.core.integrity.IntegrityTokenRequest
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest

private const val ATTESTATION_LOG_TAG = "ShamellAttestation"
private val DEBUG_SESSION_TOKEN_RE = Regex("^[0-9a-fA-F]{32}$")
private val DEBUG_CHAT_PEER_ID_RE = Regex("^[A-Za-z0-9_-]{6,128}$")

private object ReleaseRuntimeHardening {
    private val suspiciousMapNeedles = listOf(
        "frida",
        "gum-js-loop",
        "gadget",
        "xposed",
        "substrate",
        "substitute",
        "libhooker",
        "riru",
        "zygisk",
        "magisk",
        "edxp"
    )
    private val suspiciousRuntimeClasses = listOf(
        "de.robv.android.xposed.XposedBridge",
        "de.robv.android.xposed.XC_MethodHook",
        "com.saurik.substrate.MS",
        "io.github.vvb2060.magisk.util.RootUtils"
    )
    private val rootArtifactPaths = listOf(
        "/system/bin/su",
        "/system/xbin/su",
        "/sbin/su",
        "/system/app/Superuser.apk",
        "/data/adb/magisk",
        "/sbin/magisk",
        "/system/bin/failsafe/su"
    )
    private val suspiciousLoopbackPorts = setOf(
        27042, // Frida default
        27043 // Frida alternate
    )
    private val sha256HexRe = Regex("^[0-9a-f]{64}$")
    private val playIntegrityNonceB64Re = Regex("^[A-Za-z0-9_-]{16,256}$")

    fun compromiseSignals(context: Context): List<String> {
        if (BuildConfig.DEBUG) return emptyList()
        val signals = linkedSetOf<String>()
        if (Debug.isDebuggerConnected() || Debug.waitingForDebugger()) {
            signals += "debugger"
        }
        if (tracerPid() > 0) {
            signals += "tracer_pid"
        }
        if (hasSuspiciousMaps()) {
            signals += "suspicious_maps"
        }
        if (hasSuspiciousRuntimeClasses()) {
            signals += "hook_framework_class"
        }
        if (isProbablyEmulator()) {
            signals += "emulator"
        }
        if (isNonUserBuildType()) {
            signals += "non_user_build"
        }
        if (hasMagiskOverlayMounts()) {
            signals += "magisk_overlay_mount"
        }
        if (hasWritableSystemMounts()) {
            signals += "writable_system_mount"
        }
        if (hasSuspiciousLoopbackListener()) {
            signals += "frida_port_listener"
        }
        if (hasRootArtifacts()) {
            signals += "root_artifacts"
        }
        if (isAppDebuggable(context)) {
            signals += "debuggable_flag"
        }
        if (isAppMarkedTestOnly(context)) {
            signals += "test_only_flag"
        }
        if ((Build.TAGS ?: "").contains("test-keys", ignoreCase = true)) {
            signals += "test_keys"
        }
        if (hasSigningCertificateMismatch(context)) {
            signals += "signing_cert_mismatch"
        }
        return signals.toList()
    }

    fun isQaEmulatorSignalSet(signals: List<String>): Boolean {
        if (signals.isEmpty()) return false
        return signals.all {
            it == "emulator" || it == "non_user_build" || it == "test_keys"
        }
    }

    fun isProbablyEmulatorDevice(): Boolean = isProbablyEmulator()

    private fun hasSigningCertificateMismatch(context: Context): Boolean {
        val expected = normalizeFingerprint(BuildConfig.EXPECTED_SIGNING_CERT_SHA256)
        // Fail closed: production runtime attestation must never run without a
        // pinned release signing certificate fingerprint.
        if (expected.isEmpty()) return true
        val digests = loadSigningCertificateDigests(context)
        return digests.isEmpty() || !digests.contains(expected)
    }

    private fun loadSigningCertificateDigests(context: Context): Set<String> {
        return runCatching {
            @Suppress("DEPRECATION")
            val packageInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                context.packageManager.getPackageInfo(
                    context.packageName,
                    PackageManager.GET_SIGNING_CERTIFICATES
                )
            } else {
                context.packageManager.getPackageInfo(
                    context.packageName,
                    PackageManager.GET_SIGNATURES
                )
            }
            @Suppress("DEPRECATION")
            val signatures = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                val signingInfo = packageInfo.signingInfo ?: return@runCatching emptySet()
                if (signingInfo.hasMultipleSigners()) {
                    signingInfo.apkContentsSigners
                } else {
                    signingInfo.signingCertificateHistory
                }
            } else {
                packageInfo.signatures
            }
            signatures
                .orEmpty()
                .mapNotNull { signature ->
                    normalizeFingerprint(
                        sha256Hex(signature.toByteArray())
                    )
                }
                .toSet()
        }.getOrDefault(emptySet())
    }

    private fun sha256Hex(data: ByteArray): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(data)
        return digest.joinToString(separator = "") { byte ->
            "%02x".format(byte)
        }
    }

    private fun normalizeFingerprint(raw: String): String {
        val normalized = raw
            .trim()
            .lowercase()
            .replace(":", "")
            .replace(Regex("[^0-9a-f]"), "")
        return if (sha256HexRe.matches(normalized)) normalized else ""
    }

    fun isValidPlayIntegrityNonceB64(raw: String): Boolean {
        val nonce = raw.trim()
        return playIntegrityNonceB64Re.matches(nonce)
    }

    private fun tracerPid(): Int {
        return runCatching {
            File("/proc/self/status")
                .useLines { lines ->
                    lines.firstOrNull { it.startsWith("TracerPid:") }
                }
                ?.substringAfter(':')
                ?.trim()
                ?.toIntOrNull() ?: 0
        }.getOrDefault(0)
    }

    private fun hasSuspiciousMaps(): Boolean {
        val maps = runCatching {
            File("/proc/self/maps").readText()
        }.getOrDefault("")
        if (maps.isEmpty()) return false
        val lowered = maps.lowercase()
        return suspiciousMapNeedles.any { lowered.contains(it) }
    }

    private fun hasRootArtifacts(): Boolean {
        return rootArtifactPaths.any { path ->
            runCatching { File(path).exists() }.getOrDefault(false)
        }
    }

    private fun hasSuspiciousRuntimeClasses(): Boolean {
        return suspiciousRuntimeClasses.any { className ->
            runCatching {
                Class.forName(className, false, javaClass.classLoader)
                true
            }.getOrDefault(false)
        }
    }

    private fun isProbablyEmulator(): Boolean {
        val fingerprint = (Build.FINGERPRINT ?: "").lowercase()
        val model = (Build.MODEL ?: "").lowercase()
        val manufacturer = (Build.MANUFACTURER ?: "").lowercase()
        val brand = (Build.BRAND ?: "").lowercase()
        val device = (Build.DEVICE ?: "").lowercase()
        val product = (Build.PRODUCT ?: "").lowercase()
        val hardware = (Build.HARDWARE ?: "").lowercase()

        if (fingerprint.contains("generic") || fingerprint.contains("emulator")) return true
        if (model.contains("emulator")
            || model.contains("sdk_gphone")
            || model.contains("android sdk built for x86")
        ) {
            return true
        }
        if (manufacturer.contains("genymotion")) return true
        if (brand.startsWith("generic") && device.startsWith("generic")) return true
        if (product.contains("sdk")
            || product.contains("emulator")
            || product.contains("vbox86p")
        ) {
            return true
        }
        if (hardware.contains("goldfish") || hardware.contains("ranchu")) return true
        return false
    }

    private fun isNonUserBuildType(): Boolean {
        val buildType = (Build.TYPE ?: "").lowercase()
        return buildType == "userdebug" || buildType == "eng"
    }

    private fun hasMagiskOverlayMounts(): Boolean {
        val mountInfo = runCatching {
            File("/proc/self/mountinfo").readText()
        }.getOrDefault("")
        if (mountInfo.isEmpty()) return false
        val lowered = mountInfo.lowercase()
        return lowered.contains("magisk") || lowered.contains("/.magisk")
    }

    private fun hasWritableSystemMounts(): Boolean {
        val lines = runCatching {
            File("/proc/self/mountinfo").readLines()
        }.getOrDefault(emptyList())
        if (lines.isEmpty()) return false
        for (line in lines) {
            val segments = line.split(" - ", limit = 2)
            val mountFields = segments.firstOrNull()
                ?.trim()
                ?.split(Regex("\\s+"))
                .orEmpty()
            if (mountFields.size < 6) continue
            val mountPoint = mountFields[4].trim().lowercase()
            if (mountPoint != "/system"
                && mountPoint != "/vendor"
                && mountPoint != "/product"
            ) {
                continue
            }
            val mountOptions = mountFields[5]
                .split(',')
                .map { it.trim().lowercase() }
            val superOptions = if (segments.size == 2) {
                segments[1]
                    .trim()
                    .split(Regex("\\s+"))
                    .lastOrNull()
                    ?.split(',')
                    ?.map { it.trim().lowercase() }
                    .orEmpty()
            } else {
                emptyList()
            }
            val mountHasRw = mountOptions.any { it == "rw" }
            val superHasRw = superOptions.any { it == "rw" }
            if (superHasRw || (superOptions.isEmpty() && mountHasRw)) {
                return true
            }
        }
        return false
    }

    private fun hasSuspiciousLoopbackListener(): Boolean {
        return hasSuspiciousPortInProcNet("/proc/net/tcp") ||
            hasSuspiciousPortInProcNet("/proc/net/tcp6")
    }

    private fun hasSuspiciousPortInProcNet(path: String): Boolean {
        val lines = runCatching { File(path).readLines() }.getOrDefault(emptyList())
        if (lines.size <= 1) return false
        for (line in lines.drop(1)) {
            val fields = line.trim().split(Regex("\\s+"))
            if (fields.size < 4) continue
            val localAddress = fields[1]
            val stateHex = fields[3].lowercase()
            // LISTEN state in /proc/net/tcp*
            if (stateHex != "0a") continue
            val localPort = parseProcNetPort(localAddress) ?: continue
            if (!suspiciousLoopbackPorts.contains(localPort)) continue
            return true
        }
        return false
    }

    private fun parseProcNetPort(localAddress: String): Int? {
        val hexPort = localAddress.substringAfter(':', missingDelimiterValue = "")
        if (hexPort.isEmpty()) return null
        return hexPort.toIntOrNull(16)
    }

    private fun isAppDebuggable(context: Context): Boolean {
        val flags = context.applicationInfo.flags
        return (flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
    }

    private fun isAppMarkedTestOnly(context: Context): Boolean {
        val flags = context.applicationInfo.flags
        return (flags and ApplicationInfo.FLAG_TEST_ONLY) != 0
    }
}

class MainActivity : FlutterActivity() {
    private val channelName = "shamell/hardware_attestation"
    private val androidSystemChannelName = "shamell/android_system"
    private var pendingDebugSessionSeed: Map<String, String>? = null
    private var pendingDebugChatSeed: Map<String, String>? = null
    private fun clientVisibleCompromiseSignals(signals: List<String>): List<String> =
        if (BuildConfig.DEBUG) signals else emptyList()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        rememberDebugSeeds(intent)

        if (!BuildConfig.DEBUG) {
            enforceReleaseRuntimeIntegrity()
            // Reduce casual data exfiltration via screenshots, recordings, and
            // Recents thumbnails on production builds.
            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                setRecentsScreenshotEnabled(false)
            }
        }
    }

    override fun onResume() {
        super.onResume()
        enforceReleaseRuntimeIntegrity()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        rememberDebugSeeds(intent)
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "runtime_compromise_state" -> {
                        result.success(runtimeCompromiseState())
                    }

                    "android_sdk_int" -> {
                        result.success(Build.VERSION.SDK_INT)
                    }

                    "android_secure_id" -> {
                        val secureId =
                            runCatching {
                                Settings.Secure.getString(
                                    contentResolver,
                                    Settings.Secure.ANDROID_ID
                                )?.trim()?.takeIf { it.isNotEmpty() }
                            }.getOrNull()
                        if (BuildConfig.DEBUG) {
                            Log.i(
                                ATTESTATION_LOG_TAG,
                                "android_secure_id resolved=${secureId ?: "<empty>"}"
                            )
                        }
                        result.success(secureId)
                    }

                    "android_is_emulator" -> {
                        result.success(ReleaseRuntimeHardening.isProbablyEmulatorDevice())
                    }

                    "runtime_integrity_fail_closed" -> {
                        result.success(BuildConfig.RUNTIME_INTEGRITY_FAIL_CLOSED)
                    }

                    "play_integrity_token" -> {
                        val signals = ReleaseRuntimeHardening.compromiseSignals(this)
                        if (signals.isNotEmpty()) {
                            Log.w(
                                ATTESTATION_LOG_TAG,
                                "play_integrity_token blocked by runtime signals=$signals"
                            )
                            result.error(
                                "compromised_runtime",
                                "Runtime integrity check failed",
                                if (BuildConfig.DEBUG) signals else null
                            )
                            return@setMethodCallHandler
                        }
                        val nonceB64 = (call.argument<String>("nonce_b64") ?: "").trim()
                        if (nonceB64.isEmpty()) {
                            result.error("bad_request", "nonce_b64 required", null)
                            return@setMethodCallHandler
                        }
                        if (!ReleaseRuntimeHardening.isValidPlayIntegrityNonceB64(nonceB64)) {
                            result.error("bad_request", "nonce_b64 invalid", null)
                            return@setMethodCallHandler
                        }

                        try {
                            val mgr = IntegrityManagerFactory.create(applicationContext)
                            val builder = IntegrityTokenRequest.builder().setNonce(nonceB64)
                            val cloudProject = BuildConfig.PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER
                            if (cloudProject > 0) {
                                builder.setCloudProjectNumber(cloudProject)
                            }
                            val req = builder.build()
                            mgr.requestIntegrityToken(req)
                                .addOnSuccessListener { r ->
                                    result.success(r.token())
                                }
                                .addOnFailureListener { e ->
                                    Log.w(
                                        ATTESTATION_LOG_TAG,
                                        "requestIntegrityToken failed: ${e.message}",
                                        e
                                    )
                                    result.error(
                                        "unavailable",
                                        e.message ?: "Integrity token unavailable",
                                        null
                                    )
                                }
                        } catch (e: Exception) {
                            Log.e(
                                ATTESTATION_LOG_TAG,
                                "requestIntegrityToken threw: ${e.message}",
                                e
                            )
                            result.error("unavailable", e.message ?: "Integrity unavailable", null)
                        }
                    }

                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "shamell/incoming_call_ringer")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        val callerLabel = (call.argument<String>("caller_label") ?: "").trim()
                        val callerSubtitle =
                            (call.argument<String>("caller_subtitle") ?: "").trim()
                        val mode = (call.argument<String>("mode") ?: "audio").trim()
                        runCatching {
                            IncomingCallRingerService.start(
                                applicationContext,
                                callerLabel = callerLabel,
                                callerSubtitle = callerSubtitle,
                                mode = mode
                            )
                        }
                            .onSuccess { result.success(true) }
                            .onFailure { e ->
                                Log.w(ATTESTATION_LOG_TAG, "ringer start failed: ${e.message}", e)
                                result.success(false)
                            }
                    }

                    "stop" -> {
                        val reason = (call.argument<String>("reason")
                            ?: IncomingCallRingerService.STOP_REASON_EXTERNAL).trim()
                        val sanitized = when (reason) {
                            IncomingCallRingerService.STOP_REASON_ACCEPT,
                            IncomingCallRingerService.STOP_REASON_DECLINE,
                            IncomingCallRingerService.STOP_REASON_EXTERNAL,
                            IncomingCallRingerService.STOP_REASON_TIMEOUT -> reason
                            else -> IncomingCallRingerService.STOP_REASON_EXTERNAL
                        }
                        runCatching {
                            IncomingCallRingerService.stop(applicationContext, sanitized)
                        }
                            .onSuccess { result.success(true) }
                            .onFailure { e ->
                                Log.w(ATTESTATION_LOG_TAG, "ringer stop failed: ${e.message}", e)
                                result.success(false)
                            }
                    }

                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, androidSystemChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "driver_background_hardening_status" -> {
                        result.success(driverBackgroundHardeningStatus())
                    }

                    "open_driver_background_battery_settings" -> {
                        result.success(openDriverBackgroundBatterySettings())
                    }

                    "open_driver_background_autostart_settings" -> {
                        result.success(openDriverAutostartSettings())
                    }

                    "open_driver_app_info_settings" -> {
                        result.success(openAppInfoSettings())
                    }

                    "consume_debug_session_seed" -> {
                        result.success(consumeDebugSessionSeed())
                    }

                    "consume_debug_chat_seed" -> {
                        result.success(consumeDebugChatSeed())
                    }

                    else -> result.notImplemented()
                }
            }
    }

    private fun rememberDebugSeeds(intent: Intent?) {
        rememberDebugSessionSeed(intent)
        rememberDebugChatSeed(intent)
    }

    private fun rememberDebugSessionSeed(intent: Intent?) {
        if (!BuildConfig.DEBUG) return
        val extras = intent?.extras ?: return
        val token = (extras.getString("shamell_debug_session_token") ?: "").trim()
        val baseUrl = normalizeDebugSessionBaseUrl(
            extras.getString("shamell_debug_base_url") ?: ""
        )
        if (!DEBUG_SESSION_TOKEN_RE.matches(token) || baseUrl == null) {
            return
        }
        pendingDebugSessionSeed = mapOf(
            "token" to token.lowercase(),
            "base_url" to baseUrl
        )
        Log.i(ATTESTATION_LOG_TAG, "debug session seed captured for $baseUrl")
    }

    private fun rememberDebugChatSeed(intent: Intent?) {
        if (!BuildConfig.DEBUG) return
        val extras = intent?.extras ?: return
        val peerId = (extras.getString("shamell_debug_chat_peer_id") ?: "").trim()
        if (!DEBUG_CHAT_PEER_ID_RE.matches(peerId)) {
            return
        }
        val autoSendText = (extras.getString("shamell_debug_chat_autosend_text") ?: "")
            .trim()
            .takeIf { it.isNotEmpty() }
            ?.take(500)
        pendingDebugChatSeed = buildMap {
            put("peer_id", peerId)
            if (autoSendText != null) {
                put("autosend_text", autoSendText)
            }
        }
        Log.i(ATTESTATION_LOG_TAG, "debug chat seed captured for peer_id=$peerId")
    }

    private fun consumeDebugSessionSeed(): Map<String, String>? {
        if (!BuildConfig.DEBUG) return null
        val seed = pendingDebugSessionSeed
        pendingDebugSessionSeed = null
        return seed
    }

    private fun consumeDebugChatSeed(): Map<String, String>? {
        if (!BuildConfig.DEBUG) return null
        val seed = pendingDebugChatSeed
        pendingDebugChatSeed = null
        return seed
    }

    private fun normalizeDebugSessionBaseUrl(raw: String): String? {
        val value = raw.trim()
        if (value.isEmpty()) return null
        val parsed = runCatching { Uri.parse(value) }.getOrNull() ?: return null
        val scheme = parsed.scheme?.trim()?.lowercase().orEmpty()
        val host = parsed.host?.trim()?.lowercase().orEmpty()
        val isLoopbackHost = host == "localhost" || host == "127.0.0.1" || host == "::1"
        val allowsInsecureLoopback = scheme == "http" && isLoopbackHost
        if ((!allowsInsecureLoopback && scheme != "https") || host.isEmpty()) return null
        if (!parsed.userInfo.isNullOrEmpty() || parsed.fragment != null || parsed.query != null) {
            return null
        }
        val path = parsed.path?.trim().orEmpty()
        if (path.isNotEmpty() && path != "/") {
            return null
        }
        val defaultPort = if (scheme == "https") 443 else 80
        return if (parsed.port != -1 && parsed.port != defaultPort) {
            "$scheme://$host:${parsed.port}"
        } else {
            "$scheme://$host"
        }
    }

    private fun runtimeCompromiseState(): Map<String, Any> {
        val signals = ReleaseRuntimeHardening.compromiseSignals(this)
        if (BuildConfig.ALLOW_EMULATOR_QA_RUNTIME_INTEGRITY_BYPASS &&
            ReleaseRuntimeHardening.isQaEmulatorSignalSet(signals)
        ) {
            return mapOf(
                "compromised" to false,
                "signals" to emptyList<String>()
            )
        }
        return mapOf(
            "compromised" to signals.isNotEmpty(),
            "signals" to clientVisibleCompromiseSignals(signals)
        )
    }

    private fun enforceReleaseRuntimeIntegrity() {
        if (BuildConfig.DEBUG) return
        val signals = ReleaseRuntimeHardening.compromiseSignals(this)
        if (signals.isEmpty()) return
        Log.w(
            ATTESTATION_LOG_TAG,
            "runtime integrity signals=$signals failClosed=${BuildConfig.RUNTIME_INTEGRITY_FAIL_CLOSED}"
        )
        if (BuildConfig.ALLOW_EMULATOR_QA_RUNTIME_INTEGRITY_BYPASS &&
            ReleaseRuntimeHardening.isQaEmulatorSignalSet(signals)
        ) {
            Log.w(
                ATTESTATION_LOG_TAG,
                "runtime integrity emulator QA bypass enabled for signals=$signals"
            )
            return
        }
        if (!BuildConfig.RUNTIME_INTEGRITY_FAIL_CLOSED) {
            // Explicit QA escape hatch: release artifact is still minified/release-mode,
            // but runtime kill-switch is disabled for debug-signed release verification.
            return
        }
        finishAffinity()
        finishAndRemoveTask()
        Process.killProcess(Process.myPid())
    }

    private fun driverBackgroundHardeningStatus(): Map<String, Any> {
        val manufacturer = Build.MANUFACTURER?.trim().orEmpty()
        val brand = Build.BRAND?.trim().orEmpty()
        val batteryOptimizationManaged = Build.VERSION.SDK_INT >= Build.VERSION_CODES.M
        val ignoringBatteryOptimizations = if (batteryOptimizationManaged) {
            val powerManager = getSystemService(Context.POWER_SERVICE) as? PowerManager
            powerManager?.isIgnoringBatteryOptimizations(packageName) == true
        } else {
            true
        }
        return mapOf(
            "manufacturer" to manufacturer,
            "brand" to brand,
            "ignoring_battery_optimizations" to ignoringBatteryOptimizations,
            "can_manage_battery_optimizations" to batteryOptimizationManaged,
            "supports_vendor_autostart_settings" to candidateDriverAutostartIntents().isNotEmpty(),
            "aggressive_background_vendor" to isAggressiveBackgroundVendor(
                manufacturer = manufacturer,
                brand = brand
            )
        )
    }

    private fun isAggressiveBackgroundVendor(
        manufacturer: String,
        brand: String
    ): Boolean {
        val normalized = "$manufacturer $brand".trim().lowercase()
        if (normalized.isEmpty()) return false
        val needles = listOf(
            "xiaomi",
            "redmi",
            "poco",
            "oppo",
            "realme",
            "vivo",
            "iqoo",
            "huawei",
            "honor",
            "oneplus"
        )
        return needles.any { normalized.contains(it) }
    }

    private fun openDriverBackgroundBatterySettings(): Boolean {
        val candidates = mutableListOf<Intent>()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            candidates += Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
        }
        candidates += appInfoSettingsIntent()
        return launchFirstResolvableActivity(candidates)
    }

    private fun openDriverAutostartSettings(): Boolean {
        val candidates = candidateDriverAutostartIntents().toMutableList()
        candidates += appInfoSettingsIntent()
        return launchFirstResolvableActivity(candidates)
    }

    private fun openAppInfoSettings(): Boolean =
        launchFirstResolvableActivity(listOf(appInfoSettingsIntent()))

    private fun appInfoSettingsIntent(): Intent =
        Intent(
            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
            Uri.fromParts("package", packageName, null)
        )

    private fun candidateDriverAutostartIntents(): List<Intent> {
        val packageLabel = applicationInfo.loadLabel(packageManager).toString()
        val manufacturer = Build.MANUFACTURER?.trim()?.lowercase().orEmpty()
        val brand = Build.BRAND?.trim()?.lowercase().orEmpty()
        val normalized = "$manufacturer $brand"
        val intents = mutableListOf<Intent>()

        fun explicitIntent(packageName: String, className: String): Intent =
            Intent().setComponent(ComponentName(packageName, className))

        if (normalized.contains("xiaomi") ||
            normalized.contains("redmi") ||
            normalized.contains("poco")
        ) {
            intents += explicitIntent(
                "com.miui.securitycenter",
                "com.miui.permcenter.autostart.AutoStartManagementActivity"
            )
            intents += explicitIntent(
                "com.miui.powerkeeper",
                "com.miui.powerkeeper.ui.HiddenAppsConfigActivity"
            ).apply {
                putExtra("package_name", packageName)
                putExtra("package_label", packageLabel)
            }
        }
        if (normalized.contains("oppo") ||
            normalized.contains("realme") ||
            normalized.contains("oneplus")
        ) {
            intents += explicitIntent(
                "com.coloros.safecenter",
                "com.coloros.safecenter.startupapp.StartupAppListActivity"
            )
            intents += explicitIntent(
                "com.oplus.safecenter",
                "com.oplus.safecenter.startupapp.StartupAppListActivity"
            )
            intents += explicitIntent(
                "com.oneplus.security",
                "com.oneplus.security.chainlaunch.view.ChainLaunchAppListActivity"
            )
        }
        if (normalized.contains("vivo") || normalized.contains("iqoo")) {
            intents += explicitIntent(
                "com.iqoo.secure",
                "com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity"
            )
            intents += explicitIntent(
                "com.vivo.permissionmanager",
                "com.vivo.permissionmanager.activity.BgStartUpManagerActivity"
            )
        }
        if (normalized.contains("huawei") || normalized.contains("honor")) {
            intents += explicitIntent(
                "com.huawei.systemmanager",
                "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity"
            )
            intents += explicitIntent(
                "com.huawei.systemmanager",
                "com.huawei.systemmanager.optimize.process.ProtectActivity"
            )
        }

        return intents
    }

    private fun launchFirstResolvableActivity(candidates: List<Intent>): Boolean {
        for (candidate in candidates) {
            val intent = candidate.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            val resolved = intent.resolveActivity(packageManager) ?: continue
            runCatching {
                startActivity(intent)
            }.onSuccess {
                Log.i(
                    ATTESTATION_LOG_TAG,
                    "launched android settings intent=${resolved.flattenToShortString()}"
                )
                return true
            }
        }
        return false
    }
}
