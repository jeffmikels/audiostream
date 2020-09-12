import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

// import 'package:sound_stream/sound_stream.dart';

import 'package:flutter/services.dart';

class AudioStreamMixer {
  static bool _mixing = false;
  static int sampleRate;
  static int bufferBytes;
  static int bufferSamples;
  static int channels;
  static int sampleBits;
  static bool largeBuffer;
  static List<AudioStream> streams = [];
  static bool initialized = false;
  static bool closed = true;

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
  /// bufferBytes refers to the amount of memory to allocate on the
  /// platform side for the audio buffer. Android doesn't document
  /// the maximum size for the buffer, but experiments have shown that
  /// buffers longer than 10 seconds can cause intitialization to fail
  /// set {largeBuffer} to true to automatically use a 10 second buffer
  static Future<bool> initialize({
    int sampleRate = 44100,
    int channels = 2,
    int bufferMillis = 0,
    int sampleBits = 16,
    bool largeBuffer = false,
  }) async {
    if (!closed) await close();

    print('Initializing audiostreams with the following settings:');
    print('Sample Rate: $sampleRate');
    print('Channels: $channels');
    print('Bits per Sample: $sampleBits');
    print('Buffer: ${bufferMillis}ms');

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
    AudioStreamMixer.largeBuffer = largeBuffer;

    var maxBufferBytes = sampleRate * channels * (sampleBits ~/ 8) * 10;
    if (largeBuffer || bufferBytes > maxBufferBytes)
      bufferBytes = maxBufferBytes;

    print("Selected Buffer of $bufferBytes bytes");

    try {
      final bool result = await _channel.invokeMethod('initialize', {
        'rate': sampleRate,
        'channels': channels,
        'bufferBytes': bufferBytes, // ignored on iOS
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
      await write(Int16List.fromList(mixedBuffer).buffer.asUint8List());
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
    }
    _mixing = false;
    // _player.stop();
  }

  /// send raw bytes to the platform audiostream
  /// bytes should be a Uint8List of 16 bit PCM data
  static Future<bool> write(Uint8List bytes) async {
    if (!initialized) throw AudioStreamNotInitialized();
    try {
      bool result;

      if (Platform.isAndroid) {
        result = await _channel.invokeMethod('write', bytes);
      } else if (Platform.isIOS) {
        result = await _channel.invokeMethod('write', bytes);
        // _player.writeChunk(bytes);
        // result = true;
      }
      // print('wrote ${bytes.length} bytes');
      return result;
    } on PlatformException catch (e) {
      print('PlatformException: ${e.message}');
      return false;
    }
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

  /// samples should be of the same bit format as [AudioStreamMixer.sampleBits]
  void mix(List<int> samples, {bool delayMixdown = false}) {
    if (!initialized) throw AudioStreamNotInitialized();
    buffer.addAll(samples);
    if (!delayMixdown) AudioStreamMixer.mixdown();
  }
}

class AudioStreamAlreadyInitialized implements Exception {}

class AudioStreamNotInitialized implements Exception {}
