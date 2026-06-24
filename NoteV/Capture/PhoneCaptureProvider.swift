import Foundation
@preconcurrency import AVFoundation
import UIKit

// MARK: - PhoneCaptureProvider

/// Captures frames and audio from the iPhone's camera and microphone.
/// Uses AVCaptureSession for video + mic audio (16kHz mono PCM for STT, muxed into MP4).
final class PhoneCaptureProvider: NSObject, CaptureProvider {

    // MARK: - Properties

    private let captureSession = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()
    private let videoQueue = DispatchQueue(label: "com.notev.videoQueue", qos: .userInitiated)
    private let audioQueue = DispatchQueue(label: "com.notev.audioQueue", qos: .userInitiated)

    var videoRecorder: VideoRecorder?
    var visualSampleProcessor: VisualSampleProcessor?

    private var audioContinuation: AsyncStream<AudioChunk>.Continuation?

    private var acceptingSamples = true

    // Photo capture completion handler
    private var photoContinuation: CheckedContinuation<Data, Error>?

    // STT audio conversion (reused across buffers)
    private var audioConverter: AVAudioConverter?
    private var audioTargetFormat: AVAudioFormat?

    private(set) var isAvailable: Bool = true

    var frameStream: AsyncStream<TimestampedFrame> {
        visualSampleProcessor?.frameStream ?? AsyncStream { $0.finish() }
    }

    lazy var audioStream: AsyncStream<AudioChunk> = {
        AsyncStream { continuation in
            self.audioContinuation = continuation
        }
    }()

    // MARK: - Init

    override init() {
        super.init()
        NSLog("[PhoneCaptureProvider] Initialized — iPhone camera fallback mode")
        configureCaptureSession()
    }

    // MARK: - Configuration

