package online.shamell.app

import androidx.annotation.NonNull
import com.google.android.play.core.integrity.IntegrityManagerFactory
import com.google.android.play.core.integrity.IntegrityTokenRequest
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "shamell/hardware_attestation"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "play_integrity_token" -> {
                        val nonceB64 = (call.argument<String>("nonce_b64") ?: "").trim()
                        if (nonceB64.isEmpty()) {
                            result.error("bad_request", "nonce_b64 required", null)
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
                                    result.error(
                                        "unavailable",
                                        e.message ?: "Integrity token unavailable",
                                        null
                                    )
                                }
                        } catch (e: Exception) {
                            result.error("unavailable", e.message ?: "Integrity unavailable", null)
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }
}
