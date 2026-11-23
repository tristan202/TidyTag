package dk.tidytag.companion

import android.content.ContentValues
import android.content.Context
import android.media.MediaScannerConnection
import android.os.Environment
import android.provider.MediaStore
import dk.tidytag.companion.core.LocalStorage
import dk.tidytag.companion.core.MediaHooks

/** Shared storage (/storage/emulated/0) as plain files, with MediaStore for the trash. */
class AndroidStorage(private val context: Context) : LocalStorage(Environment.getExternalStorageDirectory()) {

    /**
     * Moves media files to Android's trash (restorable for about 30 days). Non-media files,
     * and files MediaStore will not let us trash, are returned as refused: nothing is deleted.
     */
    override fun trash(rels: List<String>): List<String> {
        val refused = mutableListOf<String>()
        val files = MediaStore.Files.getContentUri(MediaStore.VOLUME_EXTERNAL)
        for (rel in rels) {
            val path = file(rel).path
            val id = context.contentResolver.query(files, arrayOf(MediaStore.MediaColumns._ID),
                "${MediaStore.MediaColumns.DATA} = ?", arrayOf(path), null)?.use { c ->
                if (c.moveToFirst()) c.getLong(0) else null
            }
            if (id == null) {
                refused += rel
                continue
            }
            val values = ContentValues().apply { put(MediaStore.MediaColumns.IS_TRASHED, 1) }
            val ok = try {
                context.contentResolver.update(android.content.ContentUris.withAppendedId(files, id), values, null, null) > 0
            } catch (e: SecurityException) {
                false
            }
            if (!ok) refused += rel
        }
        return refused
    }
}

/** Asks MediaStore to read changed files again, so music apps show the new tags. */
class MediaScanHooks(private val context: Context, private val storage: AndroidStorage) : MediaHooks {
    override fun changed(rels: List<String>) {
        val paths = rels.map { storage.file(it).path }.toTypedArray()
        MediaScannerConnection.scanFile(context, paths, null, null)
    }
}
