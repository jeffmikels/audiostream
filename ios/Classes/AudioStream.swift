// Much of this code comes from
// https://gist.github.com/hotpaw2/ba815fc23b5d642705f2b1dedfaf0107
// original copyright notice is here:
//
//  Created by Ronald Nicholson on 10/21/16.
//  Copyright © 2017,2019 HotPaw Productions. All rights reserved.
//  http://www.nicholson.com/rhn/
//  Distribution permission: BSD 2-clause license
//
// I came across it in the audio_recorder_mc package
//
//  McAudioRecorder.swift
//  audio_recorder_mc
//
//  Created by Diego Lopes on 23/04/2020.

import Foundation
import AVFoundation
import AudioUnit

extension Data {

    init<T>(from value: T) {
        self = Swift.withUnsafeBytes(of: value) { Data($0) }
    }

    func to<T>(type: T.Type) -> T? where T: ExpressibleByIntegerLiteral {
        var value: T = 0
        guard count >= MemoryLayout.size(ofValue: value) else { return nil }
        _ = Swift.withUnsafeMutableBytes(of: &value, { copyBytes(to: $0)} )
        return value
    }

    init<T>(fromArray values: [T]) {
        self = values.withUnsafeBytes { Data($0) }
    }

    func toArray<T>(type: T.Type) -> [T] where T: ExpressibleByIntegerLiteral {
        var array = Array<T>(repeating: 0, count: self.count/MemoryLayout<T>.stride)
        _ = array.withUnsafeMutableBytes { copyBytes(to: $0) }
        return array
    }
}

@available(iOS 9.0, *)
class AudioStream: NSObject {
    // GLOBAL AUDIO ENGINE OBJECTS
    private let audioEngine = AVAudioEngine()
    private var mixerNode: AVAudioMixerNode!
    private let playerNode: AVAudioPlayerNode! = AVAudioPlayerNode()

    private var audioFormatFromFlutter :AVAudioFormat!
    private var audioFormatForOutput :AVAudioFormat!
    private var formatFlags : AudioFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked
    
    
    private var receivedDataBuffer = RingBuffer<UInt8>(count: 1024)
    private var sessionActive          = false
    private var micPermission          = false
    private var micPermissionDispatchToken = 0

    private let outputBus: AVAudioNodeBus      = 0   // these can both be on the same bus
    private let inputBus: AVAudioNodeBus       = 0   // these can both be on the same bus
    
    var sampleRate : Double            = 44100.0     // default audio sample rate in FRAMES per second
    var sampleSizeInBytes : Int        = 2           // default to 16 bit audio
    var numberOfChannels: Int          = 1           // default to mono audio
    var bufferSizeInBytes : Int        = 3840        // frames * numberOfChannels * sampleSizeInBytes
    var bufferSizeInFrames: AVAudioFrameCount = 441
    var bufferSeconds: Double         = 0.02        // defaults to 20ms
    
    var numLocalBuffers: Int               = 2
    var localBuffers: [ AVAudioPCMBuffer ] = [ AVAudioPCMBuffer ]()
    var bufferIndex : Int                  = 0
    
//    private let audioQueue: OS_dispatch_queue_serial = DispatchQueue(label: "AudioStreamQueue" )
//    dispatch_queue_create("AudioStreamsQueue")
//    private let audioSemaphore: DispatchSemaphore
    

    var initialized                    = false
    var isPlaying                      = false
    var isHandlingBuffer               = false


    override init() {
        super.init();
        
//        audioSemaphore = DispatchSemaphore(value: maxLocalBuffers)
    }
    deinit { stopPlayer() }

