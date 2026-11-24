package dk.tidytag.companion

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.Uri
import android.os.Bundle
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.provider.Settings
import android.view.Gravity
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.Switch
import android.widget.TextView
import java.net.Inet4Address

/** One screen: on/off, status, address, pairing code, paired PCs, permissions. */
class MainActivity : Activity() {
    private lateinit var onOff: Switch
    private lateinit var status: TextView
    private lateinit var address: TextView
    private lateinit var code: TextView
    private lateinit var pcs: LinearLayout
    private lateinit var permissions: Button
    private val handler = Handler(Looper.getMainLooper())
    private val refresh = object : Runnable {
        override fun run() { update(); handler.postDelayed(this, 1000) }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val pad = (16 * resources.displayMetrics.density).toInt()
        val root = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(pad, pad, pad, pad) }
        fun text(size: Float) = TextView(this).apply { textSize = size; setPadding(0, pad / 2, 0, pad / 2) }
        root.addView(text(22f).apply { text = getString(R.string.app_name) })
        onOff = Switch(this).apply {
            text = getString(R.string.server_switch)
            textSize = 18f
            setOnCheckedChangeListener { _, on ->
                val i = Intent(this@MainActivity, CompanionService::class.java)
                if (on) startForegroundService(i) else stopService(i)
                handler.postDelayed({ update() }, 300)
            }
        }
        root.addView(onOff)
        status = text(16f); root.addView(status)
        address = text(16f); root.addView(address)
        code = text(28f).apply { gravity = Gravity.CENTER }; root.addView(code)
        permissions = Button(this).apply { text = getString(R.string.grant_access); setOnClickListener { askAccess() } }
        root.addView(permissions)
        root.addView(text(16f).apply { text = getString(R.string.paired_pcs) })
        pcs = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        root.addView(pcs)
        // Android 15 draws apps edge to edge: keep the content clear of the status and navigation bars
        val scroll = ScrollView(this).apply { addView(root) }
        scroll.setOnApplyWindowInsetsListener { v, insets ->
            val bars = insets.getInsets(android.view.WindowInsets.Type.systemBars())
            v.setPadding(bars.left, bars.top, bars.right, bars.bottom)
            insets
        }
        setContentView(scroll)
        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1)
    }

    override fun onResume() {
        super.onResume()
        onOff.isChecked = CompanionService.server != null
        handler.post(refresh)
    }

    override fun onPause() {
        handler.removeCallbacks(refresh)
        super.onPause()
    }

    private fun hasAccess() = Environment.isExternalStorageManager() && MediaStore.canManageMedia(this)

    private fun askAccess() {
        val intent = if (!Environment.isExternalStorageManager())
            Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION, Uri.parse("package:$packageName"))
        else
            Intent(Settings.ACTION_REQUEST_MANAGE_MEDIA, Uri.parse("package:$packageName"))
        startActivity(intent)
    }

    private fun ipAddress(): String? {
        val cm = getSystemService(ConnectivityManager::class.java)
        val lp: LinkProperties = cm.getLinkProperties(cm.activeNetwork) ?: return null
        return lp.linkAddresses.map { it.address }.firstOrNull { it is Inet4Address }?.hostAddress
    }

    private fun update() {
        val s = CompanionService.server
        permissions.visibility = if (hasAccess()) android.view.View.GONE else android.view.View.VISIBLE
        status.text = when {
            !hasAccess() -> getString(R.string.status_no_access)
            s == null -> getString(R.string.status_off)
            else -> getString(R.string.status_on)
        }
        address.text = if (s != null) getString(R.string.address, "${ipAddress() ?: "?"}:${CompanionService.PORT}") else ""
        code.text = s?.let { getString(R.string.code, it.tokens.pairingCode) } ?: ""
        val tokens = s?.tokens ?: CompanionService.tokens(this)
        pcs.removeAllViews()
        for ((token, name) in tokens.paired()) {
            val row = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
            row.addView(TextView(this).apply {
                text = name.ifEmpty { "PC" }; textSize = 16f
                layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
            })
            row.addView(Button(this).apply {
                text = getString(R.string.remove)
                setOnClickListener { tokens.remove(token); update() }
            })
            pcs.addView(row)
        }
    }
}
