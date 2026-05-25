package online.shamell.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import androidx.core.app.NotificationCompat

/**
 * Foreground service that plays the device's default ringtone in a continuous
 * loop while an inbound Shamell call is ringing.
 *
 * Why a foreground service instead of relying on the notification channel's
 * built-in ringtone:
 * - Android plays a channel's default sound exactly ONCE when the notification
 *   is posted. For a call ringer that needs to keep ringing for ~30 seconds
 *   until accept/decline/timeout, the OS provides no built-in looping path
 *   without a [`CallStyle`](https://developer.android.com/reference/androidx/core/app/NotificationCompat.CallStyle)
 *   notification, which flutter_local_notifications does not yet support.
 * - Audio playback in the background on Android 10+ requires either an active
 *   foreground service or a system call screen. We pick the foreground-service
 *   route so the ringer is independent of the Flutter UI lifecycle.
 *
 * Lifecycle:
 *  - Start from the Flutter side via `IncomingCallRinger.start()` (Dart) →
 *    `MethodChannel("shamell/incoming_call_ringer")` → `start(context)` here.
 *  - Stop from the Flutter side via `IncomingCallRinger.stop()` when the user
 *    taps Accept/Decline or the bootstrap-side timeout fires.
 *  - The service's own foreground notification is silent + low-importance; it
 *    exists purely so Android lets us run a background MediaPlayer. The
 *    user-visible ringer banner is the separate `showIncomingCall(...)`
 *    notification on the `incoming_call_audio_v2` / `incoming_call_video_v2`
 *    channels, which we deliberately created with `playSound = false` to
 *    avoid a double-ring against this service's loop.
 */
