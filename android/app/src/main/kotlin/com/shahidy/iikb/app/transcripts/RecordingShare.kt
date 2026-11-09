package com.shahidy.iikb.app.transcripts

import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.MediaMuxer
import android.provider.Telephony
import androidx.core.content.FileProvider
import com.shahidy.iikb.Transcript
import com.shahidy.iikb.Transcripts
import com.shahidy.iikb.keyboard.Clips
import com.shahidy.iikb.voice.Recording
import java.io.File
import java.io.IOException

/**
 * A transcript's sound sent on, as iOS's `RecordingShare`: as AAC in an .m4a, which texting apps and players all take,
 * into a new message in the phone's texting app or through the share sheet. Each export takes the last one's place in
 * the cache's `recordings/`, since Android never says when the app it went to is done reading it.
 */
object RecordingShare {
    /** The phone's texting app, by package and name; null where there's none, as on a tablet without one. */
    fun messages(context: Context): Pair<String, String>? {
        val sms = Telephony.Sms.getDefaultSmsPackage(context) ?: return null
        val packages = context.packageManager
        val name = runCatching { packages.getApplicationLabel(packages.getApplicationInfo(sms, 0)).toString() }.getOrNull()
        return name?.let { sms to it }
    }

    /** The recording exported, so call it off the main thread, in an intent for the texting app or else the share sheet. */
    fun intent(context: Context, transcript: Transcript, toMessages: Boolean): Intent {
        val file = export(context, transcript)
        val uri = FileProvider.getUriForFile(context, Clips.AUTHORITY, file)
        val send = Intent(Intent.ACTION_SEND).setType("audio/mp4").putExtra(Intent.EXTRA_STREAM, uri)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        send.clipData = ClipData.newRawUri(file.name, uri)
        val sms = if (toMessages) messages(context)?.first else null
        return (if (sms != null) send.setPackage(sms) else Intent.createChooser(send, null)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }

    private fun export(context: Context, transcript: Transcript): File {
        val recording = Recording.read(Transcripts.recording(transcript.id))?.takeIf { it.samples.isNotEmpty() }
            ?: throw IOException("The recording couldn’t be read")
        val folder = File(context.cacheDir, "recordings")
        folder.deleteRecursively()
        folder.mkdirs()
        return File(folder, name(transcript) + ".m4a").also { encode(recording, it) }
    }

    /** Its first six words, as iOS names it, else "iikb Recording". */
    private fun name(transcript: Transcript): String =
        transcript.text.split(Regex("\\s+")).filter { it.isNotEmpty() }.take(6).joinToString(" ")
            .filterNot { it in "/:\\\\" }.ifEmpty { "iikb Recording" }

    /** The recording as AAC-LC, 16 kHz mono, by Android's own encoder. */
    private fun encode(recording: Recording, file: File) {
        val pcm = recording.pcm16()
        val format = MediaFormat.createAudioFormat(MediaFormat.MIMETYPE_AUDIO_AAC, Recording.RATE, 1).apply {
            setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC)
            setInteger(MediaFormat.KEY_BIT_RATE, 48_000)
        }
        val codec = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC)
        val muxer = MediaMuxer(file.path, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        var track = -1
        try {
            codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            codec.start()
            val info = MediaCodec.BufferInfo()
            var offset = 0
            var fed = false
            while (true) {
                if (!fed) {
                    val index = codec.dequeueInputBuffer(TIMEOUT)
                    if (index >= 0) {
                        val buffer = codec.getInputBuffer(index)!!
                        val count = minOf(buffer.remaining() and 1.inv(), pcm.size - offset)
                        buffer.put(pcm, offset, count)
                        val time = offset / 2 * 1_000_000L / Recording.RATE
                        offset += count
                        fed = offset >= pcm.size
                        codec.queueInputBuffer(index, 0, count, time, if (fed) MediaCodec.BUFFER_FLAG_END_OF_STREAM else 0)
                    }
                }
                val index = codec.dequeueOutputBuffer(info, TIMEOUT)
                if (index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    track = muxer.addTrack(codec.outputFormat)
                    muxer.start()
                } else if (index >= 0) {
                    if (info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG == 0 && info.size > 0 && track >= 0) {
                        muxer.writeSampleData(track, codec.getOutputBuffer(index)!!, info)
                    }
                    codec.releaseOutputBuffer(index, false)
                    if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) break
                }
            }
        } finally {
            runCatching { codec.stop() }
            codec.release()
            if (track >= 0) runCatching { muxer.stop() }
            muxer.release()
        }
    }

    private const val TIMEOUT = 10_000L
}
