package org.jeffmikels.audiostream

import android.media.AudioAttributes
import android.media.AudioFormat

import android.media.AudioTrack
import androidx.annotation.NonNull
import androidx.annotation.UiThread
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry.Registrar
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** AudiostreamPlugin */
public class AudiostreamPlugin: FlutterPlugin, MethodCallHandler {
  /// The MethodChannel that will the communication between Flutter and native Android
  ///
  /// This local reference serves to register the plugin with the Flutter Engine and unregister it
  /// when the Flutter Engine is detached from the Activity
  private lateinit var channel : MethodChannel
  private lateinit var player : AudioTrack
  private var rate = 44100
  private var channels = 2
  private var initialized = false
  private var sampleBuffer = MutableList<Short>(0, init = { 0 })
  private var bufferPlaying = false

  override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "org.jeffmikels.audiostream")
    channel.setMethodCallHandler(this);
  }

  // This static function is optional and equivalent to onAttachedToEngine. It supports the old
  // pre-Flutter-1.12 Android projects. You are encouraged to continue supporting
  // plugin registration via this function while apps migrate to use the new Android APIs
  // post-flutter-1.12 via https://flutter.dev/go/android-project-migration.
  //
  // It is encouraged to share logic between onAttachedToEngine and registerWith to keep
  // them functionally equivalent. Only one of onAttachedToEngine or registerWith will be called
  // depending on the user's project. onAttachedToEngine or registerWith must both be defined
  // in the same class.
  companion object {
    @JvmStatic
    fun registerWith(registrar: Registrar) {
      val channel = MethodChannel(registrar.messenger(), "org.jeffmikels.audiostream")
      var instance = AudiostreamPlugin()
      channel.setMethodCallHandler(instance)
    }
  }

  override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
    when (call.method) {
      "getPlatformVersion" -> result.success("Android ${android.os.Build.VERSION.RELEASE}")
      "initialize" -> doInitialize(call, result)
      "close" -> doClose(result)
      "write" -> doWrite(call.arguments, result)
      else -> result.notImplemented()
    }
  }

  override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
    closePlayer()
    channel.setMethodCallHandler(null)
  }

  private fun doInitialize(@NonNull call: MethodCall, @NonNull result: Result) {
    var bufferSize = 0

    if (call.hasArgument("rate")) {
      val givenRate = call.argument<Int>("rate")
      if (givenRate is Int) {
        rate = givenRate
      }
    }

    if (call.hasArgument("channels")) {
      val givenChannels = call.argument<Int>("channels")
      if (givenChannels is Int) {
        channels = givenChannels
      }
    }

    if (call.hasArgument("bufferBytes")) {
      val givenBuffer = call.argument<Int>("bufferBytes")
      if (givenBuffer is Int) {
        bufferSize = givenBuffer
      }
    }

    val channelConstant = if (channels == 1) AudioFormat.CHANNEL_OUT_MONO else AudioFormat.CHANNEL_OUT_STEREO
    val minBufSize = AudioTrack.getMinBufferSize(rate,
            channelConstant,
            AudioFormat.ENCODING_PCM_16BIT
    )
    val maxBufSize = rate * channels * 2 * 10 // 2 bytes is 16 bits & 10 second max buffer
    if (bufferSize < minBufSize) bufferSize = minBufSize
    if (bufferSize > maxBufSize) bufferSize = maxBufSize

    closePlayer() // releases existing player if it exists


    println("AUDIO TRACK RATE: $rate")
    println("AUDIO TRACK ENCODING: PCM_16BIT")
    println("AUDIO TRACK CHANNELS: $channels")
    println("AUDIO TRACK BUFFER: $bufferSize")
    player = AudioTrack.Builder()
            .setAudioAttributes(AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                    .build())
            .setAudioFormat(AudioFormat.Builder()
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .setSampleRate(rate)
                    .setChannelMask(channelConstant)
                    .build())
            .setTransferMode(AudioTrack.MODE_STREAM)
            .setBufferSizeInBytes(bufferSize)
            .build()
// .setPerformanceMode(AudioTrack.PERFORMANCE_MODE_LOW_LATENCY)   // api 26+
// .setOffloadedPlayback(true)                                    // api 29+

    // start player for streaming
    initialized = true
    result.success( true )
  }

  private fun closePlayer() {
    if (initialized) {
      player.flush()
      player.release()
    }
  }

  private fun doClose(@NonNull result: Result) {
    closePlayer()
    result.success( true )
  }

  private fun doWrite(@NonNull audioData:Any, @NonNull result: Result) {
    if (!initialized){
      result.error("NOT INITIALIZED", "You must call initialize first", "")
    } else if (audioData is IntArray){
      println("received ${audioData.size} samples... storing in buffer")
      if (player.playState != AudioTrack.PLAYSTATE_PLAYING) {
        player.play()
      }

      // convert submitted data to shorts and store in a buffer here
      // we do this here because we might want to offload the
      // playback of this buffer to another thread
      for (item in audioData) {
        sampleBuffer.add(item.toShort())
      }
      println("sampleBuffer now has ${sampleBuffer.size} samples")
      println("triggering player")

      // currently, this function will block until
      // all data has been written to the audio track
      // to prevent lag problems, consider building the
      // audio track with a large buffer of its own
      // or offloading the playback to it's own thread
      playBuffer()


      result.success( true )
    } else {
      result.error("MISMATCH", "audioData is not a IntArray", "")
    }
  }

  private fun playBuffer() {

    // this is a sanity check to make this thread safe
    if (bufferPlaying) return
    bufferPlaying = true
    println("in playBuffer")

    player.play()
    while (sampleBuffer.size > 0) {
      val count = sampleBuffer.size

      // get everything from our buffer
      val shorts = ShortArray(count)

      // println("SampleBuffer has $count samples")

      for (i in 0 until count) {
        shorts[i] = sampleBuffer[i]
      }
      sampleBuffer = MutableList(size=sampleBuffer.size - count, init = { sampleBuffer[count + it] })

      var offset = 0
      // println("writing ${shorts.size} samples to audio buffer")
      while (shorts.lastIndex > offset) {
        offset += player.write(shorts, offset, shorts.size - offset, AudioTrack.WRITE_NON_BLOCKING)
        // println("$offset samples written to buffer")
      }
      // println("sampleBuffer now has ${sampleBuffer.size} samples")
    }
    bufferPlaying = false
  }
}


class CircularShortArray {

  constructor(size: Int) {
    this.arr = ShortArray(size)
  }

  private val arr: ShortArray
  private var readIndex: Int = 0
  private var writeIndex: Int = 0

  private val availableSpaceForReading: Int get() = writeIndex - readIndex
  private val availableSpaceForWriting: Int get() = arr.size - availableSpaceForReading
  private val isEmpty: Boolean get() = availableSpaceForReading == 0
  private val isFull: Boolean get() = availableSpaceForWriting == 0
  val size: Int get() = availableSpaceForReading

  fun write(element: Short) : Boolean {
    if (!isFull) {
      arr[writeIndex % arr.size] = element
      writeIndex++
      return true
    }
    return false
  }

  @Suppress("UNCHECKED_CAST")
  fun read() : Short {
    if (!isEmpty) {
      val el = arr[readIndex % arr.size]
      readIndex++
      return el
    }
    return 0
  }
}