    func initialize(
        sampleRate: Double     = 44100.0,
        sampleSizeInBytes: Int = 2,
        numberOfChannels: Int  = 2) {
        
        assert(sampleSizeInBytes == 2, "We only support 16 bit audio at the moment")

        self.sampleRate = sampleRate
        self.sampleSizeInBytes = sampleSizeInBytes
        self.numberOfChannels = numberOfChannels
        
        // Flutter sends audio as sampleRate, interleaved, two channel
        // However, this plugin only processes mono audio for now
        // we compensate by "faking" an audio format with twice the samplerate
        // but only one channel, and then everything works well enough
        // this has the effect of downmixing two channels to one
        audioFormatFromFlutter = AVAudioFormat(
            commonFormat: AVAudioCommonFormat.pcmFormatInt16,
            sampleRate: sampleRate * Double(numberOfChannels),
            channels: UInt32(1),
            interleaved: false)
//        audioFormatFromFlutter = AVAudioFormat(
//            commonFormat: AVAudioCommonFormat.pcmFormatInt16,
//            sampleRate: sampleRate,
//            channels: UInt32(numberOfChannels),
//            interleaved: true)
        
        
        // PREPARE LOCAL BUFFERS
        self.bufferSizeInFrames = UInt32(sampleRate * bufferSeconds) // each buffer holds 20ms of audio
        self.bufferSizeInBytes = Int(bufferSizeInFrames * audioFormatFromFlutter.streamDescription.pointee.mBytesPerFrame)
        
        receivedDataBuffer = RingBuffer<UInt8>(count: bufferSizeInBytes * 2)
        
        // setup the pcm buffers
//        for _ in 0..<numLocalBuffers {
//            let buf = AVAudioPCMBuffer(pcmFormat: audioFormatFromFlutter, frameCapacity: bufferSizeInFrames)!
//            localBuffers.append(buf)
//            bufferIndex = 0
//        }


        setupAudioSession()
        setupAudioEngine()
        audioFormatForOutput = audioEngine.outputNode.outputFormat(forBus: outputBus)
        
        initialized = true

        print("AudioStream Initialized -- Submitted")
        print("Sample Rate: \(self.sampleRate)")
        print("Sample Bytes: \(self.sampleSizeInBytes)")
        print("Channels: \(self.numberOfChannels)")
        
        print("AudioStream Initialized -- Computed")
        print("Buffer: \(self.bufferSizeInBytes) bytes")
        
        print("AudioStream Initialized -- audioFormatFromFlutter")
        print(audioFormatFromFlutter!)

        print("AudioStream Initialized -- audioFormatForOutput")
        print(audioFormatForOutput!)
    }
    
    /*
    func computeBufferSizes() {
        bufferDuration = Double(bufferedFrames) / sampleRate
        bufferSizeInSamples = bufferedFrames * numberOfChannels
        bufferSizeInBytes = bufferSizeInSamples * sampleSizeInBytes
        
        // the stored buffer should be able to hold twice as much
        // as our desired audio buffer
        outputAudioBuffer = RingBuffer<UInt8>(count: bufferSizeInBytes * 2)
    }
    */


    // input comes from flutter as Array<UInt8>
    func writeAll(_ values: [UInt8]) {
        print("received \(values.count) bytes")
        for val in values {
            receivedDataBuffer.write(val)
        }
        checkBuffer()
    }

    func checkBuffer() {
        if receivedDataBuffer.count > bufferSizeInBytes {
            if !isPlaying { startPlayer() }
            playBuffer()
        }
    }

