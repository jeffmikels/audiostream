import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';

class Audiostream {
  // to handle using as a stream
  static StreamController<Int16List> consumer = StreamController();
  static StreamSubscription _streamSubscription;

  static bool closed = true;
  static const MethodChannel _channel = const MethodChannel('audiostream');

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
    int rate = 44100,
    int channels = 2,
    int bufferSeconds = 0,
    int sampleBits = 16,
    bool largeBuffer = false,
  }) async {
    if (_streamSubscription == null) {
      _streamSubscription = consumer.stream.listen((data) {
        print('audio data received');
        write(data.buffer);
      });
    }
    if (!closed) await close();

    var bufferBytes = rate * channels * (sampleBits ~/ 8) * bufferSeconds;
    var maxBufferBytes = rate * channels * (sampleBits ~/ 8) * 10;
    if (largeBuffer || bufferBytes > maxBufferBytes)
      bufferBytes = maxBufferBytes;

    try {
      final bool result = await _channel.invokeMethod('initialize',
          {'rate': rate, 'channels': channels, 'bufferBytes': bufferBytes});
      if (result) closed = false;
      return result;
    } on PlatformException catch (e) {
      print('PlatformException: ${e.message}');
      return false;
    }
  }

  // close player
  static Future<bool> close() async {
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

  static destroy() async {
    _streamSubscription?.cancel();
    consumer?.close();
  }

  /// send raw bytes to the platform audiostream
  /// using the sample rate specified during initialization
  static Future<bool> write(ByteBuffer _bytes) async {
    // var data = Int16List.fromList(_data).buffer.asUint8List();
    Uint8List bytes = _bytes.asUint8List();

    try {
      // write expects a ByteArray (Uint8List) of 16 bit PCM data
      final bool result = await _channel.invokeMethod('write', bytes);
      return result;
    } on PlatformException catch (e) {
      print('PlatformException: ${e.message}');
      return false;
    }
  }
}