class IncomingCallRingerService : Service() {
    private var player: MediaPlayer? = null
    private val handler = Handler(Looper.getMainLooper())
    private val missedCallRunnable = Runnable { onMissedCallTimeout() }
    private var callerLabel: String = ""
    private var callerSubtitle: String = ""
    private var modeIsVideo: Boolean = false
    private var stopReason: String = ""

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        ensureForegroundChannel()
        ensureMissedCallChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopReason = intent.getStringExtra(EXTRA_STOP_REASON) ?: STOP_REASON_EXTERNAL
            stopAndClose()
            return START_NOT_STICKY
        }
        // Cache caller metadata so the +30s missed-call fallback notification
        // has the right name + mode without re-deriving it from Dart state.
        callerLabel = intent?.getStringExtra(EXTRA_CALLER_LABEL).orEmpty()
        callerSubtitle = intent?.getStringExtra(EXTRA_CALLER_SUBTITLE).orEmpty()
        modeIsVideo = (intent?.getStringExtra(EXTRA_MODE) ?: "audio")
            .equals("video", ignoreCase = true)
        startForegroundCompat()
        startRinging()
        scheduleMissedCallFallback()
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        handler.removeCallbacks(missedCallRunnable)
        stopAndClose()
        super.onDestroy()
    }

    private fun scheduleMissedCallFallback() {
        handler.removeCallbacks(missedCallRunnable)
        handler.postDelayed(missedCallRunnable, MISSED_CALL_TIMEOUT_MS)
    }

    private fun onMissedCallTimeout() {
        // Reached +30 s without the user (or the peer) cancelling the ringer.
        // Post a missed-call notification with the cached caller label and
        // let the service shut itself down.
        showMissedCallNotification()
        stopReason = STOP_REASON_TIMEOUT
        stopAndClose()
    }

    private fun showMissedCallNotification() {
        val title = if (callerLabel.isNotBlank()) {
            "Missed call from $callerLabel"
        } else if (modeIsVideo) {
            "Missed video call"
        } else {
            "Missed call"
        }
        val body = if (callerSubtitle.isNotBlank()) callerSubtitle
        else if (modeIsVideo) "You missed an incoming video call" else "You missed an incoming voice call"
        val builder = NotificationCompat.Builder(this, MISSED_CALL_CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setCategory(NotificationCompat.CATEGORY_MISSED_CALL)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setShowWhen(true)
            .setWhen(System.currentTimeMillis())
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(MISSED_CALL_NOTIFICATION_ID, builder.build())
    }

    private fun startForegroundCompat() {
        val notification = buildForegroundNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            // Android 14+: foregroundServiceType must match the permission
            // declared in the manifest. We declared `phoneCall`, which gates
            // call-related audio + microphone use.
            startForeground(
                FG_NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_PHONE_CALL
            )
        } else {
            startForeground(FG_NOTIFICATION_ID, notification)
        }
    }

    private fun startRinging() {
        if (player != null) return
        try {
            val ringtoneUri =
                RingtoneManager.getActualDefaultRingtoneUri(
                    applicationContext,
                    RingtoneManager.TYPE_RINGTONE
                )
                    ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
            if (ringtoneUri == null) {
                Log.w(TAG, "no default ringtone uri available")
                return
            }
            player = MediaPlayer().apply {
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                        .build()
                )
                setDataSource(applicationContext, ringtoneUri)
                isLooping = true
                setOnErrorListener { _, what, extra ->
                    Log.w(TAG, "ringer mp error what=$what extra=$extra")
                    true
                }
                prepare()
                start()
            }
        } catch (e: Exception) {
            Log.w(TAG, "ringer mp start failed: ${e.message}", e)
            player = null
        }
    }

    private fun stopAndClose() {
        handler.removeCallbacks(missedCallRunnable)
        runCatching { player?.stop() }
        runCatching { player?.release() }
        player = null
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        stopSelf()
    }

    private fun ensureMissedCallChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (nm.getNotificationChannel(MISSED_CALL_CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            MISSED_CALL_CHANNEL_ID,
            "Missed calls",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Notifications surfaced when an incoming SyrChat call is not answered"
            enableVibration(true)
            setShowBadge(true)
        }
        nm.createNotificationChannel(channel)
    }

    private fun ensureForegroundChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (nm.getNotificationChannel(FG_CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            FG_CHANNEL_ID,
            "Incoming-call ringer",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description =
                "Background service that plays the looped ringtone while a SyrChat call is ringing"
            setSound(null, null)
            enableVibration(false)
            setShowBadge(false)
            lockscreenVisibility = Notification.VISIBILITY_SECRET
        }
        nm.createNotificationChannel(channel)
    }

    private fun buildForegroundNotification(): Notification {
        return NotificationCompat.Builder(this, FG_CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("SyrChat")
            .setContentText("Ringing…")
            .setOngoing(true)
            .setSilent(true)
            .setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setVisibility(NotificationCompat.VISIBILITY_SECRET)
            .build()
    }

    companion object {
        private const val TAG = "ShamellRinger"
        private const val FG_CHANNEL_ID = "shamell_ringer_fg_v1"
        private const val FG_NOTIFICATION_ID = 5101
        private const val MISSED_CALL_CHANNEL_ID = "shamell_missed_call_v1"
        private const val MISSED_CALL_NOTIFICATION_ID = 5102
        private const val MISSED_CALL_TIMEOUT_MS = 30_000L
        const val ACTION_STOP = "online.shamell.app.RINGER_STOP"
        const val EXTRA_CALLER_LABEL = "caller_label"
        const val EXTRA_CALLER_SUBTITLE = "caller_subtitle"
        const val EXTRA_MODE = "mode"
        const val EXTRA_STOP_REASON = "stop_reason"
        const val STOP_REASON_ACCEPT = "accept"
        const val STOP_REASON_DECLINE = "decline"
        const val STOP_REASON_EXTERNAL = "external"
        const val STOP_REASON_TIMEOUT = "timeout"

        /**
         * Start the looped-ringer service. Safe to call multiple times — the
         * service de-dupes player creation in [startRinging] and re-schedules
         * the missed-call fallback fresh each time.
         *
         * `callerLabel` is the resolved name shown on both the live ringer
         * notification (Flutter-side) and the +30 s missed-call follow-up
         * notification. `callerSubtitle` is optional; defaults to a generic
         * "you missed a call" string when blank.
         */
        fun start(
            context: Context,
            callerLabel: String,
            callerSubtitle: String,
            mode: String
        ) {
            val intent = Intent(context, IncomingCallRingerService::class.java)
                .putExtra(EXTRA_CALLER_LABEL, callerLabel)
                .putExtra(EXTRA_CALLER_SUBTITLE, callerSubtitle)
                .putExtra(EXTRA_MODE, mode)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        /**
         * Stop the looped-ringer service. `reason` distinguishes user-driven
         * stops (`accept` / `decline`) from external cancellation paths so the
         * missed-call fallback is suppressed when the user actively answered.
         */
        fun stop(context: Context, reason: String = STOP_REASON_EXTERNAL) {
            val intent = Intent(context, IncomingCallRingerService::class.java)
                .setAction(ACTION_STOP)
                .putExtra(EXTRA_STOP_REASON, reason)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }
    }
}