    private func configureCaptureSession() {
        captureSession.beginConfiguration()
        captureSession.sessionPreset = NoteVConfig.Video.phoneSessionPreset

        // Video input — back camera
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let videoInput = try? AVCaptureDeviceInput(device: camera) else {
            NSLog("[PhoneCaptureProvider] ERROR: Could not configure back camera")
            isAvailable = false
            captureSession.commitConfiguration()
            return
        }

        if captureSession.canAddInput(videoInput) {
            captureSession.addInput(videoInput)
        }

        configureCameraFrameRate(videoInput.device)

        // Microphone input — shared with MP4 mux and STT
        if let microphone = AVCaptureDevice.default(for: .audio),
           let micInput = try? AVCaptureDeviceInput(device: microphone),
           captureSession.canAddInput(micInput) {
            captureSession.addInput(micInput)
        } else {
            NSLog("[PhoneCaptureProvider] WARNING: Could not configure microphone input")
        }

        // Video output — BGRA for easy conversion
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoOutput.alwaysDiscardsLateVideoFrames = false
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)

        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }

        // Lock video orientation to portrait so pixel buffers arrive upright
        if let connection = videoOutput.connection(with: .video) {
            connection.videoOrientation = .portrait
        }

        // Photo output — for bookmark high-res capture
        if captureSession.canAddOutput(photoOutput) {
            captureSession.addOutput(photoOutput)
        }

        // Also lock photo output to portrait
        if let photoConnection = photoOutput.connection(with: .video) {
            photoConnection.videoOrientation = .portrait
        }

        audioOutput.setSampleBufferDelegate(self, queue: audioQueue)
        if captureSession.canAddOutput(audioOutput) {
            captureSession.addOutput(audioOutput)
        }

        captureSession.commitConfiguration()
        NSLog("[PhoneCaptureProvider] AVCaptureSession configured — camera + photo + audio output ready")
    }

    private func configureCameraFrameRate(_ device: AVCaptureDevice) {
        let fps = NoteVConfig.Video.targetFrameRate
        let frameDuration = CMTime(value: 1, timescale: fps)
        do {
            try device.lockForConfiguration()
            device.activeVideoMinFrameDuration = frameDuration
            device.activeVideoMaxFrameDuration = frameDuration
            device.unlockForConfiguration()
            NSLog("[PhoneCaptureProvider] Camera locked to \(fps) fps")
        } catch {
            NSLog("[PhoneCaptureProvider] WARNING: Could not set \(fps) fps — \(error.localizedDescription)")
        }
    }

    // MARK: - Audio Configuration

    private func configureAudioSession() throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothA2DP])
        try audioSession.setActive(true)
    }

    private func prepareAudioConverter(for sampleBuffer: CMSampleBuffer) -> Bool {
        guard audioConverter == nil else { return true }

        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else {
            return false
        }

        let sourceFormat = AVAudioFormat(cmAudioFormatDescription: formatDescription)
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Double(NoteVConfig.Audio.sampleRate),
            channels: AVAudioChannelCount(NoteVConfig.Audio.channels),
            interleaved: true
        ) else {
            return false
        }

        guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
            return false
        }

        audioConverter = converter
        audioTargetFormat = targetFormat
        return true
    }

    private func makeAudioChunk(from sampleBuffer: CMSampleBuffer, timestamp: TimeInterval) -> AudioChunk? {
        guard prepareAudioConverter(for: sampleBuffer),
              let converter = audioConverter,
              let targetFormat = audioTargetFormat else {
            return nil
        }

        guard let sourceBuffer = makePCMBuffer(from: sampleBuffer) else { return nil }

        let frameCount = AVAudioFrameCount(
            Double(sourceBuffer.frameLength) * targetFormat.sampleRate / sourceBuffer.format.sampleRate
        )
        guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCount) else {
            return nil
        }

        var error: NSError?
        let status = converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return sourceBuffer
        }

        guard status != .error, error == nil else {
            NSLog("[PhoneCaptureProvider] Audio conversion error: \(error?.localizedDescription ?? "unknown")")
            return nil
        }

        guard let channelData = convertedBuffer.int16ChannelData else { return nil }
        let byteCount = Int(convertedBuffer.frameLength) * 2
        let data = Data(bytes: channelData[0], count: byteCount)
        let duration = Double(convertedBuffer.frameLength) / targetFormat.sampleRate

        return AudioChunk(timestamp: timestamp, data: data, duration: duration)
    }

    private func makePCMBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else { return nil }
        let format = AVAudioFormat(cmAudioFormatDescription: formatDescription)

        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return nil }
        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else {
            return nil
        }

        pcmBuffer.frameLength = AVAudioFrameCount(frameCount)

        var length = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        guard CMBlockBufferGetDataPointer(
            blockBuffer,
            atOffset: 0,
            lengthAtOffsetOut: nil,
            totalLengthOut: &length,
            dataPointerOut: &dataPointer
        ) == noErr,
              let dataPointer else {
            return nil
        }

        let audioBufferList = pcmBuffer.mutableAudioBufferList
        let audioBuffer = audioBufferList.pointee.mBuffers
        guard let destination = audioBuffer.mData else { return nil }
        memcpy(destination, dataPointer, min(length, Int(audioBuffer.mDataByteSize)))
        return pcmBuffer
    }

    // MARK: - CaptureProvider

    func startCapture() async throws {
        NSLog("[PhoneCaptureProvider] startCapture() called")
        acceptingSamples = true
        audioConverter = nil
        audioTargetFormat = nil
        visualSampleProcessor?.reset()

        _ = audioStream

        do {
            try configureAudioSession()
        } catch {
            NSLog("[PhoneCaptureProvider] ERROR configuring audio session: \(error.localizedDescription)")
            throw error
        }

        await performOnVideoQueue {
            self.captureSession.startRunning()
            NSLog("[PhoneCaptureProvider] AVCaptureSession started")
        }
    }

    func stopCapture() async {
        NSLog("[PhoneCaptureProvider] stopCapture() called")
        acceptingSamples = false

        await performOnVideoQueue {
            self.captureSession.stopRunning()
        }

        visualSampleProcessor?.finishFrames()
        audioContinuation?.finish()

        audioConverter = nil
        audioTargetFormat = nil
        NSLog("[PhoneCaptureProvider] Capture stopped")
    }

    func capturePhoto() async throws -> Data {
        NSLog("[PhoneCaptureProvider] capturePhoto() called")

        guard photoContinuation == nil else {
            throw NSError(domain: "PhoneCaptureProvider", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "Photo capture already in progress"])
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.photoContinuation = continuation
            let settings = AVCapturePhotoSettings()
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    // MARK: - Helpers

    private func performOnVideoQueue(_ work: @escaping () -> Void) async {
        await withCheckedContinuation { continuation in
            videoQueue.async {
                work()
                continuation.resume()
            }
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension PhoneCaptureProvider: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard acceptingSamples else { return }

        if output === videoOutput {
            visualSampleProcessor?.processVideoSample(sampleBuffer)
            return
        }

        if output === audioOutput {
            guard CMSampleBufferDataIsReady(sampleBuffer) else { return }

            let timestamp = visualSampleProcessor?.establishTimebaseIfNeeded(for: sampleBuffer) ?? 0
            videoRecorder?.appendAudio(sampleBuffer)

            if let chunk = makeAudioChunk(from: sampleBuffer, timestamp: timestamp) {
                audioContinuation?.yield(chunk)
            }
        }
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension PhoneCaptureProvider: AVCapturePhotoCaptureDelegate {
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        if let error = error {
            NSLog("[PhoneCaptureProvider] Photo capture error: \(error.localizedDescription)")
            photoContinuation?.resume(throwing: error)
            photoContinuation = nil
            return
        }

        guard let data = photo.fileDataRepresentation() else {
            NSLog("[PhoneCaptureProvider] ERROR: No photo data")
            photoContinuation?.resume(throwing: NSError(domain: "PhoneCaptureProvider", code: -1, userInfo: [NSLocalizedDescriptionKey: "No photo data"]))
            photoContinuation = nil
            return
        }

        NSLog("[PhoneCaptureProvider] Photo captured — \(data.count) bytes")
        photoContinuation?.resume(returning: data)
        photoContinuation = nil
    }
}
