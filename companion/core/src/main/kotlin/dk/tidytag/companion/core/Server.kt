package dk.tidytag.companion.core

import fi.iki.elonen.NanoHTTPD
import java.io.ByteArrayInputStream
import java.util.Base64

/** The HTTP API (docs/phone-protocol.md). Every call except /v1/pair needs X-TidyTag-Token. */
class CompanionServer(
    private val storage: Storage,
    private val hooks: MediaHooks,
    port: Int,
    val tokens: TokenStore,
) : NanoHTTPD(port) {

    /** Set by the app to name itself in pairing answers; id is a stable random device id. */
    var deviceName: String = "Phone"
    var deviceId: String = "test"
    /** Called after a successful pairing (the app shows the new PC). */
    var onPaired: ((String) -> Unit)? = null

    override fun serve(session: IHTTPSession): Response = try {
        handle(session)
    } catch (e: BadPathException) {
        error(Response.Status.BAD_REQUEST, e.message)
    } catch (e: NotFoundException) {
        error(Response.Status.NOT_FOUND, e.message)
    } catch (e: ConflictException) {
        error(Response.Status.CONFLICT, e.message)
    } catch (e: IllegalArgumentException) {
        error(Response.Status.BAD_REQUEST, e.message)
    } catch (e: Exception) {
        error(Response.Status.INTERNAL_ERROR, e.toString())
    }

    private fun error(status: Response.Status, msg: String?) =
        newFixedLengthResponse(status, "application/json", Json.obj("error" to (msg ?: status.description)))

    private fun ok(json: String = "{}") = newFixedLengthResponse(Response.Status.OK, "application/json", json)

    private fun body(s: IHTTPSession): ByteArray {
        val len = s.headers["content-length"]?.toLongOrNull() ?: 0L
        val b = ByteArray(len.toInt())
        var n = 0
        while (n < b.size) {
            val r = s.inputStream.read(b, n, b.size - n)
            if (r < 0) break
            n += r
        }
        require(n == b.size) { "short body" }
        return b
    }

    private fun handle(s: IHTTPSession): Response {
        val p = s.parameters.mapValues { it.value.firstOrNull() ?: "" }
        fun arg(name: String) = p[name] ?: throw IllegalArgumentException("missing $name")
        fun long(name: String) = arg(name).toLongOrNull() ?: throw IllegalArgumentException("bad $name")
        val post = s.method == Method.POST

        if (s.uri == "/v1/pair" && post) return pair(String(body(s), Charsets.UTF_8))
        if (!tokens.isValid(s.headers["x-tidytag-token"])) return error(Response.Status.UNAUTHORIZED, "not paired")

        when (s.uri) {
            "/v1/list" -> return ok(Json.arr(storage.list(arg("path")).map(::entryJson)))
            "/v1/read" -> {
                val data = storage.read(arg("path"), long("offset"), long("len").toInt())
                return newFixedLengthResponse(Response.Status.OK, "application/octet-stream",
                    ByteArrayInputStream(data), data.size.toLong())
            }
            "/v1/stat" -> return storage.exists(arg("path"))?.let { ok(entryJson(it)) }
                ?: error(Response.Status.NOT_FOUND, arg("path"))
        }
        if (!post) return error(Response.Status.METHOD_NOT_ALLOWED, s.uri)
        when (s.uri) {
            "/v1/peek" -> return peek(String(body(s), Charsets.UTF_8))
            "/v1/write" -> { storage.write(arg("path"), long("offset"), body(s)); changed(arg("path")) }
            "/v1/truncate" -> { storage.setLength(arg("path"), long("len")); changed(arg("path")) }
            "/v1/create" -> storage.create(arg("path"))
            "/v1/rename" -> { storage.rename(arg("from"), arg("to"), arg("replace") == "1"); changed(arg("from"), arg("to")) }
            "/v1/mkdir" -> storage.mkdir(arg("path"))
            "/v1/copy" -> {
                storage.copyRange(arg("src"), long("srcOffset"), long("len"), arg("dst"), long("dstOffset"))
                changed(arg("dst"))
            }
            "/v1/trash" -> {
                @Suppress("UNCHECKED_CAST")
                val paths = Json.parse(String(body(s), Charsets.UTF_8))["paths"] as? List<String> ?: emptyList()
                val refused = storage.trash(paths)
                hooks.changed(paths - refused.toSet())
                return ok(Json.obj("refused" to RawJson(Json.arr(refused.map(Json::str)))))
            }
            "/v1/mtime" -> { storage.setModified(arg("path"), long("ms")); changed(arg("path")) }
            else -> return error(Response.Status.NOT_FOUND, s.uri)
        }
        return ok()
    }

    // temporary files are TidyTag's own; the media library only cares about the real ones
    private fun changed(vararg rels: String) {
        val real = rels.filterNot { it.endsWith(TMP_SUFFIX) }
        if (real.isNotEmpty()) hooks.changed(real)
    }

    private fun entryJson(e: Entry) = Json.obj("name" to e.name, "dir" to e.dir, "size" to e.size, "mtime" to e.mtime)

    private fun peek(text: String): Response {
        val m = Json.parse(text)
        @Suppress("UNCHECKED_CAST")
        val paths = m["paths"] as? List<String> ?: emptyList()
        val head = (m["head"] as? Long ?: 0L).toInt()
        val tail = (m["tail"] as? Long ?: 0L).toInt()
        val b64 = Base64.getEncoder()
        val out = paths.mapNotNull { path ->
            val e = storage.exists(path) ?: return@mapNotNull null
            if (e.dir) return@mapNotNull null
            val h = storage.read(path, 0, minOf(head.toLong(), e.size).toInt())
            val tStart = maxOf(h.size.toLong(), e.size - tail)
            val t = if (tStart < e.size) storage.read(path, tStart, (e.size - tStart).toInt()) else ByteArray(0)
            Json.obj("path" to path, "size" to e.size, "mtime" to e.mtime,
                "head" to b64.encodeToString(h), "tail" to b64.encodeToString(t))
        }
        return ok(Json.arr(out))
    }

    private fun pair(text: String): Response {
        val m = Json.parse(text)
        if (m["code"] != tokens.pairingCode) return error(Response.Status.UNAUTHORIZED, "wrong code")
        val token = tokens.newToken()
        val pc = m["pcName"] as? String ?: ""
        tokens.add(token, pc)
        tokens.rotateCode()
        onPaired?.invoke(pc)
        return ok(Json.obj("token" to token, "id" to deviceId, "name" to deviceName))
    }
}
