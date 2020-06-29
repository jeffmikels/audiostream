import 'dart:async';

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

  bool playerReady = false;

  @override
  void initState() {
    super.initState();
    initPlatformState();
    preparePlayer();
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
    var res = await Audiostream.initialize();
    setState(() {
      playerReady = res;
    });
    return res;
  }

  Future<bool> play() async {
    var res;
    var data =
        (await rootBundle.load('assets/sample.raw')).buffer.asUint8List();
    print('sending audio data');
    var frames = data.lengthInBytes / (441000);
    for (var i = 0; i < frames; i++) {
      var start = i * 441000;
      var towrite = data.sublist(start, start + 441000);
      print(towrite.lengthInBytes);
      // res = await Audiostream.write(towrite);
      // print(res);
      Audiostream.write(towrite);
      setState(() {
        change += 1;
      });
    }
    return res;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Plugin example app'),
        ),
        body: Center(
          child: RaisedButton(
            child: Text('play - $change'),
            onPressed: playerReady
                ? () {
                    play();
                  }
                : null,
          ),
        ),
      ),
    );
  }
}
