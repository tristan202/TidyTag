package dk.tidytag.companion.core

/** A file or folder in a listing. mtime in milliseconds since 1970. */
data class Entry(val name: String, val dir: Boolean, val size: Long, val mtime: Long)

class BadPathException(msg: String) : Exception(msg)
class ConflictException(msg: String) : Exception(msg)
class NotFoundException(msg: String) : Exception(msg)

/**
 * The files the server serves. Paths are relative to the storage root, '/'-separated;
 * implementations refuse anything that would leave the root (BadPathException).
 * This is the replaceable part: Android may later use MediaStore instead of plain files.
 */
interface Storage {
    fun list(rel: String): List<Entry>
    fun read(rel: String, offset: Long, len: Int): ByteArray
    fun write(rel: String, offset: Long, data: ByteArray)
    fun setLength(rel: String, len: Long)
    fun create(rel: String)
    fun rename(from: String, to: String, replace: Boolean)
    fun mkdir(rel: String)
    /** Removes an empty folder; a folder with anything in it is a ConflictException. */
    fun rmdir(rel: String)
    fun exists(rel: String): Entry?
    fun copyRange(src: String, srcOffset: Long, len: Long, dst: String, dstOffset: Long)
    /** Moves files to the system trash; returns the ones it could not take. */
    fun trash(rels: List<String>): List<String>
    fun setModified(rel: String, millis: Long)
}

/** Told about every changed path (Android rescans them in MediaStore). */
interface MediaHooks {
    fun changed(rels: List<String>)
}