    func playBuffer() {
        if isHandlingBuffer { return }
        isHandlingBuffer = true;
        
        while receivedDataBuffer.count >= bufferSizeInBytes {
//            let audioBuffer = localBuffers[bufferIndex]
//            bufferIndex = (bufferIndex + 1) % localBuffers.count

            
            // grab up to a full "buffer" amount of samples from the buffer
            // print("Preparing a new Audio Buffer")
            let bufferBytes = receivedDataBuffer.read(count: bufferSizeInBytes, allowShort: true)
            // let bufferData = Data(bytes: bufferBytes, count: bufferBytes.count)
            
            let audioBuffer = bytesToAudioBuffer(bufferBytes) // assumes Int16 audio
            
            // set up an audio buffer for this length of samples
            /*
            let frameCount = UInt32(bufferBytes.count) / audioFormatFromFlutter.streamDescription.pointee.mBytesPerFrame
            let audioBuffer = AVAudioPCMBuffer(
                pcmFormat: audioFormatFromFlutter,
                frameCapacity: frameCount)!
            audioBuffer.frameLength = frameCount // tell the buffer how many frames we have
            
            print("BYTES:    \(bufferBytes.count)")
            print("FRAMES:   \(frameCount)")
            print("CHANNELS: \(audioBuffer.stride)")
            
            
            
            // point the audioBuffer's data pointer to the values data
            switch audioFormatFromFlutter.commonFormat {
                case AVAudioCommonFormat.pcmFormatFloat32:
                    // fill the buffer with float32 samples assuming interleaved channel data
                    /*
                    let values = bufferData.toArray(type: Float32.self)
                    for i in 0..<numberOfChannels {
                        var channelSamples = [ Float32 ]()
                        for frame in 0..<Int(frameCount) {
                            let index = frame * numberOfChannels + i
                            channelSamples.append(values[index])
                        }
                        memcpy(
                            audioBuffer.floatChannelData![i],
                            channelSamples,
                            channelSamples.count)
                    }
                    */
                    let dstLeft = audioBuffer.floatChannelData![0]
                    bufferBytes.withUnsafeBufferPointer {
                        let src = UnsafeRawPointer($0.baseAddress!).bindMemory(
                            to: Float32.self, capacity: Int(frameCount))
                        dstLeft.initialize(from: src, count: Int(frameCount))
                    }
                    
                    
                //case AVAudioCommonFormat.pcmFormatInt16:
                default:
                    // fill the buffer with int16 samples considering channel data
                    /*
                    let values = bufferData.toArray(type: Int16.self)
                    print(values.count)
                    for i in 0..<numberOfChannels {
                        var channelSamples = [ Int16 ]()
                        for frame in 0..<Int(frameCount) {
                            let index = frame * numberOfChannels + i
                            print(index)
                            channelSamples.append(values[index])
                        }
                        memcpy(
                            audioBuffer.int16ChannelData![i],
                            channelSamples,
                            channelSamples.count)
                    }
                    */
                    let dstLeft = audioBuffer.int16ChannelData![0]
                    bufferBytes.withUnsafeBufferPointer {
                        let src = UnsafeRawPointer($0.baseAddress!).bindMemory(
                            to: Int16.self, capacity: Int(frameCount))
                        dstLeft.initialize(from: src, count: Int(frameCount))
                    }
            }
            */
            
            // create a converter to go from our audio to the device output audio
            let sourceFormat = audioFormatFromFlutter!
            let targetFormat = audioFormatForOutput!
            let formatConverter = AVAudioConverter(from: sourceFormat, to: targetFormat)
            let ratio: Float = Float(sourceFormat.sampleRate)/Float(targetFormat.sampleRate)
            let outFrameCapacity = UInt32(Float(audioBuffer.frameCapacity) / ratio)
            let pcmBuffer = AVAudioPCMBuffer(
                pcmFormat: targetFormat,
                frameCapacity: outFrameCapacity)!

            var error: NSError? = nil
            let inputBlock: AVAudioConverterInputBlock = {inNumPackets, outStatus in
                outStatus.pointee = .haveData
                return audioBuffer
            }
            formatConverter?.convert(to: pcmBuffer, error: &error, withInputFrom: inputBlock)
            playerNode.scheduleBuffer(pcmBuffer) { print("player finished") } // play as soon as possible
            print("scheduled audio")
            print(sourceFormat)
            print(targetFormat)
        }
        isHandlingBuffer = false;
    }
    
    func setupAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try! session.setCategory(AVAudioSession.Category.playAndRecord, options: AVAudioSession.CategoryOptions.allowBluetooth)
