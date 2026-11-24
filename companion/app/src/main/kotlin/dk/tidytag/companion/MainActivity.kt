package dk.tidytag.companion

import android.Manifest
import android.app.Activity
import android.app.AlertDialog
import android.app.LocaleManager
import android.os.Build
import android.os.LocaleList
import android.content.Intent
import android.content.res.ColorStateList
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.net.ConnectivityManager
import android.net.Uri
import android.os.Bundle
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.provider.Settings
import android.view.Gravity
import android.view.View
import android.view.WindowInsets
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.Switch
import android.widget.TextView
import java.net.Inet4Address

/** One screen of cards: status with on/off, access steps, pairing code, paired PCs. */
class MainActivity : Activity() {
    private lateinit var onOff: Switch
    private lateinit var dot: View
    private lateinit var title: TextView
    private lateinit var status: TextView
    private lateinit var address: TextView
    private lateinit var accessCard: LinearLayout
    private lateinit var stepFiles: TextView
    private lateinit var stepTrash: TextView
    private lateinit var grant: Button
    private lateinit var codeCard: LinearLayout
    private lateinit var code: TextView
    private lateinit var pcs: LinearLayout
    private val handler = Handler(Looper.getMainLooper())
    private var pairingOpenedFor: Any? = null
    private val refresh = object : Runnable {
        override fun run() { update(); handler.postDelayed(this, 1000) }
    }

    private fun dp(v: Int) = (v * resources.displayMetrics.density).toInt()
    private fun color(id: Int) = getColor(id)

    private fun text(size: Float, colorId: Int = R.color.text, bold: Boolean = false) = TextView(this).apply {
        textSize = size
        setTextColor(color(colorId))
        if (bold) typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
    }

