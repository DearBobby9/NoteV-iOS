import Foundation
@preconcurrency import AVFoundation
import UIKit

// MARK: - PhoneCaptureProvider

/// Captures frames and audio from the iPhone's camera and microphone.
/// Uses AVCaptureSession for video + AVAudioEngine for audio (16kHz mono PCM).
final class PhoneCaptureProvider: NSObject, CaptureProvider {

    // MARK: - Properties

    private let captureSession = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let videoQueue = DispatchQueue(label: "com.notev.videoQueue", qos: .userInitiated)

    private let audioEngine = AVAudioEngine()

    private var frameContinuation: AsyncStream<TimestampedFrame>.Continuation?
    private var audioContinuation: AsyncStream<AudioChunk>.Continuation?

    private var sessionStartTime: Date?
    private var frameIndex: Int = 0

    // Photo capture completion handler
    private var photoContinuation: CheckedContinuation<Data, Error>?

    private(set) var isAvailable: Bool = true

    lazy var frameStream: AsyncStream<TimestampedFrame> = {
        AsyncStream { continuation in
            self.frameContinuation = continuation
        }
    }()

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
        captureSession.sessionPreset = .medium

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

        // Video output — BGRA for easy conversion
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)

        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }

        // Photo output — for bookmark high-res capture
        if captureSession.canAddOutput(photoOutput) {
            captureSession.addOutput(photoOutput)
        }

        captureSession.commitConfiguration()
        NSLog("[PhoneCaptureProvider] AVCaptureSession configured — camera + photo output ready")
    }

    // MARK: - Audio Configuration

    private func configureAudioEngine() throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothA2DP])
        try audioSession.setActive(true)

        let inputNode = audioEngine.inputNode
        let hardwareFormat = inputNode.outputFormat(forBus: 0)

        // Target format: 16kHz mono Int16 PCM
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Double(NoteVConfig.Audio.sampleRate),
            channels: AVAudioChannelCount(NoteVConfig.Audio.channels),
            interleaved: true
        ) else {
            NSLog("[PhoneCaptureProvider] ERROR: Could not create target audio format")
            return
        }

        // Install converter if sample rates differ
        guard let converter = AVAudioConverter(from: hardwareFormat, to: targetFormat) else {
            NSLog("[PhoneCaptureProvider] ERROR: Could not create audio converter")
            return
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: hardwareFormat) { [weak self] buffer, time in
            guard let self = self else { return }

            // Convert to target format
            let frameCount = AVAudioFrameCount(Double(buffer.frameLength) * targetFormat.sampleRate / hardwareFormat.sampleRate)
            guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCount) else { return }

            var error: NSError?
            let status = converter.convert(to: convertedBuffer, error: &error) { inNumPackets, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            guard status != .error, error == nil else {
                NSLog("[PhoneCaptureProvider] Audio conversion error: \(error?.localizedDescription ?? "unknown")")
                return
            }

            // Extract PCM data
            guard let channelData = convertedBuffer.int16ChannelData else { return }
            let byteCount = Int(convertedBuffer.frameLength) * 2 // Int16 = 2 bytes
            let data = Data(bytes: channelData[0], count: byteCount)

            let timestamp = self.currentTimestamp()
            let duration = Double(convertedBuffer.frameLength) / targetFormat.sampleRate

            let chunk = AudioChunk(
                timestamp: timestamp,
                data: data,
                duration: duration
            )

            self.audioContinuation?.yield(chunk)
        }

        NSLog("[PhoneCaptureProvider] Audio engine configured — \(Int(hardwareFormat.sampleRate))Hz → \(NoteVConfig.Audio.sampleRate)Hz")
    }

    // MARK: - CaptureProvider

    func startCapture() async throws {
        NSLog("[PhoneCaptureProvider] startCapture() called")
        sessionStartTime = Date()
        frameIndex = 0

        // Start video capture on background queue
        videoQueue.async { [weak self] in
            self?.captureSession.startRunning()
            NSLog("[PhoneCaptureProvider] AVCaptureSession started")
        }

        // Start audio engine
        do {
            try configureAudioEngine()
            try audioEngine.start()
            NSLog("[PhoneCaptureProvider] AVAudioEngine started")
        } catch {
            NSLog("[PhoneCaptureProvider] ERROR starting audio engine: \(error.localizedDescription) — rolling back")
            // Rollback: dispatch stopRunning on videoQueue to guarantee it runs AFTER the
            // async startRunning that was already enqueued (otherwise startRunning fires later)
            videoQueue.async { [weak self] in
                self?.captureSession.stopRunning()
                NSLog("[PhoneCaptureProvider] Rollback: AVCaptureSession stopped")
            }
            // Remove audio tap if configureAudioEngine() installed it before the throw
            audioEngine.inputNode.removeTap(onBus: 0)
            sessionStartTime = nil
            throw error
        }
    }

    func stopCapture() async {
        NSLog("[PhoneCaptureProvider] stopCapture() called")

        captureSession.stopRunning()
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)

        frameContinuation?.finish()
        audioContinuation?.finish()

        sessionStartTime = nil
        NSLog("[PhoneCaptureProvider] Capture stopped — \(frameIndex) frames produced")
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

    private func currentTimestamp() -> TimeInterval {
        guard let start = sessionStartTime else { return 0 }
        return Date().timeIntervalSince(start)
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension PhoneCaptureProvider: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // Convert CMSampleBuffer → JPEG Data
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }

        let uiImage = UIImage(cgImage: cgImage)
        guard let jpegData = uiImage.jpegData(compressionQuality: NoteVConfig.Storage.jpegCompressionQuality) else { return }

        let timestamp = currentTimestamp()
        frameIndex += 1

        let filename = String(format: "frame_%04d.jpg", frameIndex)

        let frame = TimestampedFrame(
            timestamp: timestamp,
            trigger: .periodic,
            changeScore: 0.0,
            imageFilename: filename,
            imageData: jpegData
        )

        frameContinuation?.yield(frame)
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
