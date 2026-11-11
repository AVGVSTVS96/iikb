package com.shahidy.iikb.keyboard

import android.Manifest
import android.content.ContentUris
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.ImageDecoder
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil3.compose.AsyncImage
import coil3.request.ImageRequest
import com.shahidy.iikb.Text
import kotlinx.serialization.Serializable
import java.io.File
import java.util.UUID
import java.util.concurrent.Executors
import kotlin.math.floor
import kotlin.math.roundToInt

/**
 * Photos to send from a chat, as iOS's `ChatPhotos`: your newest photos as a grid in the keys' place, as Telegram shows
 * them under its message box. A tap attaches a photo, numbered in the order picked, up to ten, and a second tap takes
 * it off, as the ✕ on it in the box does; Paste in the box attaches copied photos too. Each goes as a JPEG of at most
 * 2048 pixels on its longer side, kept a day after it's picked, so a sent one still shows in its chat until the
 * extension's copy comes. The library is read with the access iikb's app asks for, which the keyboard shares.
 * Compose state.
 */
class ChatPhotos(private val context: Context) {
    @Serializable
    data class Photo(val name: String, val width: Int, val height: Int) {
        fun file(context: Context) = File(folder(context), name)
    }

    private val shown = mutableStateOf(emptyList<Photo>())
    /** The photos attached, in the order picked, as each is ready to send. */
    var attached: List<Photo>
        get() = shown.value
        private set(photos) {
            shown.value = photos
            changed()
        }
    /** The photos attached changed. */
    var changed: () -> Unit = {}
    /** Your newest photos' ids, newest first, as the grid last read them; null without access to them. */
    var library by mutableStateOf<List<Long>?>(emptyList())
        private set
    /** The photos picked in the grid, by id, each with its copy once it's ready. */
    private var picked by mutableStateOf(emptyList<Pair<Long, Photo?>>())
    /** One photo made ready at a time, so only one is in memory. */
    private val work = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    /** A picked photo's number, from 1, in the order picked. */
    fun number(id: Long) = picked.indexOfFirst { it.first == id }.takeIf { it >= 0 }?.plus(1)

    /** Ten are picked in the grid, so the rest dim. */
    val full get() = picked.size >= MOST

    /** Reads the library again as the grid comes up, so a photo just taken is first. */
    fun show() {
        if (!allowed(context)) {
            library = null
            return
        }
        work.execute {
            val ids = runCatching {
                context.contentResolver.query(
                    MediaStore.Images.Media.EXTERNAL_CONTENT_URI, arrayOf(MediaStore.Images.Media._ID), null, null,
                    "${MediaStore.Images.Media.DATE_ADDED} DESC",
                )?.use { rows -> buildList { while (size < NEWEST && rows.moveToNext()) add(rows.getLong(0)) } }
            }.getOrNull().orEmpty()
            main.post { library = ids }
        }
    }

    fun toggle(id: Long) {
        val at = picked.indexOfFirst { it.first == id }
        if (at >= 0) {
            val photo = picked[at].second
            picked = picked.filterIndexed { index, _ -> index != at }
            if (photo != null) attached = attached - photo
            return
        }
        if (attached.size + picked.count { it.second == null } >= MOST) return
        picked = picked + (id to null)
        read(uri(id)) { photo ->
            val index = picked.indexOfFirst { it.first == id }
            if (index < 0) return@read
            if (photo == null) {
                picked = picked.filterIndexed { place, _ -> place != index }
                return@read
            }
            picked = picked.mapIndexed { place, pick -> if (place == index) id to photo else pick }
            attach(photo)
        }
    }

    fun remove(index: Int) {
        val photo = attached.getOrNull(index) ?: return
        attached = attached - photo
        picked = picked.filterNot { it.second == photo }
    }

    /** What was sent comes off the box and out of the grid. */
    fun clear() {
        attached = emptyList()
        picked = emptyList()
    }

    /** The photos stay attached; the grid starts again with nothing ticked. */
    fun dropGrid() {
        picked = emptyList()
    }

    /** Photos pasted into the box, after those attached, up to ten in all. */
    fun paste(uris: List<Uri>) {
        uris.take(MOST - attached.size).forEach { uri -> read(uri) { photo -> photo?.let(::attach) } }
    }

    private fun attach(photo: Photo) {
        if (attached.size < MOST) attached = attached + photo
    }

    private fun read(uri: Uri, done: (Photo?) -> Unit) = work.execute {
        val photo = shrink(uri)
        main.post { done(photo) }
    }

    /**
     * The photo at most `SIDE` pixels on its longer side, as a JPEG kept to send: decoded at the largest power-of-two
     * step down that keeps it that big, so a large photo is never in memory whole, then scaled the rest of the way.
     */
    private fun shrink(uri: Uri): Photo? = runCatching {
        val decoded = ImageDecoder.decodeBitmap(ImageDecoder.createSource(context.contentResolver, uri)) { decoder, info, _ ->
            var step = 1
            while (maxOf(info.size.width, info.size.height) / (step * 2) >= SIDE) step *= 2
            decoder.setTargetSampleSize(step)
            decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
        }
        val scale = minOf(1f, SIDE.toFloat() / maxOf(decoded.width, decoded.height))
        val bitmap = if (scale < 1f) {
            Bitmap.createScaledBitmap(decoded, (decoded.width * scale).roundToInt(), (decoded.height * scale).roundToInt(), true)
                .also { decoded.recycle() }
        } else decoded
        val photo = Photo(UUID.randomUUID().toString() + ".jpg", bitmap.width, bitmap.height)
        folder(context).mkdirs()
        photo.file(context).outputStream().use { bitmap.compress(Bitmap.CompressFormat.JPEG, QUALITY, it) }
        bitmap.recycle()
        photo
    }.getOrNull()

