package com.shahidy.iikb.voice

import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest

/**
 * A model's files and where they come from, each pinned to its SHA-256, so a download is the file the model was
 * tested with or nothing. A download picks up where the last left off (`.part` beside each file, with an HTTP range),
 * so an ended keyboard, a lost network or a phone that died loses no more than the moment it stopped.
 */
class ModelFiles(val folder: File, private val files: List<Remote>) {
    class Remote(val name: String, val url: String, val size: Long, val sha256: String)

    val total = files.sumOf { it.size }
    val present get() = files.all { File(folder, it.name).length() == it.size }

    fun file(name: String) = File(folder, name)

    /** Downloads what's missing, reporting the bytes there so far out of [total]; throws when it can't finish. */
    fun download(progress: (Long) -> Unit) {
        folder.mkdirs()
        var done = files.filter { File(folder, it.name).length() == it.size }.sumOf { it.size }
        for (remote in files) {
            val target = File(folder, remote.name)
            if (target.length() == remote.size) continue
            val part = File(folder, remote.name + ".part")
            if (part.length() > remote.size) part.delete()
            val before = done
            fetch(remote, part) { progress(before + it) }
            if (sha256(part) != remote.sha256) {
                part.delete()
                throw IOException("${remote.name} didn't download whole")
            }
            if (!part.renameTo(target)) throw IOException("Couldn't save ${remote.name}")
            done += remote.size
            progress(done)
        }
    }

    private fun fetch(remote: Remote, part: File, progress: (Long) -> Unit) {
        val from = part.length()
        val connection = URL(remote.url).openConnection() as HttpURLConnection
        connection.connectTimeout = 15_000
        connection.readTimeout = 30_000
        if (from > 0) connection.setRequestProperty("Range", "bytes=$from-")
        try {
            val code = connection.responseCode
            val append = code == HttpURLConnection.HTTP_PARTIAL
            if (code != HttpURLConnection.HTTP_OK && !append) throw IOException("The download server said $code")
            var written = if (append) from else 0L
            connection.inputStream.use { input ->
                FileOutputStream(part, append).use { output ->
                    val buffer = ByteArray(1 shl 16)
                    var reported = written
                    while (true) {
                        val read = input.read(buffer)
                        if (read < 0) break
                        output.write(buffer, 0, read)
                        written += read
                        if (written - reported >= 1 shl 20) {
                            reported = written
                            progress(written)
                        }
                    }
                }
            }
        } finally {
            connection.disconnect()
        }
    }

    private fun sha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(1 shl 16)
            while (true) {
                val read = input.read(buffer)
                if (read < 0) break
                digest.update(buffer, 0, read)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }
}
