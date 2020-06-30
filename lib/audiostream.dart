import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';

class Audiostream {
  static bool closed = true;
  static const MethodChannel _channel = const MethodChannel('audiostream');

  static Future<String> get platformVersion async {
    final String version = await _channel.invokeMethod('getPlatformVersion');
    return version;
  }

  /// Initializes a 2 channel 16bit PCM Platform Audio Player
  /// with the specified rate and buffer values.
  ///
  /// bufferBytes refers to the amount of memory to allocate on the
  /// platform side for the audio buffer. Android doesn't document
  /// the maximum size for the buffer, but experiments have shown that
  /// buffers longer than 10 seconds can cause intitialization to fail
  /// set {largeBuffer} to true to automatically use a 10 second buffer
  static Future<bool> initialize(
      {int rate = 44100, int bufferBytes, bool largeBuffer = false}) async {
    if (!closed) await close();

    bufferBytes = bufferBytes ?? 0;
    var maxBufferBytes = rate * 2 * 2 * 10;
    if (largeBuffer || bufferBytes > maxBufferBytes)
      bufferBytes = maxBufferBytes;

    try {
      final bool result = await _channel.invokeMethod(
          'initialize', {'rate': rate, 'bufferBytes': bufferBytes ?? 0});
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

  /// write two channel 16 bit PCM audio to player
  /// using the sample rate specified during initialization
  static Future<bool> write(Uint8List data) async {
    try {
      final bool result = await _channel.invokeMethod('write', data);
      return result;
    } on PlatformException catch (e) {
      print('PlatformException: ${e.message}');
      return false;
    }
  }
}
