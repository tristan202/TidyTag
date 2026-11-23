package dk.tidytag.companion.core

import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetSocketAddress
import java.net.SocketException

const val DISCOVERY_PORT = 47101

/** Answers TidyTag's UDP broadcast "TIDYTAG?" with answer() (JSON {name, port, id}). */
class Discovery(private val wantedPort: Int = DISCOVERY_PORT, private val answer: () -> String) {
    private var socket: DatagramSocket? = null
    private var thread: Thread? = null

    /** The bound port (useful when started with 0). */
    val port: Int get() = socket?.localPort ?: wantedPort

    fun start() {
        val s = DatagramSocket(null)
        s.reuseAddress = true
        s.broadcast = true
        s.bind(InetSocketAddress(wantedPort))
        socket = s
        thread = Thread({
            val buf = ByteArray(256)
            while (!s.isClosed) {
                try {
                    val p = DatagramPacket(buf, buf.size)
                    s.receive(p)
                    if (String(p.data, 0, p.length, Charsets.UTF_8) != "TIDYTAG?") continue
                    val a = answer().toByteArray(Charsets.UTF_8)
                    s.send(DatagramPacket(a, a.size, p.socketAddress))
                } catch (e: SocketException) {
                    break // closed by stop()
                }
            }
        }, "TidyTag discovery").apply { isDaemon = true; start() }
    }

    fun stop() {
        socket?.close()
        thread?.join(2000)
        socket = null
    }
}