    private fun card(parent: LinearLayout) = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        setPadding(dp(20), dp(18), dp(20), dp(18))
        background = GradientDrawable().apply { cornerRadius = dp(20).toFloat(); setColor(color(R.color.card)) }
        parent.addView(this, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT).apply { topMargin = dp(12) })
    }

    private fun heading(parent: LinearLayout, id: Int) =
        parent.addView(text(14f, R.color.muted, true).apply { text = getString(id); setPadding(0, 0, 0, dp(8)) })

    private fun button(label: String, filled: Boolean, onClick: () -> Unit) = Button(this).apply {
        text = label
        isAllCaps = false
        stateListAnimator = null
        setTextColor(color(if (filled) R.color.on_accent else R.color.accent))
        background = GradientDrawable().apply {
            cornerRadius = dp(24).toFloat()
            if (filled) setColor(color(R.color.accent)) else setColor(color(R.color.accent_soft))
        }
        setPadding(dp(20), 0, dp(20), 0)
        setOnClickListener { onClick() }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val root = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(dp(16), dp(8), dp(16), dp(24)) }
        root.addView(text(26f, bold = true).apply { text = getString(R.string.app_name); setPadding(dp(4), dp(16), 0, dp(4)) })

        // status: coloured dot, Klar/Slukket, switch
        val statusCard = card(root)
        val row = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
        dot = View(this)
        row.addView(dot, LinearLayout.LayoutParams(dp(14), dp(14)).apply { marginEnd = dp(12) })
        title = text(22f, bold = true)
        row.addView(title, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        onOff = Switch(this).apply {
            val states = arrayOf(intArrayOf(android.R.attr.state_checked), intArrayOf())
            thumbTintList = ColorStateList(states, intArrayOf(color(R.color.accent), color(R.color.card)))
            trackTintList = ColorStateList(states, intArrayOf((color(R.color.accent) and 0xFFFFFF) or 0x66000000.toInt(), color(R.color.off)))
            setOnCheckedChangeListener { _, on ->
                val i = Intent(this@MainActivity, CompanionService::class.java)
                if (on) startForegroundService(i) else stopService(i)
                // this@MainActivity: inside apply, a bare "handler" is the Switch's View.getHandler() (null)
                this@MainActivity.handler.postDelayed({ update() }, 300)
            }
        }
        row.addView(onOff)
        statusCard.addView(row)
        status = text(15f, R.color.muted).apply { setPadding(0, dp(8), 0, 0) }
        statusCard.addView(status)
        address = text(13f, R.color.muted).apply { setPadding(0, dp(4), 0, 0) }
        statusCard.addView(address)

        // access: two steps, one button for the next missing one
        accessCard = card(root)
        heading(accessCard, R.string.access_title)
        stepFiles = text(16f); accessCard.addView(stepFiles)
        stepTrash = text(16f).apply { setPadding(0, dp(6), 0, dp(12)) }; accessCard.addView(stepTrash)
        grant = button("", true) { askAccess() }
        accessCard.addView(grant, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, dp(48)))

        // pairing code, only while pairing is open
        codeCard = card(root)
        heading(codeCard, R.string.code_title)
        code = text(44f, R.color.accent, true).apply {
            typeface = Typeface.create(Typeface.MONOSPACE, Typeface.BOLD)
            letterSpacing = 0.1f
            gravity = Gravity.CENTER
        }
        codeCard.addView(code)
        codeCard.addView(text(14f, R.color.muted).apply { text = getString(R.string.code_hint); setPadding(0, dp(8), 0, 0) })

        // paired PCs
        val pcCard = card(root)
        heading(pcCard, R.string.paired_pcs)
        pcs = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        pcCard.addView(pcs)

        // language: Android 13+ keeps a per-app language; older phones follow the phone's language
        if (Build.VERSION.SDK_INT >= 33) {
            val langCard = card(root)
            heading(langCard, R.string.language)
            val current = getSystemService(LocaleManager::class.java).applicationLocales
            val tag = if (current.isEmpty) "" else current[0].language
            val choice = LANGUAGES.indexOfFirst { it.first == tag }.coerceAtLeast(0)
            langCard.addView(button(languageName(choice), false) { pickLanguage(choice) },
                LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, dp(44)))
        }

        // Android 15 draws apps edge to edge: keep the content clear of the status and navigation bars
        val scroll = ScrollView(this).apply { addView(root) }
        scroll.setOnApplyWindowInsetsListener { v, insets ->
            val bars = insets.getInsets(WindowInsets.Type.systemBars())
            v.setPadding(bars.left, bars.top, bars.right, bars.bottom)
            insets
        }
        setContentView(scroll)
        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1)
    }

    private companion object {
        // "" = the phone's language; the others are shown in their own language
        val LANGUAGES = listOf("" to "", "en" to "English", "da" to "Dansk", "de" to "Deutsch",
            "es" to "Español", "fr" to "Français", "it" to "Italiano", "sv" to "Svenska")
    }

    private fun languageName(i: Int) = if (i == 0) getString(R.string.phone_language) else LANGUAGES[i].second

    private fun pickLanguage(current: Int) {
        val names = Array(LANGUAGES.size) { languageName(it) }
        AlertDialog.Builder(this)
            .setTitle(R.string.language)
            .setSingleChoiceItems(names, current) { dialog, i ->
                dialog.dismiss()
                // Android recreates the screen in the new language
                getSystemService(LocaleManager::class.java).applicationLocales =
                    if (i == 0) LocaleList.getEmptyLocaleList() else LocaleList.forLanguageTags(LANGUAGES[i].first)
            }
            .show()
    }

    override fun onResume() {
        super.onResume()
        pairingOpenedFor = null
        onOff.isChecked = CompanionService.server != null
        handler.post(refresh)
    }

    override fun onPause() {
        handler.removeCallbacks(refresh)
        // pairing only while this screen is open: nobody on the network can try codes meanwhile
        CompanionService.server?.tokens?.closePairing()
        super.onPause()
    }

    private fun hasFiles() = Environment.isExternalStorageManager()
    private fun hasTrash() = MediaStore.canManageMedia(this)

    private fun askAccess() {
        val intent = if (!hasFiles())
            Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION, Uri.parse("package:$packageName"))
        else
            Intent(Settings.ACTION_REQUEST_MANAGE_MEDIA, Uri.parse("package:$packageName"))
        startActivity(intent)
    }

    private fun ipAddress(): String? {
        val cm = getSystemService(ConnectivityManager::class.java)
        val lp = cm.getLinkProperties(cm.activeNetwork) ?: return null
        return lp.linkAddresses.map { it.address }.firstOrNull { it is Inet4Address }?.hostAddress
    }

    private fun update() {
        val s = CompanionService.server
        val files = hasFiles()
        val trash = hasTrash()
        val ready = files && trash

        accessCard.visibility = if (ready) View.GONE else View.VISIBLE
        stepFiles.text = (if (files) "✓  " else "1.  ") + getString(R.string.step_files)
        stepFiles.setTextColor(color(if (files) R.color.accent else R.color.text))
        stepTrash.text = (if (trash) "✓  " else "2.  ") + getString(R.string.step_trash)
        stepTrash.setTextColor(color(if (trash) R.color.accent else R.color.text))
        grant.text = getString(if (!files) R.string.grant_files else R.string.grant_trash)

        val on = s != null && ready
        title.text = getString(if (on) R.string.title_on else R.string.title_off)
        dot.background = GradientDrawable().apply {
            shape = GradientDrawable.OVAL; setColor(color(if (on) R.color.accent else R.color.off))
        }
        status.text = getString(when {
            !ready -> R.string.status_no_access
            s == null -> R.string.status_off
            else -> R.string.status_on
        })
        address.text = if (s != null) getString(R.string.address, "${ipAddress() ?: "?"}:${CompanionService.PORT}") else ""
        address.visibility = if (s != null) View.VISIBLE else View.GONE

        // pairing opens once per visit of this screen (closed in onPause; five wrong codes close it too)
        if (s != null && s !== pairingOpenedFor) {
            s.tokens.openPairing(10 * 60 * 1000L)
            pairingOpenedFor = s
        }
        val c = s?.takeIf { it.tokens.pairingOpen() }?.tokens?.pairingCode
        codeCard.visibility = if (c != null) View.VISIBLE else View.GONE
        if (c != null) code.text = if (c.length == 6) c.substring(0, 3) + " " + c.substring(3) else c

        val tokens = s?.tokens ?: CompanionService.tokens(this)
        pcs.removeAllViews()
        val paired = tokens.paired()
        if (paired.isEmpty()) pcs.addView(text(16f, R.color.muted).apply { text = getString(R.string.no_pcs) })
        for ((token, name) in paired) {
            val row = LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL; setPadding(0, dp(4), 0, dp(4))
            }
            row.addView(text(16f).apply { text = name.ifEmpty { "PC" } },
                LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
            row.addView(button(getString(R.string.remove), false) { tokens.remove(token); update() },
                LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, dp(40)))
            pcs.addView(row)
        }
    }
}
