import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:audiostream/audiostream.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String _platformVersion = 'Unknown';
  int change = 0;
  int sampleRate = 48000;
  String note = '';

  bool playerReady = false;
  AudioStream audioStream;

  Int16List samples;

  @override
  void initState() {
    super.initState();
    initPlatformState();
    preparePlayer();
  }

  void e(String s) {
    print(s);
    setState(() {
      note = s;
    });
  }

  // Platform messages are asynchronous, so we initialize in an async method.
  Future<void> initPlatformState() async {
    String platformVersion;
    // Platform messages may fail, so we use a try/catch PlatformException.
    try {
      platformVersion = await AudioStreamMixer.platformVersion;
    } on PlatformException {
      platformVersion = 'Failed to get platform version.';
    }

    // If the widget was removed from the tree while the asynchronous platform
    // message was in flight, we want to discard the reply rather than calling
    // setState to update our non-existent appearance.
    if (!mounted) return;

    setState(() {
      _platformVersion = platformVersion;
    });
  }

  Future<void> preparePlayer() async {
    print('preparing player');
    e('initializing player to $sampleRate');
    await AudioStreamMixer.initialize(
      sampleRate: sampleRate,
      channels: 2,
      androidBufferBytes: sampleRate * 2 * 2 * 5,
    );

    samples = (await rootBundle.load('assets/sample-$sampleRate-s16le.raw'))
        .buffer
        .asInt16List();
    setState(() {
      playerReady = AudioStreamMixer.initialized;
    });
  }

  void play() async {
    // AudioStreamMixer.write(samples.buffer.asUint8List());
    var as1 = AudioStream(volume: .2);
    var as2 = AudioStream(volume: .7);
    e('sending audio data');
    as1.mix(samples, delayMixdown: true);
    as2.mix([...List<int>(48000 * 3), ...samples]);
    e('here we are!');
    as1.destroy();
    as2.destroy();
    // var frames = data.lengthInBytes ~/ sampleRate;
    // for (var i = 0; i < frames; i++) {
    //   var start = i * sampleRate;
    //   var towrite = data.sublist(start, start + sampleRate);
    //   e('sending packet $i, ${towrite.lengthInBytes} bytes');
    //   await Audiostream.write(towrite);
    // }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Plugin example app'),
        ),
        body: ListView(
          padding: EdgeInsets.all(20),
          children: <Widget>[
            Text(
              note,
              style: TextStyle(fontSize: 20),
            ),
            Container(
              child: RaisedButton(
                child: Text('play - $change'),
                onPressed: playerReady
                    ? () {
                        play();
                      }
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