    /** Drops the photos picked over a day ago that aren't attached or `kept` by a message still to send. */
    fun prune(kept: Set<String>) = work.execute {
        val old = System.currentTimeMillis() - DAY
        val held = kept + attached.map { it.name }
        folder(context).listFiles()?.forEach { if (it.name !in held && it.lastModified() < old) it.delete() }
    }

    fun close() = work.shutdownNow()

    companion object {
        /** Telegram's album holds ten. */
        const val MOST = 10
        /** The longer side a photo is sent at, as Telegram sends photos. */
        const val SIDE = 2048
        private const val QUALITY = 85
        /** The newest this many; a keyboard is for the photo you just took. */
        private const val NEWEST = 500
        private const val DAY = 86_400_000L

        /** Kept out of Auto Backup: they're only on their way. */
        fun folder(context: Context) = File(context.noBackupFilesDir, "chat-photos")

        fun uri(id: Long): Uri = ContentUris.withAppendedId(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, id)

        /** The permissions that read your photos on this Android: all of them, or those you picked (14 on). */
        val permissions = when {
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE ->
                arrayOf(Manifest.permission.READ_MEDIA_IMAGES, Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED)
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU -> arrayOf(Manifest.permission.READ_MEDIA_IMAGES)
            else -> arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE)
        }

        fun allowed(context: Context) = permissions.any { context.checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED }
    }
}

/**
 * Your newest photos, about 110 across each and at least three to a row, with 2 between, each drawn at the size it's
 * shown so the grid costs the keyboard little memory, a picked one dimmed under its number. Without access to them it
 * says so, and Allow Photos opens iikb to ask.
 */
@Composable
fun PhotoGrid(photos: ChatPhotos) {
    val look = LocalColors.current
    val actions = LocalActions.current
    val library = photos.library
    if (library == null) {
        val notice = buildAnnotatedString {
            append("Photos need their own permission to show here.\n")
            withStyle(SpanStyle(color = look.accent, fontWeight = FontWeight.SemiBold)) { append("Allow Photos") }
        }
        return Box(
            Modifier.fillMaxSize().padding(horizontal = 24.dp)
                .clickable(remember { MutableInteractionSource() }, indication = null, onClick = actions::allowPhotos),
            contentAlignment = Alignment.Center,
        ) { Text(notice, color = look.secondary, fontSize = 15.sp, textAlign = TextAlign.Center) }
    }
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val across = maxOf(3, (maxWidth.value / 110).roundToInt())
        val side = floor((maxWidth.value - GRID_GAP * (across - 1)) / across)
        LazyVerticalGrid(
            GridCells.Fixed(across), Modifier.fillMaxSize(),
            horizontalArrangement = Arrangement.spacedBy(GRID_GAP.dp), verticalArrangement = Arrangement.spacedBy(GRID_GAP.dp),
        ) {
            items(library, key = { it }) { id -> PhotoCell(id, side, photos.number(id), photos.full) { photos.toggle(id) } }
        }
    }
}

/**
 * A photo in the grid, and its number once it's picked, in a circle ringed in white at its corner as Telegram's; with
 * ten picked (`full`), the rest dim and lose their ring.
 */
@Composable
private fun PhotoCell(id: Long, side: Float, number: Int?, full: Boolean, tap: () -> Unit) {
    val look = LocalColors.current
    val context = LocalContext.current
    val pixels = with(LocalDensity.current) { side.dp.roundToPx() }
    val request = remember(id, pixels) { ImageRequest.Builder(context).data(ChatPhotos.uri(id)).size(pixels).build() }
    Box(
        Modifier.aspectRatio(1f).background(look.key)
            .clickable(remember { MutableInteractionSource() }, indication = null, onClick = tap),
    ) {
        AsyncImage(
            request, "Photo", imageLoader(), contentScale = ContentScale.Crop,
            modifier = Modifier.fillMaxSize().alpha(if (number != null) 0.8f else if (full) 0.4f else 1f),
        )
        val badge = Modifier.align(Alignment.TopEnd).padding(top = 6.dp, end = 6.dp).size(BADGE.dp).clip(CircleShape)
        if (number == null) {
            if (!full) Box(badge.background(Color.Black.copy(alpha = 0.15f)).border(1.5.dp, Color.White, CircleShape))
        } else {
            Box(badge.background(look.accent).border(1.5.dp, Color.White, CircleShape), contentAlignment = Alignment.Center) {
                Text("$number", color = look.accentLabel, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
            }
        }
    }
}

private const val GRID_GAP = 2f
private const val BADGE = 24f
