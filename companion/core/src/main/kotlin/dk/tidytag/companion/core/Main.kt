package dk.tidytag.companion.core

import java.io.File

/** Desktop runner for TidyTag's tests: --root <dir> --port <n> --token <t> [--code <6 digits>] [--name <n>] */
fun main(args: Array<String>) {
    val opt = args.toList().chunked(2).filter { it.size == 2 }.associate { it[0].removePrefix("--") to it[1] }
    val root = File(opt["root"] ?: error("--root missing"))
    val tokens = TokenStore(null)
    opt["token"]?.let { tokens.add(it, "test") }
    opt["code"]?.let { tokens.setCode(it); tokens.openPairing(Long.MAX_VALUE / 2) }
    val server = CompanionServer(LocalStorage(root), object : MediaHooks {
        override fun changed(rels: List<String>) = println("changed: $rels")
    }, opt["port"]?.toInt() ?: 47100, tokens)
    server.deviceName = opt["name"] ?: "Test"
    server.deviceId = opt["id"] ?: "test-device"
    server.start(fi.iki.elonen.NanoHTTPD.SOCKET_READ_TIMEOUT, false)
    // tests run several jars at once: --discovery 0 turns the UDP answer off
    val discoveryPort = opt["discovery"]?.toInt() ?: DISCOVERY_PORT
    if (discoveryPort != 0)
        Discovery(discoveryPort) {
            Json.obj("name" to server.deviceName, "port" to server.listeningPort, "id" to server.deviceId)
        }.start()
    println("listening on ${server.listeningPort}")
    Thread.currentThread().join()
}
