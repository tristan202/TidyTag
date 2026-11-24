package dk.tidytag.companion.core

import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertArrayEquals
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File
import java.net.URI
import java.net.URLEncoder
import java.net.http.HttpClient
import java.net.http.HttpRequest
import java.net.http.HttpResponse

class ServerTest {
    @TempDir
    lateinit var root: File

    private lateinit var server: CompanionServer
    private val changed = mutableListOf<String>()
    private val http = HttpClient.newHttpClient()
    private val token = "secret"

    @BeforeEach
    fun start() {
        val tokens = TokenStore(null)
        tokens.add(token)
        server = CompanionServer(LocalStorage(root), object : MediaHooks {
            override fun changed(rels: List<String>) { changed += rels }
        }, 0, tokens)
        server.start()
    }

    @AfterEach
    fun stop() = server.stop()

    private fun q(s: String) = URLEncoder.encode(s, Charsets.UTF_8)

    private fun call(method: String, pathAndQuery: String, body: ByteArray = ByteArray(0), tok: String? = token): HttpResponse<ByteArray> {
        val b = HttpRequest.newBuilder(URI("http://127.0.0.1:${server.listeningPort}$pathAndQuery"))
        if (tok != null) b.header("X-TidyTag-Token", tok)
        if (method == "POST") b.POST(HttpRequest.BodyPublishers.ofByteArray(body)) else b.GET()
        return http.send(b.build(), HttpResponse.BodyHandlers.ofByteArray())
    }

    @Test
    fun listShowsFilesAndFolders() {
        File(root, "Music/Rock").mkdirs()
        File(root, "Music/a.mp3").writeBytes(ByteArray(10))
        val r = call("GET", "/v1/list?path=${q("Music")}")
        assertEquals(200, r.statusCode())
        val text = String(r.body())
        assertTrue(text.contains("\"name\":\"Rock\"") && text.contains("\"dir\":true"), text)
        assertTrue(text.contains("\"name\":\"a.mp3\"") && text.contains("\"size\":10"), text)
    }

    @Test
    fun readRangeAcrossEnd() {
        File(root, "a.bin").writeBytes(ByteArray(100) { it.toByte() })
        val r = call("GET", "/v1/read?path=a.bin&offset=90&len=50")
        assertEquals(200, r.statusCode())
        assertArrayEquals(ByteArray(10) { (90 + it).toByte() }, r.body())
    }

    @Test
    fun writeIsApplied() {
        File(root, "a.bin").writeBytes(ByteArray(20))
        assertEquals(200, call("POST", "/v1/write?path=a.bin&offset=5", byteArrayOf(1, 2, 3)).statusCode())
        val b = File(root, "a.bin").readBytes()
        assertEquals(20, b.size)
        assertArrayEquals(byteArrayOf(0, 1, 2, 3, 0), b.copyOfRange(4, 9))
    }

    @Test
    fun renameReplace() {
        File(root, "a.mp3.tidytag-tmp").writeText("new")
        File(root, "a.mp3").writeText("old")
        assertEquals(200, call("POST", "/v1/rename?from=${q("a.mp3.tidytag-tmp")}&to=a.mp3&replace=1").statusCode())
        assertEquals("new", File(root, "a.mp3").readText())
        assertFalse(File(root, "a.mp3.tidytag-tmp").exists())
        // without replace an existing target is a conflict
        File(root, "b.mp3").writeText("b")
        assertEquals(409, call("POST", "/v1/rename?from=a.mp3&to=b.mp3&replace=0").statusCode())
    }

    @Test
    fun copyRangeOnPhone() {
        File(root, "src.bin").writeBytes(ByteArray(1000) { (it % 251).toByte() })
        File(root, "dst.bin").writeBytes(ByteArray(10) { 7 })
        assertEquals(200, call("POST", "/v1/copy?src=src.bin&srcOffset=100&len=500&dst=dst.bin&dstOffset=10").statusCode())
        val d = File(root, "dst.bin").readBytes()
        assertEquals(510, d.size)
        assertArrayEquals(File(root, "src.bin").readBytes().copyOfRange(100, 600), d.copyOfRange(10, 510))
    }

    @Test
    fun refusesDotDotAndAbsolute() {
        File(root.parentFile, "outside.txt").writeText("x")
        for (p in listOf("../outside.txt", "/etc/passwd", "a/../../outside.txt", "C:\\Windows\\win.ini"))
            assertEquals(400, call("GET", "/v1/read?path=${q(p)}&offset=0&len=1").statusCode(), p)
    }

    @Test
    fun refusesWithoutToken() {
        assertEquals(401, call("GET", "/v1/list?path=", tok = null).statusCode())
        assertEquals(401, call("GET", "/v1/list?path=", tok = "wrong").statusCode())
    }

    @Test
    fun rmdirOnlyEmpty() {
        File(root, "Tom").mkdir()
        File(root, "Fuld").mkdir()
        File(root, "Fuld/a.mp3").writeText("x")
        assertEquals(200, call("POST", "/v1/rmdir?path=Tom").statusCode())
        assertFalse(File(root, "Tom").exists())
        assertEquals(409, call("POST", "/v1/rmdir?path=Fuld").statusCode())
        assertTrue(File(root, "Fuld/a.mp3").exists())
    }

    @Test
    fun hugeBodyRefusedAndServerSurvives() {
        java.net.Socket("127.0.0.1", server.listeningPort).use { s ->
            s.getOutputStream().write("POST /v1/pair HTTP/1.1\r\nHost: x\r\nContent-Length: 2000000000\r\n\r\n".toByteArray())
            s.getOutputStream().flush()
            val head = s.getInputStream().bufferedReader().readLine()
            assertTrue(head.contains("413"), head)
        }
        assertEquals(200, call("GET", "/v1/list?path=").statusCode())
    }

    @Test
    fun shortCopyRefused() {
        File(root, "src.bin").writeBytes(ByteArray(100))
        File(root, "dst.bin").writeBytes(ByteArray(0))
        assertTrue(call("POST", "/v1/copy?src=src.bin&srcOffset=0&len=500&dst=dst.bin&dstOffset=0").statusCode() >= 400)
    }

    @Test
    fun staleTmpRemovedOnList() {
        File(root, "a.mp3.tidytag-tmp").writeText("half")
        call("GET", "/v1/list?path=")
        assertFalse(File(root, "a.mp3.tidytag-tmp").exists())
    }

    @Test
    fun hooksCalledOnChange() {
        File(root, "a.mp3").writeBytes(ByteArray(10))
        call("POST", "/v1/write?path=a.mp3&offset=0", byteArrayOf(1))
        assertEquals(listOf("a.mp3"), changed)
        changed.clear()
        call("POST", "/v1/rename?from=a.mp3&to=${q("Rock/b.mp3")}&replace=0".also { File(root, "Rock").mkdir() })
        assertEquals(listOf("a.mp3", "Rock/b.mp3"), changed)
    }
}
