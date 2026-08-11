package app.privacycam.photo.redactor

import android.content.Context
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.opengl.GLES20
import android.os.Handler
import android.os.Looper
import androidx.media3.common.C
import androidx.media3.common.Effect
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.VideoFrameProcessingException
import androidx.media3.common.util.GlProgram
import androidx.media3.common.util.GlUtil
import androidx.media3.common.util.Size
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.BaseGlShaderProgram
import androidx.media3.effect.GlEffect
import androidx.media3.effect.GlShaderProgram
import androidx.media3.effect.Presentation
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.EditedMediaItemSequence
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.InAppMp4Muxer
import androidx.media3.transformer.ProgressHolder
import androidx.media3.transformer.Transformer
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.abs
import kotlin.math.max

@UnstableApi
class PrivacyCamVideoBridge(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, "app.privacycam/video")
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val analysisCancelled = AtomicBoolean(false)
    private var transformer: Transformer? = null
    private var pendingExportResult: MethodChannel.Result? = null
    private var pendingOutput: File? = null
    private var progressRunnable: Runnable? = null

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "inspectVideo" -> {
                val path = call.argument<String>("path")
                    ?: return result.error("missing_path", "The selected video path is missing.", null)
                worker.execute { inspect(path, result) }
            }
            "extractFrames" -> {
                val path = call.argument<String>("path")
                    ?: return result.error("missing_path", "The selected video path is missing.", null)
                val timestamps = call.argument<List<Number>>("timestampsMs")?.map(Number::toLong)
                    ?: return result.error("invalid_frames", "The video frame request is invalid.", null)
                val maximum = call.argument<Number>("maximumDimension")?.toInt() ?: 1280
                analysisCancelled.set(false)
                worker.execute { extractFrames(path, timestamps, maximum, result) }
            }
            "cancelAnalysis" -> {
                analysisCancelled.set(true)
                result.success(null)
            }
            "exportVideo" -> startExport(call, result)
            "cancelExport" -> {
                cancelExport()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun inspect(path: String, result: MethodChannel.Result) {
        val file = File(path)
        if (!file.exists()) return error(result, "missing_video", "The selected video is no longer available.")
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(path)
            val duration = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0
            var width = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull() ?: 0
            var height = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull() ?: 0
            val rotation = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toIntOrNull() ?: 0
            val frameRate = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_CAPTURE_FRAMERATE)
                ?.toDoubleOrNull()?.takeIf { it > 0.0 } ?: 30.0
            if (rotation == 90 || rotation == 270) width = height.also { height = width }
            success(result, mapOf(
                "durationMs" to duration,
                "width" to width,
                "height" to height,
                "hasAudio" to (retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_HAS_AUDIO) == "yes"),
                "fileSize" to file.length(),
                "frameRate" to frameRate,
            ))
        } catch (_: Throwable) {
            error(result, "unsupported_video", "This video format is not supported on this device.")
        } finally {
            retriever.release()
        }
    }

    private fun extractFrames(
        path: String,
        timestamps: List<Long>,
        maximumDimension: Int,
        result: MethodChannel.Result,
    ) {
        val retriever = MediaMetadataRetriever()
        val directory = File(context.cacheDir, "privacycam_video_frames_${System.nanoTime()}")
        try {
            retriever.setDataSource(path)
            directory.mkdirs()
            val frames = mutableListOf<Map<String, Any>>()
            for (timestamp in timestamps) {
                if (analysisCancelled.get()) {
                    directory.deleteRecursively()
                    return success(result, emptyList<Any>())
                }
                val source = retriever.getFrameAtTime(
                    timestamp * 1000,
                    MediaMetadataRetriever.OPTION_CLOSEST,
                ) ?: continue
                val largest = max(source.width, source.height)
                val bitmap = if (largest > maximumDimension) {
                    val scale = maximumDimension.toDouble() / largest
                    Bitmap.createScaledBitmap(
                        source,
                        max(1, (source.width * scale).toInt()),
                        max(1, (source.height * scale).toInt()),
                        true,
                    ).also { source.recycle() }
                } else {
                    source
                }
                val frame = File(directory, "frame_$timestamp.jpg")
                FileOutputStream(frame).use {
                    if (!bitmap.compress(Bitmap.CompressFormat.JPEG, 91, it)) {
                        throw IllegalStateException("JPEG encoding failed")
                    }
                }
                frames += mapOf(
                    "timestampMs" to timestamp,
                    "path" to frame.absolutePath,
                    "width" to bitmap.width,
                    "height" to bitmap.height,
                )
                bitmap.recycle()
            }
            success(result, frames)
        } catch (_: Throwable) {
            directory.deleteRecursively()
            error(result, "frame_extraction_failed", "PrivacyCam could not read frames from this video.")
        } finally {
            retriever.release()
        }
    }

    private fun startExport(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")
            ?: return result.error("missing_path", "The selected video path is missing.", null)
        val outputPath = call.argument<String>("outputPath")
            ?: return result.error("missing_output", "The export destination is missing.", null)
        val rawTracks = call.argument<List<Map<String, Any?>>>("tracks").orEmpty()
        val tracks = rawTracks.mapNotNull(VideoMaskTrack::fromMap)
        if (tracks.isEmpty()) {
            return result.error("no_redactions", "Select at least one privacy area before exporting.", null)
        }
        val blurStrength = call.argument<Number>("blurStrength")?.toFloat() ?: 18f
        val pixelSize = call.argument<Number>("pixelSize")?.toFloat() ?: 14f
        val muteAudio = call.argument<Boolean>("muteAudio") ?: false
        val editRanges = call.argument<List<Map<String, Any?>>>("editRanges")
            .orEmpty()
            .mapNotNull(VideoEditRange::fromMap)
        if (editRanges.isEmpty()) {
            return result.error("no_kept_video", "Keep at least one part of the video before exporting.", null)
        }
        main.post {
            cancelExport(notifyFlutter = false)
            val output = File(outputPath)
            output.delete()
            pendingOutput = output
            pendingExportResult = result
            try {
                val effects = mutableListOf<Effect>()
                videoDimensions(path)?.let { (width, height) ->
                    if (max(width, height) > 1920) effects += Presentation.createForShortSide(1080)
                }
                tracks.chunked(MAX_MASKS_PER_PASS).forEach { chunk ->
                    effects += VideoRedactionEffect(chunk, blurStrength, pixelSize)
                }
                val sourceUri = Uri.fromFile(File(path))
                val editedItems = editRanges.map { range ->
                    val clipping = MediaItem.ClippingConfiguration.Builder()
                        .setStartPositionMs(range.startMs)
                        .setEndPositionMs(range.endMs)
                        .build()
                    val mediaItem = MediaItem.Builder()
                        .setUri(sourceUri)
                        .setClippingConfiguration(clipping)
                        .build()
                    EditedMediaItem.Builder(mediaItem)
                        .setRemoveAudio(muteAudio)
                        .build()
                }
                val sequence = EditedMediaItemSequence.Builder(editedItems).build()
                val exportComposition = Composition.Builder(sequence)
                    .setEffects(Effects(emptyList(), effects))
                    .build()
                val listener = object : Transformer.Listener {
                    override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                        if (!verifyMetadata(output)) {
                            output.delete()
                            finishExportError(
                                "metadata_verification_failed",
                                "Metadata removal could not be verified, so export was stopped.",
                            )
                            return
                        }
                        finishExportSuccess(output.absolutePath)
                    }

                    override fun onError(
                        composition: Composition,
                        exportResult: ExportResult,
                        exportException: ExportException,
                    ) {
                        output.delete()
                        finishExportError(
                            "export_failed",
                            exportException.localizedMessage ?: "The privacy-safe video could not be created.",
                        )
                    }
                }
                val next = Transformer.Builder(context)
                    .setAudioMimeType(MimeTypes.AUDIO_AAC)
                    .setVideoMimeType(MimeTypes.VIDEO_H264)
                    .setMuxerFactory(InAppMp4Muxer.Factory { entries -> entries.clear() })
                    .addListener(listener)
                    .build()
                transformer = next
                next.start(exportComposition, output.absolutePath)
                startProgress(next)
            } catch (throwable: Throwable) {
                output.delete()
                finishExportError(
                    "export_failed",
                    throwable.localizedMessage ?: "The privacy-safe video could not be created.",
                )
            }
        }
    }

    private fun startProgress(active: Transformer) {
        stopProgress()
        val holder = ProgressHolder()
        val runnable = object : Runnable {
            override fun run() {
                if (transformer !== active) return
                if (active.getProgress(holder) == Transformer.PROGRESS_STATE_AVAILABLE) {
                    channel.invokeMethod("exportProgress", holder.progress / 100.0)
                }
                main.postDelayed(this, 180)
            }
        }
        progressRunnable = runnable
        main.post(runnable)
    }

    private fun stopProgress() {
        progressRunnable?.let(main::removeCallbacks)
        progressRunnable = null
    }

    private fun cancelExport(notifyFlutter: Boolean = true) {
        stopProgress()
        transformer?.cancel()
        transformer = null
        pendingOutput?.delete()
        pendingOutput = null
        if (notifyFlutter) {
            pendingExportResult?.error("export_cancelled", "Video export was cancelled.", null)
        }
        pendingExportResult = null
    }

    private fun finishExportSuccess(path: String) {
        stopProgress()
        transformer = null
        pendingOutput = null
        pendingExportResult?.success(mapOf("path" to path, "metadataRemoved" to true))
        pendingExportResult = null
    }

    private fun finishExportError(code: String, message: String) {
        stopProgress()
        transformer = null
        pendingOutput = null
        pendingExportResult?.error(code, message, null)
        pendingExportResult = null
    }

    private fun verifyMetadata(file: File): Boolean {
        if (!file.exists() || file.length() <= 0) return false
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(file.absolutePath)
            // A newly muxed MP4 can contain its own container creation time.
            // It is not inherited capture metadata, so verify the fields that
            // can identify the source, owner or recording location instead.
            listOf(
                MediaMetadataRetriever.METADATA_KEY_LOCATION,
                MediaMetadataRetriever.METADATA_KEY_AUTHOR,
                MediaMetadataRetriever.METADATA_KEY_ARTIST,
                MediaMetadataRetriever.METADATA_KEY_ALBUM,
                MediaMetadataRetriever.METADATA_KEY_TITLE,
                MediaMetadataRetriever.METADATA_KEY_WRITER,
                MediaMetadataRetriever.METADATA_KEY_COMPOSER,
            ).all { key -> retriever.extractMetadata(key).isNullOrBlank() }
        } catch (_: Throwable) {
            false
        } finally {
            retriever.release()
        }
    }

    private fun videoDimensions(path: String): Pair<Int, Int>? {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(path)
            val width = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull()
            val height = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull()
            if (width == null || height == null) null else width to height
        } catch (_: Throwable) {
            null
        } finally {
            retriever.release()
        }
    }

    private fun success(result: MethodChannel.Result, value: Any?) {
        main.post { result.success(value) }
    }

    private fun error(result: MethodChannel.Result, code: String, message: String) {
        main.post { result.error(code, message, null) }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        analysisCancelled.set(true)
        main.post { cancelExport() }
        worker.shutdownNow()
    }

    companion object {
        private const val MAX_MASKS_PER_PASS = 6
    }
}

