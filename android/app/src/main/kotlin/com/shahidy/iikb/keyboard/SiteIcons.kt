package com.shahidy.iikb.keyboard

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import androidx.compose.foundation.Image
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalContext
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Each copied link's site icon, as iOS's `LinkIcons` fetches it: from the site itself, its `apple-touch-icon.png`, else
 * the largest icon its home page links, else its `favicon.ico`, so only the site's name leaves the phone, never the
 * link; a site without any is asked again a week later. Each is kept as its tile, the icon on a white rounded square
 * with a hairline edge, in the cache the keyboard and the app share.
 */
object SiteIcons {
    private val memory = ConcurrentHashMap<String, Bitmap>()
    private val loading = ConcurrentHashMap<String, CompletableDeferred<Bitmap?>>()

    fun cached(site: String): Bitmap? = memory[site]

    suspend fun icon(context: Context, site: String): Bitmap? {
        memory[site]?.let { return it }
        val mine = CompletableDeferred<Bitmap?>()
        val task = loading.putIfAbsent(site, mine) ?: mine
        if (task === mine) {
            val image = runCatching { withContext(Dispatchers.IO) { load(File(context.cacheDir, "site-icons"), site) } }.getOrNull()
            image?.let { memory[site] = it }
            loading.remove(site)
            mine.complete(image)
        }
        return task.await()
    }

    private fun load(folder: File, site: String): Bitmap? {
        val file = File(folder, "$site.png")
        val none = File(folder, "$site.none")
        BitmapFactory.decodeFile(file.path)?.let { return it }
        if (none.exists() && System.currentTimeMillis() - none.lastModified() < 7 * 24 * 3600 * 1000L) return null
        folder.mkdirs()
        var answered = false
        fun fetch(url: URL): ByteArray? {
            val connection = runCatching { url.openConnection() as HttpURLConnection }.getOrNull() ?: return null
            return try {
                connection.connectTimeout = 8000
                connection.readTimeout = 8000
                connection.setRequestProperty("User-Agent", "iikb")
                val code = connection.responseCode
                answered = true
                if (code == 200) connection.inputStream.use { it.readBytes() } else null
            } catch (_: Exception) {
                null
            } finally {
                connection.disconnect()
            }
        }
        fun tileOf(url: URL) = fetch(url)?.let(::tile)
        var image = tileOf(URL("https://$site/apple-touch-icon.png"))
        if (image == null) {
            val page = URL("https://$site/")
            fetch(page)?.let { html ->
                for (url in linkedIcons(String(html, 0, minOf(html.size, 500_000)), page).take(2)) {
                    image = tileOf(url) ?: continue
                    break
                }
            }
        }
        if (image == null) image = tileOf(URL("https://$site/favicon.ico"))
        image?.let { tile ->
            file.outputStream().use { tile.compress(Bitmap.CompressFormat.PNG, 100, it) }
            none.delete()
            return tile
        }
        if (answered) none.writeBytes(ByteArray(0))
        return null
    }

    /** The icons a home page's `<link rel="…icon…">` tags name, largest first, leaving out SVG. */
    fun linkedIcons(html: String, page: URL): List<URL> =
        Regex("<link\\b[^>]*>", RegexOption.IGNORE_CASE).findAll(html).mapNotNull { match ->
            val tag = match.value
            val rel = Regex("rel\\s*=\\s*[\"']([^\"']*)[\"']", RegexOption.IGNORE_CASE).find(tag)?.groupValues?.get(1)?.lowercase() ?: ""
            if (!rel.contains("icon") || rel.contains("mask")) return@mapNotNull null
            val href = Regex("href\\s*=\\s*[\"']([^\"']*)[\"']", RegexOption.IGNORE_CASE).find(tag)?.groupValues?.get(1)
                ?.replace("&amp;", "&") ?: return@mapNotNull null
            if (href.lowercase().endsWith(".svg")) return@mapNotNull null
            val url = runCatching { URL(page, href) }.getOrNull() ?: return@mapNotNull null
            val size = Regex("sizes\\s*=\\s*[\"'](\\d+)", RegexOption.IGNORE_CASE).find(tag)?.groupValues?.get(1)?.toIntOrNull()
                ?: if (rel.contains("apple")) 180 else 32
            size to url
        }.sortedByDescending { it.first }.map { it.second }.toList()

    /** The icon on a white rounded square, 180 px a side; one under 120 px sits inset, as iOS's tile has it. */
    private fun tile(data: ByteArray): Bitmap? {
        val icon = BitmapFactory.decodeByteArray(data, 0, data.size) ?: return null
        if (icon.width < 16) return null
        val side = 180f
        val tile = Bitmap.createBitmap(side.toInt(), side.toInt(), Bitmap.Config.ARGB_8888)
        val canvas = Canvas(tile)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
        val corner = side * 0.22f
        val bounds = RectF(0f, 0f, side, side)
        canvas.save()
        canvas.clipPath(android.graphics.Path().apply { addRoundRect(bounds, corner, corner, android.graphics.Path.Direction.CW) })
        paint.color = android.graphics.Color.WHITE
        canvas.drawRect(bounds, paint)
        val inset = if (icon.width >= 120) 0f else side * 0.14f
        canvas.drawBitmap(icon, null, RectF(inset, inset, side - inset, side - inset), paint)
        canvas.restore()
        val edge = side / 60f * 2.5f
        paint.style = Paint.Style.STROKE
        paint.strokeWidth = edge
        paint.color = android.graphics.Color.argb(31, 0, 0, 0)
        val inner = RectF(edge / 2, edge / 2, side - edge / 2, side - edge / 2)
        canvas.drawRoundRect(inner, corner - edge / 2, corner - edge / 2, paint)
        return tile
    }
}

/** A site's icon tile, filling its box, or the globe in `fallback` until one's found or where there's none. */
@Composable
fun SiteIcon(site: String?, fallback: Color = Color(0xFF8E8E93)) {
    val context = LocalContext.current
    val icon by produceState(site?.let(SiteIcons::cached), site) { value = site?.let { SiteIcons.icon(context, it) } }
    val shown = icon ?: return Canvas(Modifier.fillMaxSize()) {
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = fallback.toArgb() }
        drawIntoCanvas { Glyphs.draw(it.nativeCanvas, "globe", center.x, center.y, size.minDimension * 0.8f, paint) }
    }
    Image(shown.asImageBitmap(), site, Modifier.fillMaxSize())
}