//        try! session.setPreferredSampleRate(sampleRate)
//        try! session.setPreferredIOBufferDuration(0.005)
        sessionActive = true;
    }
    
    func setupAudioEngine() {
        if audioEngine.isRunning { return }
        
        print("Starting audioEngine")
        mixerNode = audioEngine.mainMixerNode
        // let outputNode = audioEngine.outputNode
        // mixerNode.outputVolume = 1
        
        // Player Node Settings
        audioEngine.attach(playerNode)
        audioEngine.connect(playerNode, to: mixerNode, format: mixerNode.outputFormat(forBus: outputBus))
        // audioEngine.connect(mixerNode, to: outputNode, format: outputNode.outputFormat(forBus: outputBus))
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            print("Could not start audioEngine")
        }
    }
    
    func startPlayer() {
        print("Starting audio player with this format:")
        print(audioFormatFromFlutter ?? "none")
        playerNode.play()
        isPlaying = true
    }
    
    func close() {
        stopPlayer()
    }
    
    func stopPlayer() {
        playerNode.stop();
        audioEngine.stop();
        audioEngine.reset();
        isPlaying = false
    }
    
    // copied from the sound_stream plugin, but modified to handle multiple channel interleaved audio
    private func bytesToAudioBuffer(_ buf: [UInt8]) -> AVAudioPCMBuffer {
        let bytesPerFrame = Int(audioFormatFromFlutter.streamDescription.pointee.mBytesPerFrame)
        let bytesPerChannel = bytesPerFrame / Int(audioFormatFromFlutter.channelCount)
        let frameCount = UInt32(buf.count / bytesPerFrame)
        let audioBuffer = AVAudioPCMBuffer(pcmFormat: audioFormatFromFlutter, frameCapacity: frameCount)!
        
        var channelBytes = [ Data ]()
        // if there are multiple channels, we need to split them into two arrays
        // this assumes the channels are interleaved
        
        if audioFormatFromFlutter.channelCount > 1 {
            for _ in 0..<Int(audioFormatFromFlutter.channelCount) {
                channelBytes.append(Data())
            }
            for frameNumber in 0..<Int(frameCount) {
                for cid in 0..<Int(audioFormatFromFlutter.channelCount) {
                    for i in 0..<bytesPerChannel {
                        let index = frameNumber * Int(bytesPerFrame) + (cid * bytesPerChannel) + i
                        channelBytes[cid].append(buf[index])
                    }
                }
            }
        } else {
            channelBytes.append(Data(buf))
        }
        
        for cid in 0..<Int(audioFormatFromFlutter.channelCount) {
            let channel = audioBuffer.int16ChannelData![cid]
            channelBytes[cid].withUnsafeBytes {
                let src = UnsafeRawPointer($0.baseAddress!).bindMemory(
                    to: Int16.self, capacity: Int(frameCount))
                channel.initialize(from: src, count: Int(frameCount))
            }
        }
        audioBuffer.frameLength = frameCount
        return audioBuffer
    }
}

public struct RingBuffer<T> {
    private var array: [T?]
    private var readIndex = 0
    private var writeIndex = 0

    public init(count: Int) {
        array = [T?](repeating: nil, count: count)
    }

    /* Returns false if out of space. */
    @discardableResult public mutating func write(_ element: T) -> Bool {
        if !isFull {
            array[writeIndex % array.count] = element
            writeIndex += 1
            return true
        } else {
            return false
        }
    }

    /* Returns nil if the buffer is empty. */
    public mutating func read() -> T? {
        if !isEmpty {
            let element = array[readIndex % array.count]
            readIndex += 1
            return element
        } else {
            return nil
        }
    }
    
    public mutating func read(count: Int, allowShort: Bool = false) -> [T] {
        assert(count < availableSpaceForReading || allowShort)
        
        var retval = [T]()
        for _ in 0..<count {
            let el = read();
            if el == nil { return retval }
            retval.append(el!)
        }
        return retval
    }

    public mutating func readAll() -> [T] {
        var retval = [T]()
        for _ in 0..<availableSpaceForReading {
            retval.append(read()!)
        }
        return retval
    }

    
    fileprivate var availableSpaceForReading: Int {
        return writeIndex - readIndex
    }

    fileprivate var availableSpaceForWriting: Int {
        return array.count - availableSpaceForReading
    }

    public var isEmpty: Bool {
        return availableSpaceForReading == 0
    }

    public var isFull: Bool {
        return availableSpaceForWriting == 0
    }
    
    public var count: Int {
        return availableSpaceForReading
    }
}