private data class VideoMaskKeyframe(val timestampMs: Long, val bounds: FloatArray) {
    companion object {
        fun fromMap(raw: Map<String, Any?>): VideoMaskKeyframe? {
            val timestamp = (raw["timestampMs"] as? Number)?.toLong() ?: return null
            val values = (raw["bounds"] as? List<*>)?.mapNotNull { (it as? Number)?.toFloat() }
                ?: return null
            if (values.size != 4) return null
            return VideoMaskKeyframe(timestamp, values.toFloatArray())
        }
    }
}

private data class VideoEditRange(val startMs: Long, val endMs: Long) {
    companion object {
        fun fromMap(raw: Map<String, Any?>): VideoEditRange? {
            val start = (raw["startMs"] as? Number)?.toLong() ?: return null
            val end = (raw["endMs"] as? Number)?.toLong() ?: return null
            if (end <= start) return null
            return VideoEditRange(start, end)
        }
    }
}

private data class VideoMaskHold(
    val startMs: Long,
    val endMs: Long,
    val bounds: FloatArray,
) {
    fun contains(timestampMs: Long): Boolean = timestampMs in startMs..endMs

    companion object {
        fun fromMap(raw: Map<String, Any?>): VideoMaskHold? {
            val start = (raw["startMs"] as? Number)?.toLong() ?: return null
            val end = (raw["endMs"] as? Number)?.toLong() ?: return null
            val values = (raw["bounds"] as? List<*>)
                ?.mapNotNull { (it as? Number)?.toFloat() }
                ?: return null
            if (end < start || values.size != 4) return null
            return VideoMaskHold(start, end, values.toFloatArray())
        }
    }
}

