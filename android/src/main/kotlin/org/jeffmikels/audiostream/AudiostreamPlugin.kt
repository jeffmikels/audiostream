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

  override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "audiostream")
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
      val channel = MethodChannel(registrar.messenger(), "audiostream")
      channel.setMethodCallHandler(AudiostreamPlugin())
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
        println("AUDIO TRACK RATE: $rate")
      }
    }

    if (call.hasArgument("channels")) {
      val givenChannels = call.argument<Int>("channels")
      if (givenChannels is Int) {
        channels = givenChannels
        println("AUDIO TRACK CHANNELS: $channels")
      }
    }

    if (call.hasArgument("bufferBytes")) {
      val givenBuffer = call.argument<Int>("bufferBytes")
      if (givenBuffer is Int) {
        bufferSize = givenBuffer
        println("AUDIO TRACK BUFFER: $bufferSize")
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

    closePlayer() // releases existing player


    player = AudioTrack.Builder()
            .setAudioAttributes(AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                    .build())
            .setAudioFormat(AudioFormat.Builder()
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .setSampleRate(rate)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_STEREO)
                    .build())
            .setTransferMode(AudioTrack.MODE_STREAM)
            .setBufferSizeInBytes(bufferSize)
            .build()


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
    } else if (audioData is ByteArray){
      var offset = 0;
      println("starting player")
      player.play()
      println("writing to audio buffer")
      while (audioData.lastIndex > offset) {
        offset += player.write(audioData, offset, audioData.size - offset, AudioTrack.WRITE_NON_BLOCKING)
      }
      println("$offset bytes written to buffer, returning")
      result.success( true )
    } else {
      result.error("MISMATCH", "audioData is not a ByteArray", "")
    }
  }


}
