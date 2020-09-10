import Flutter
import UIKit

@available(iOS 9.0, *)
public class SwiftAudiostreamPlugin: NSObject, FlutterPlugin {
    var audioStream = AudioStream()

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "org.jeffmikels.audiostream", binaryMessenger: registrar.messenger())
        let instance = SwiftAudiostreamPlugin()

        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
            case "getPlatformVersion":
                result("iOS " + UIDevice.current.systemVersion)
            case "initialize":
                doInitialize(call, result: result)
            case "write":
                doWrite(call.arguments as? FlutterStandardTypedData, result: result)
            case "close":
                doClose(result: result)
            default:
                result(FlutterMethodNotImplemented)
        }
    }

    func doInitialize(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        if let args = call.arguments as? Dictionary<String, Any> {
            let sampleRate = (args["rate"] as? Int) ?? 44100
            let channels = (args["channels"] as? Int) ?? 2

            audioStream.initialize(
                sampleRate: Double(sampleRate),
                sampleSizeInBytes: 2,
                numberOfChannels: channels
            )
            result(true)
        }
        result(false)
    }

    // Flutter sends data as PCM Array<Int16>
    func doWrite(_ audioData: FlutterStandardTypedData?, result: @escaping FlutterResult){
        if !audioStream.initialized {
            result("NOT INITIALIZED: You must call initialize first")
        } else {
            if audioData != nil {
                let realData = [UInt8](audioData!.data)
                audioStream.writeAll(realData)
                //result("\(audioData!.count) bytes written.")
                result(true)
            }
            //result("0 bytes written.")
            result(false)
        }
    }

    func doClose(result: @escaping FlutterResult){
        audioStream.close()
        result(true)
    }

}