private data class VideoMaskTrack(
    val category: String,
    val style: String,
    val startMs: Long,
    val endMs: Long,
    val keyframes: List<VideoMaskKeyframe>,
    val holds: List<VideoMaskHold>,
) {
    fun boundsAt(timestampMs: Long): FloatArray? {
        if (timestampMs < startMs || timestampMs > endMs || keyframes.isEmpty()) return null
        holds.asReversed().firstOrNull { it.contains(timestampMs) }?.let { return it.bounds }
        if (timestampMs <= keyframes.first().timestampMs) return keyframes.first().bounds
        if (timestampMs >= keyframes.last().timestampMs) return keyframes.last().bounds
        for (index in 1 until keyframes.size) {
            val next = keyframes[index]
            if (timestampMs > next.timestampMs) continue
            val previous = keyframes[index - 1]
            val fraction = (timestampMs - previous.timestampMs).toFloat() /
                max(1, next.timestampMs - previous.timestampMs).toFloat()
            return FloatArray(4) { coordinate ->
                previous.bounds[coordinate] +
                    (next.bounds[coordinate] - previous.bounds[coordinate]) * fraction
            }
        }
        return keyframes.last().bounds
    }

    companion object {
        fun fromMap(raw: Map<String, Any?>): VideoMaskTrack? {
            val category = raw["category"] as? String ?: return null
            val style = raw["style"] as? String ?: return null
            val start = (raw["startMs"] as? Number)?.toLong() ?: return null
            val end = (raw["endMs"] as? Number)?.toLong() ?: return null
            val frames = (raw["keyframes"] as? List<*>)
                ?.mapNotNull { (it as? Map<*, *>)?.entries?.associate { entry -> entry.key.toString() to entry.value } }
                ?.mapNotNull(VideoMaskKeyframe::fromMap)
                ?.sortedBy(VideoMaskKeyframe::timestampMs)
                .orEmpty()
            val holds = (raw["holds"] as? List<*>)
                ?.mapNotNull { (it as? Map<*, *>)?.entries?.associate { entry -> entry.key.toString() to entry.value } }
                ?.mapNotNull(VideoMaskHold::fromMap)
                ?.sortedBy(VideoMaskHold::startMs)
                .orEmpty()
            if (frames.isEmpty()) return null
            return VideoMaskTrack(category, style, start, end, frames, holds)
        }
    }
}

