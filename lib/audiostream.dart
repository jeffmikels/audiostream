import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

// import 'package:sound_stream/sound_stream.dart';

import 'package:flutter/services.dart';

// we handle mixing in the Dart layer
// because dart is fast enough and it's
// easier this way
// if performance suffers when streams increase,
// we may have to switch to mixing on the platform side
class AudioStreamMixer {
  static bool _mixing = false;
  static int sampleRate;
  static int bufferBytes;
  static int bufferSamples;
  static int channels;
  static int sampleBits;
  static List<AudioStream> streams = [];
  static bool initialized = false;
  static bool closed = true;
  static bool debug = false;

  // static PlayerStream _player = PlayerStream();
  // static RecorderStream _recorder = RecorderStream();

  static const MethodChannel _channel =
      const MethodChannel('org.jeffmikels.audiostream');
  static Future<String> get platformVersion async {
    final String version = await _channel.invokeMethod('getPlatformVersion');
    return version;
  }

  /// Initializes a Platform Audio Player
  /// with the specified rate, bits, channels and buffer values.
  ///
  /// [bufferBytes] refers to the amount of memory to allocate on the
  /// local side for the audio buffer.
  ///
  /// [androidBufferBytes] refers to the amount to allocate on the
  /// platform side for the audio buffer on Android devices.
  /// the android audiotrack.write is a blocking operation while the iOS
  /// version is not. Therefore, we allow the customization of the android
  /// audio buffer here. Note: if the buffer is too low, the UI might lag;
  /// if the buffer is too high, the creation of the Android AudioTrack
  /// might fail
  ///
  /// the android buffer should be a multiple of the local buffer, and
  /// should be large enough to receive all the data you intend to send
  /// in any given write operation
  ///
  /// Android doesn't document the maximum size for the buffer,
  /// but experiments indicate that buffers longer than 10 seconds
  /// can cause intitialization to fail.
  static Future<bool> initialize({
    int sampleRate = 44100,
    int channels = 2,
    int bufferMillis = 0,
    int sampleBits = 16,
    int androidBufferBytes = 0,
  }) async {
    if (!closed) await close();

    print('Initializing audiostreams with the following settings:');
    print('Sample Rate: $sampleRate');
    print('Channels: $channels');
    print('Bits per Sample: $sampleBits');
    print('Buffer: ${bufferMillis}ms');
    print('Requested Android Buffer: $androidBufferBytes bytes');

    // initialize the streamplayer player
    // await _player.initialize(sampleRate: sampleRate, channels: channels);
    // print('Initialized Sound Stream Plugin');
    // await _player.start();

    // not necessary
    // if (Platform.isIOS && bufferMillis < 20) bufferMillis = 20;

    // compute safe buffer value in bytes
    while (true) {
      var bSamples = sampleRate * channels * (bufferMillis / 1000);
      int bSamplesInt = bSamples ~/ 1;
      if (bSamplesInt == bSamples) {
        AudioStreamMixer.bufferSamples = bSamplesInt;
        AudioStreamMixer.bufferBytes = bSamplesInt * (sampleBits ~/ 8);
        break;
      }
      bufferMillis += 1;
    }
    AudioStreamMixer.sampleRate = sampleRate;
    AudioStreamMixer.sampleBits = sampleBits;
    AudioStreamMixer.channels = channels;

    var maxAndroidBufferBytes = sampleRate * channels * (sampleBits ~/ 8) * 10;

    if (androidBufferBytes == 0) androidBufferBytes = bufferBytes * 2;
    if (androidBufferBytes > maxAndroidBufferBytes)
      androidBufferBytes = maxAndroidBufferBytes;

    if (Platform.isAndroid) {
      print("Initializing Android with buffer of $androidBufferBytes bytes");
    }

    try {
      final bool result = await _channel.invokeMethod('initialize', {
        'rate': sampleRate,
        'channels': channels,
        'bufferBytes': androidBufferBytes, // ignored on iOS
      });
      if (result) {
        closed = false;
        initialized = true;
      }
      return result;
    } on PlatformException catch (e) {
      print('PlatformException: ${e.message}');
      return false;
    }
  }

