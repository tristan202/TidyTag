package dk.tidytag.companion.core

import java.io.File
import java.io.RandomAccessFile
import java.nio.file.Files
import java.nio.file.StandardCopyOption

const val TMP_SUFFIX = ".tidytag-tmp"

/** Plain files under root (shared storage on Android, any folder on the PC). */
open class LocalStorage(root: File) : Storage {
    private val root: File = root.canonicalFile

    fun file(rel: String): File {
        if (rel.contains('\\') || rel.startsWith("/") || rel.contains(':') && rel.length > 1 && rel[1] == ':')
            throw BadPathException("bad path: $rel")
        val f = File(root, rel).canonicalFile
        if (f != root && !f.path.startsWith(root.path + File.separator)) throw BadPathException("outside root: $rel")
        return f
    }

    private fun entry(f: File) = Entry(f.name, f.isDirectory, if (f.isDirectory) 0 else f.length(), f.lastModified())

    override fun list(rel: String): List<Entry> {
        val d = file(rel)
        if (!d.isDirectory) throw NotFoundException(rel)
        // a rewrite that never got its replace: the original is untouched, the half file goes
        d.listFiles { f -> f.isFile && f.name.endsWith(TMP_SUFFIX) }?.forEach { it.delete() }
        return d.listFiles()?.sortedBy { it.name.lowercase() }?.map(::entry) ?: emptyList()
    }

    override fun read(rel: String, offset: Long, len: Int): ByteArray {
        val f = file(rel)
        if (!f.isFile) throw NotFoundException(rel)
        RandomAccessFile(f, "r").use { r ->
            val n = maxOf(0L, minOf(len.toLong(), r.length() - offset)).toInt()
            val b = ByteArray(n)
            r.seek(offset)
            r.readFully(b)
            return b
        }
    }

    override fun write(rel: String, offset: Long, data: ByteArray) {
        val f = file(rel)
        if (!f.isFile) throw NotFoundException(rel)
        RandomAccessFile(f, "rw").use { r ->
            r.seek(offset)
            r.write(data)
            r.fd.sync()
        }
    }

    override fun setLength(rel: String, len: Long) {
        val f = file(rel)
        if (!f.isFile) throw NotFoundException(rel)
        RandomAccessFile(f, "rw").use { r -> r.setLength(len); r.fd.sync() }
    }

    override fun create(rel: String) {
        val f = file(rel)
        if (f.isDirectory) throw ConflictException(rel)
        RandomAccessFile(f, "rw").use { it.setLength(0) }
    }

    override fun rename(from: String, to: String, replace: Boolean) {
        val a = file(from)
        val b = file(to)
        if (!a.exists()) throw NotFoundException(from)
        if (b.exists() && !replace && !a.path.equals(b.path, ignoreCase = true)) throw ConflictException(to)
        b.parentFile?.mkdirs()
        if (replace) Files.move(a.toPath(), b.toPath(), StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
        else Files.move(a.toPath(), b.toPath(), StandardCopyOption.ATOMIC_MOVE)
    }

    override fun mkdir(rel: String) {
        val d = file(rel)
        if (!d.isDirectory && !d.mkdirs()) throw ConflictException(rel)
    }

    override fun rmdir(rel: String) {
        val d = file(rel)
        if (!d.isDirectory) throw NotFoundException(rel)
        if (!(d.list()?.isEmpty() ?: false) || !d.delete()) throw ConflictException("not empty: $rel")
    }

    override fun exists(rel: String): Entry? {
        val f = file(rel)
        return if (f.exists()) entry(f) else null
    }

    override fun copyRange(src: String, srcOffset: Long, len: Long, dst: String, dstOffset: Long) {
        val s = file(src)
        val d = file(dst)
        if (!s.isFile || !d.isFile) throw NotFoundException(if (!s.isFile) src else dst)
        RandomAccessFile(s, "r").use { rs ->
            RandomAccessFile(d, "rw").use { rd ->
                var done = 0L
                while (done < len) {
                    val n = rs.channel.transferTo(srcOffset + done, len - done, rd.channel.position(dstOffset + done))
                    if (n <= 0) break
                    done += n
                }
                // a source that changed in between must not leave a short file behind
                if (done < len) throw ConflictException("copied $done of $len bytes from $src")
                rd.fd.sync()
            }
        }
    }

    /** No trash on a plain disk: refused, so nothing is lost. Android overrides this. */
    override fun trash(rels: List<String>): List<String> = rels

    override fun setModified(rel: String, millis: Long) {
        if (!file(rel).setLastModified(millis)) throw NotFoundException(rel)
    }
}