@UnstableApi
private class VideoRedactionEffect(
    private val tracks: List<VideoMaskTrack>,
    private val blurStrength: Float,
    private val pixelSize: Float,
) : GlEffect {
    override fun toGlShaderProgram(context: Context, useHdr: Boolean): GlShaderProgram =
        VideoRedactionShaderProgram(useHdr, tracks, blurStrength, pixelSize)
}

@UnstableApi
private class VideoRedactionShaderProgram(
    useHdr: Boolean,
    private val tracks: List<VideoMaskTrack>,
    private val blurStrength: Float,
    private val pixelSize: Float,
) : BaseGlShaderProgram(useHdr, 1) {
    private val glProgram = GlProgram(VERTEX_SHADER, FRAGMENT_SHADER)
    private var width = 1
    private var height = 1

    init {
        glProgram.setBufferAttribute(
            "aFramePosition",
            GlUtil.getNormalizedCoordinateBounds(),
            GlUtil.HOMOGENEOUS_COORDINATE_VECTOR_SIZE,
        )
        val identity = GlUtil.create4x4IdentityMatrix()
        glProgram.setFloatsUniform("uTransformationMatrix", identity)
        glProgram.setFloatsUniform("uTexTransformationMatrix", identity)
    }

    override fun configure(inputWidth: Int, inputHeight: Int): Size {
        width = inputWidth
        height = inputHeight
        glProgram.setFloatsUniform("uOutputSize", floatArrayOf(width.toFloat(), height.toFloat()))
        glProgram.setFloatUniform("uBlurRadius", blurStrength.coerceIn(8f, 40f))
        return Size(inputWidth, inputHeight)
    }

    override fun drawFrame(inputTexId: Int, presentationTimeUs: Long) {
        try {
            glProgram.use()
            glProgram.setSamplerTexIdUniform("uTexSampler", inputTexId, 0)
            val timestampMs = presentationTimeUs / 1000
            repeat(MAX_MASKS) { index ->
                val track = tracks.getOrNull(index)
                val bounds = track?.boundsAt(timestampMs)
                glProgram.setFloatsUniform("uRect$index", bounds ?: floatArrayOf(0f, 0f, 0f, 0f))
                glProgram.setFloatUniform("uStyle$index", when (track?.style) {
                    "blur" -> if (bounds == null) 0f else 1f
                    "pixelate" -> if (bounds == null) 0f else 2f
                    "blackout" -> if (bounds == null) 0f else 3f
                    "emoji" -> if (bounds == null) 0f else 4f
                    "flowers" -> if (bounds == null) 0f else 5f
                    else -> 0f
                })
                val secureMinimum = when (track?.category) {
                    "qrCode", "barcode" -> 28f
                    "numberPlate" -> 20f
                    else -> 10f
                }
                glProgram.setFloatUniform("uBlock$index", max(pixelSize, secureMinimum))
            }
            glProgram.bindAttributesAndUniforms()
            GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
        } catch (exception: GlUtil.GlException) {
            throw VideoFrameProcessingException(exception, presentationTimeUs)
        }
    }

    override fun release() {
        try {
            glProgram.delete()
        } catch (_: GlUtil.GlException) {
            // Base release will still return the pooled textures.
        }
        super.release()
    }

    companion object {
        private const val MAX_MASKS = 6
        private const val VERTEX_SHADER = """
            #version 100
            attribute vec4 aFramePosition;
            uniform mat4 uTransformationMatrix;
            uniform mat4 uTexTransformationMatrix;
            varying vec2 vTexSamplingCoord;
            varying vec2 vMaskCoord;
            void main() {
              gl_Position = uTransformationMatrix * aFramePosition;
              vec4 position = vec4(aFramePosition.x * 0.5 + 0.5, aFramePosition.y * 0.5 + 0.5, 0.0, 1.0);
              vTexSamplingCoord = (uTexTransformationMatrix * position).xy;
              vMaskCoord = vec2(position.x, 1.0 - position.y);
            }
        """
        private const val FRAGMENT_SHADER = """
            #version 100
            precision highp float;
            uniform sampler2D uTexSampler;
            uniform vec2 uOutputSize;
            uniform float uBlurRadius;
            uniform vec4 uRect0; uniform float uStyle0; uniform float uBlock0;
            uniform vec4 uRect1; uniform float uStyle1; uniform float uBlock1;
            uniform vec4 uRect2; uniform float uStyle2; uniform float uBlock2;
            uniform vec4 uRect3; uniform float uStyle3; uniform float uBlock3;
            uniform vec4 uRect4; uniform float uStyle4; uniform float uBlock4;
            uniform vec4 uRect5; uniform float uStyle5; uniform float uBlock5;
            varying vec2 vTexSamplingCoord;
            varying vec2 vMaskCoord;

            bool insideRect(vec2 p, vec4 r) {
              return p.x >= r.x && p.y >= r.y && p.x <= r.z && p.y <= r.w;
            }
            vec4 privacyColor(float style, float blockSize, vec4 rect, vec4 baseColor) {
              vec2 local = (vMaskCoord - rect.xy) / max(vec2(0.0001), rect.zw - rect.xy);
              vec2 p = (local - 0.5) * 2.0;
              if (style > 4.5) {
                float petal = 0.0;
                petal = max(petal, 1.0 - step(0.30, length(p - vec2(0.00, -0.30))));
                petal = max(petal, 1.0 - step(0.30, length(p - vec2(0.26, -0.15))));
                petal = max(petal, 1.0 - step(0.30, length(p - vec2(0.26, 0.15))));
                petal = max(petal, 1.0 - step(0.30, length(p - vec2(0.00, 0.30))));
                petal = max(petal, 1.0 - step(0.30, length(p - vec2(-0.26, 0.15))));
                petal = max(petal, 1.0 - step(0.30, length(p - vec2(-0.26, -0.15))));
                float middle = 1.0 - step(0.23, length(p));
                if (middle > 0.5) return vec4(1.0, 0.89, 0.64, 1.0);
                if (petal > 0.5) return vec4(1.0, 0.35, 0.12, 1.0);
                return baseColor;
              }
              if (style > 3.5) {
                p.y += 0.12;
                float x2y2 = p.x * p.x + p.y * p.y - 0.32;
                float heart = x2y2 * x2y2 * x2y2 - p.x * p.x * p.y * p.y * p.y;
                return heart <= 0.0 ? vec4(1.0, 0.79, 0.16, 1.0) : baseColor;
              }
              if (style > 2.5) return vec4(0.0, 0.0, 0.0, 1.0);
              if (style > 1.5) {
                vec2 blocks = max(vec2(1.0), uOutputSize / max(8.0, blockSize));
                vec2 uv = (floor(vTexSamplingCoord * blocks) + 0.5) / blocks;
                return texture2D(uTexSampler, uv);
              }
              vec2 d = vec2(uBlurRadius) / uOutputSize;
              vec4 color = texture2D(uTexSampler, vTexSamplingCoord) * 0.20;
              color += texture2D(uTexSampler, vTexSamplingCoord + vec2(d.x, 0.0)) * 0.10;
              color += texture2D(uTexSampler, vTexSamplingCoord - vec2(d.x, 0.0)) * 0.10;
              color += texture2D(uTexSampler, vTexSamplingCoord + vec2(0.0, d.y)) * 0.10;
              color += texture2D(uTexSampler, vTexSamplingCoord - vec2(0.0, d.y)) * 0.10;
              color += texture2D(uTexSampler, vTexSamplingCoord + d) * 0.10;
              color += texture2D(uTexSampler, vTexSamplingCoord - d) * 0.10;
              color += texture2D(uTexSampler, vTexSamplingCoord + vec2(d.x, -d.y)) * 0.10;
              color += texture2D(uTexSampler, vTexSamplingCoord + vec2(-d.x, d.y)) * 0.10;
              return color;
            }
            void main() {
              vec4 color = texture2D(uTexSampler, vTexSamplingCoord);
              if (uStyle0 > 0.5 && insideRect(vMaskCoord, uRect0)) color = privacyColor(uStyle0, uBlock0, uRect0, color);
              if (uStyle1 > 0.5 && insideRect(vMaskCoord, uRect1)) color = privacyColor(uStyle1, uBlock1, uRect1, color);
              if (uStyle2 > 0.5 && insideRect(vMaskCoord, uRect2)) color = privacyColor(uStyle2, uBlock2, uRect2, color);
              if (uStyle3 > 0.5 && insideRect(vMaskCoord, uRect3)) color = privacyColor(uStyle3, uBlock3, uRect3, color);
              if (uStyle4 > 0.5 && insideRect(vMaskCoord, uRect4)) color = privacyColor(uStyle4, uBlock4, uRect4, color);
              if (uStyle5 > 0.5 && insideRect(vMaskCoord, uRect5)) color = privacyColor(uStyle5, uBlock5, uRect5, color);
              gl_FragColor = color;
            }
        """
    }
}
