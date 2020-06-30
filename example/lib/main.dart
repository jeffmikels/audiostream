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

  Uint8List data;

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
      platformVersion = await Audiostream.platformVersion;
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

  Future<bool> preparePlayer() async {
    print('preparing player');
    e('initializing player to $sampleRate');
    var res = await Audiostream.initialize(
      rate: sampleRate,
      largeBuffer: true,
    );

    data = (await rootBundle.load('assets/sample-$sampleRate-s16le.raw'))
        .buffer
        .asUint8List();
    setState(() {
      playerReady = res;
    });
    return res;
  }

  Future<bool> play() async {
    var res;
    e('sending audio data');
    e('calling with await');
    res = await Audiostream.write(data);
    e('here we are!');
    e('here we are again');
    // var frames = data.lengthInBytes ~/ sampleRate;
    // for (var i = 0; i < frames; i++) {
    //   var start = i * sampleRate;
    //   var towrite = data.sublist(start, start + sampleRate);
    //   e('sending packet $i, ${towrite.lengthInBytes} bytes');
    //   await Audiostream.write(towrite);
    // }
    return res;
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
