package dk.tidytag.companion

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import dk.tidytag.companion.core.CompanionServer
import dk.tidytag.companion.core.Discovery
import dk.tidytag.companion.core.Json
import dk.tidytag.companion.core.TokenStore
import java.io.File
import java.util.UUID

/** Runs the server while switched on; Android would stop a background server otherwise. */
class CompanionService : Service() {

    companion object {
        const val PORT = 47100
        @Volatile var server: CompanionServer? = null
            private set
        @Volatile var lastClient: String = ""

        fun tokens(context: Context) = TokenStore(File(context.filesDir, "tokens.txt"))

        fun deviceId(context: Context): String {
            val prefs = context.getSharedPreferences("companion", Context.MODE_PRIVATE)
            return prefs.getString("id", null) ?: UUID.randomUUID().toString().also {
                prefs.edit().putString("id", it).apply()
            }
        }
    }

    private var discovery: Discovery? = null
    private var multicastLock: WifiManager.MulticastLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForeground(1, notification(), ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        if (server == null) {
            val storage = AndroidStorage(this)
            val s = CompanionServer(storage, MediaScanHooks(this, storage), PORT, tokens(this))
            s.deviceName = Build.MODEL
            s.deviceId = deviceId(this)
            s.onPaired = { pc -> lastClient = pc }
            s.start(fi.iki.elonen.NanoHTTPD.SOCKET_READ_TIMEOUT, false)
            server = s
            // broadcasts are dropped by some Wi-Fi drivers without this lock
            multicastLock = (getSystemService(WIFI_SERVICE) as WifiManager)
                .createMulticastLock("TidyTag").apply { setReferenceCounted(false); acquire() }
            discovery = Discovery { Json.obj("name" to s.deviceName, "port" to PORT, "id" to s.deviceId) }
                .also { it.start() }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        discovery?.stop()
        server?.stop()
        server = null
        multicastLock?.release()
        super.onDestroy()
    }

    private fun notification(): Notification {
        val nm = getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(NotificationChannel("server", getString(R.string.channel), NotificationManager.IMPORTANCE_LOW))
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE)
        return Notification.Builder(this, "server")
            .setContentTitle(getString(R.string.notification))
            .setSmallIcon(R.drawable.ic_launcher)
            .setContentIntent(open)
            .setOngoing(true)
            .build()
    }
}