  // close player
  static Future<bool> close() async {
    // _player.stop();

    print('closing media player');
    try {
      final bool result = await _channel.invokeMethod('close');
      if (result) closed = true;
      return result;
    } on PlatformException catch (e) {
      print('PlatformException: ${e.message}');
      return false;
    }
  }

  static destroy() async {}

  static registerStream(AudioStream stream) => streams.add(stream);
  static removeStream(AudioStream stream) => streams.remove(stream);

  static mixdown() async {
    if (_mixing) return;

    // print('mixdown');
    _mixing = true;

    final List<int> mixedBuffer = [];
    bool keepMixing = true;
    while (keepMixing) {
      var now = DateTime.now();
      // make sure at least one of the streams has enough samples
      var longestStreamSamples = 0;
      for (var stream in streams) {
        if (stream.buffer.length > longestStreamSamples) {
          longestStreamSamples = stream.buffer.length;
        }
      }
      if (longestStreamSamples < bufferSamples) break;
      // print('mixing $longestStreamSamples samples each from ${streams.length} streams');

      // mix samples based on the longest stream buffer
      for (var i = 0; i < longestStreamSamples; i++) {
        double mixedSample = 0;

        // multiply samples by their volume and add together
        for (var stream in streams) {
          int sample = 0;
          if (i < stream.buffer.length) sample = stream.buffer[i] ?? 0;
          mixedSample += (stream.volume * sample);
        }

        mixedBuffer.add(mixedSample ~/ 1);
      }

      // don't bother waiting for this, just send the data
      // to the native layer and move on!
      // write(Int16List.fromList(mixedBuffer).buffer.asUint8List());
      await write(mixedBuffer);
      mixedBuffer.clear();

      // truncate individual stream buffers and check for more data
      keepMixing = false;
      for (var stream in streams) {
        if (stream.buffer.length <= longestStreamSamples) {
          stream.buffer.clear();
          // print('mixing done');
        } else {
          stream.buffer = stream.buffer.sublist(longestStreamSamples);
          keepMixing = true;
        }
      }
      var elapsed = DateTime.now().difference(now).inMilliseconds;
      if (debug) print('Mixdown took $elapsed ms.');
    }

    _mixing = false;
    // _player.stop();
  }

  /// send samples to the platform audiostream
  static Future<bool> write(List<int> samples) async {
    if (!initialized) throw AudioStreamNotInitialized();
    var now = DateTime.now();
    bool res = false;
    if (debug) print('sending ${samples.length} samples to platform layer');
    try {
      if (Platform.isAndroid) {
        await _channel.invokeMethod('write', Int32List.fromList(samples));
        res = true;
      } else if (Platform.isIOS) {
        await _channel.invokeMethod('write', samples);
        // _player.writeChunk(bytes);
        // result = true;
      }
      // print('wrote ${bytes.length} bytes');
    } on PlatformException catch (e) {
      print('PlatformException: ${e.message}');
    }
    var elapsed = DateTime.now().difference(now).inMilliseconds;
    if (debug) print('Audio Write took $elapsed ms.');
    return res;
  }
}

/// remember to destroy this stream when done with it.
class AudioStream {
  bool get initialized => AudioStreamMixer.initialized;
  List<int> buffer = [];
  double volume;

  /// volume should be between 0 and 1;
  AudioStream({this.volume = 0.7}) {
    AudioStreamMixer.registerStream(this);
  }

  void destroy() => AudioStreamMixer.removeStream(this);

  /// Add a list of samples to the local buffer, and trigger the Mixer to
  /// start a mixdown if it is not already running.
  /// samples should be of the same bit format as [AudioStreamMixer.sampleBits]
  void mix(List<int> samples, {bool delayMixdown = false}) {
    if (!initialized) throw AudioStreamNotInitialized();
    buffer.addAll(samples);
    if (!delayMixdown) AudioStreamMixer.mixdown();
  }
}

class AudioStreamAlreadyInitialized implements Exception {}

class AudioStreamNotInitialized implements Exception {}
