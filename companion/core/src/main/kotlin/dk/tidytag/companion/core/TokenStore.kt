package dk.tidytag.companion.core

import java.io.File
import java.security.SecureRandom

/** Paired PCs (token = their name) and the current pairing code; kept in file when given. */
class TokenStore(private val file: File?) {
    private val random = SecureRandom()
    private val tokens = linkedMapOf<String, String>() // token -> PC name
    var pairingCode: String = newCode()
        private set

    init {
        file?.takeIf { it.isFile }?.readLines()?.forEach { line ->
            val t = line.split('\t', limit = 2)
            if (t.size == 2) tokens[t[0]] = t[1]
        }
    }

    @Synchronized fun isValid(token: String?): Boolean = token != null && tokens.containsKey(token)

    @Synchronized fun add(token: String, pcName: String = "") {
        tokens[token] = pcName
        save()
    }

    @Synchronized fun remove(token: String) {
        tokens.remove(token)
        save()
    }

    @Synchronized fun paired(): List<Pair<String, String>> = tokens.map { it.key to it.value }

    @Synchronized fun rotateCode() { pairingCode = newCode() }

    /** For tests and the desktop runner. */
    @Synchronized fun setCode(code: String) { pairingCode = code }

    fun newToken(): String = ByteArray(24).also(random::nextBytes).joinToString("") { "%02x".format(it) }

    private fun newCode() = "%06d".format(random.nextInt(1_000_000))

    private fun save() {
        file?.writeText(tokens.entries.joinToString("") { "${it.key}\t${it.value}\n" })
    }
}
