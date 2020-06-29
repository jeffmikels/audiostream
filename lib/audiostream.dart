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

  // initialize player
  static Future<bool> initialize() async {
    if (!closed) await close();

    try {
      final bool result = await _channel.invokeMethod('initialize');
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

  // write audio to player
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
