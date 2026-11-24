package dk.tidytag.companion.core

import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.URI
import java.net.http.HttpClient
import java.net.http.HttpRequest
import java.net.http.HttpResponse

class PairingTest {
    @TempDir
    lateinit var root: File
    private lateinit var tokens: TokenStore
    private lateinit var server: CompanionServer
    private val http = HttpClient.newHttpClient()

    @BeforeEach
    fun start() {
        tokens = TokenStore(null)
        tokens.setCode("123456")
        tokens.openPairing(60_000)
        server = CompanionServer(LocalStorage(root), object : MediaHooks {
            override fun changed(rels: List<String>) {}
        }, 0, tokens)
        server.deviceName = "Pixel"
        server.deviceId = "dev-1"
        server.start()
    }

    @AfterEach
    fun stop() = server.stop()

    private fun post(path: String, body: String, token: String? = null): HttpResponse<String> {
        val b = HttpRequest.newBuilder(URI("http://127.0.0.1:${server.listeningPort}$path"))
            .POST(HttpRequest.BodyPublishers.ofString(body))
        if (token != null) b.header("X-TidyTag-Token", token)
        return http.send(b.build(), HttpResponse.BodyHandlers.ofString())
    }

    private fun list(token: String) = http.send(
        HttpRequest.newBuilder(URI("http://127.0.0.1:${server.listeningPort}/v1/list?path=")).header("X-TidyTag-Token", token).build(),
        HttpResponse.BodyHandlers.ofString()).statusCode()

    @Test
    fun pairWithRightCode() {
        val r = post("/v1/pair", """{"code":"123456","pcName":"STUDIO-PC"}""")
        assertEquals(200, r.statusCode())
        val m = Json.parse(r.body())
        assertEquals("dev-1", m["id"])
        assertEquals("Pixel", m["name"])
        assertEquals(200, list(m["token"] as String))
        assertEquals(listOf("STUDIO-PC"), tokens.paired().map { it.second })
    }

    @Test
    fun pairWithWrongCodeRefused() {
        assertEquals(401, post("/v1/pair", """{"code":"000000","pcName":"x"}""").statusCode())
        assertTrue(tokens.paired().isEmpty())
    }

    @Test
    fun codeRotatesAfterPair() {
        post("/v1/pair", """{"code":"123456","pcName":"x"}""")
        assertNotEquals("123456", tokens.pairingCode)
        // refused: the code changed and pairing closed after the successful pairing
        assertTrue(post("/v1/pair", """{"code":"123456","pcName":"y"}""").statusCode() in listOf(401, 403))
    }

    @Test
    fun pairingClosedRefused() {
        tokens.closePairing()
        assertEquals(403, post("/v1/pair", """{"code":"123456","pcName":"x"}""").statusCode())
        assertTrue(tokens.paired().isEmpty())
    }

    @Test
    fun wrongCodeRotatesCode() {
        post("/v1/pair", """{"code":"000000","pcName":"x"}""")
        assertNotEquals("123456", tokens.pairingCode)
        assertEquals(401, post("/v1/pair", """{"code":"123456","pcName":"x"}""").statusCode())
    }

    @Test
    fun closesAfterFiveWrongCodes() {
        repeat(5) { post("/v1/pair", """{"code":"000000","pcName":"x"}""") }
        val code = tokens.pairingCode
        assertEquals(403, post("/v1/pair", """{"code":"$code","pcName":"x"}""").statusCode())
        assertTrue(tokens.paired().isEmpty())
    }

    @Test
    fun removedTokenRefused() {
        val token = Json.parse(post("/v1/pair", """{"code":"123456","pcName":"x"}""").body())["token"] as String
        tokens.remove(token)
        assertEquals(401, list(token))
    }

    @Test
    fun answersBroadcast() {
        val d = Discovery(0) { Json.obj("name" to "Pixel", "port" to 47100, "id" to "dev-1") }
        d.start()
        try {
            DatagramSocket().use { s ->
                s.soTimeout = 3000
                val q = "TIDYTAG?".toByteArray()
                s.send(DatagramPacket(q, q.size, InetAddress.getLoopbackAddress(), d.port))
                val buf = ByteArray(1024)
                val p = DatagramPacket(buf, buf.size)
                s.receive(p)
                val m = Json.parse(String(p.data, 0, p.length))
                assertEquals(47100L, m["port"])
                assertEquals("dev-1", m["id"])
            }
        } finally {
            d.stop()
        }
    }
}
