import Foundation
import MWDATCore
import MWDATCamera
@preconcurrency import AVFoundation
import UIKit

// MARK: - GlassesCaptureProvider

/// Captures frames and audio from Meta Ray-Ban smart glasses via the DAT SDK.
/// Video: StreamSession → videoFramePublisher → throttle → JPEG → TimestampedFrame.
/// Audio: Glasses mic routes through Bluetooth HFP → AVAudioEngine tap → 16kHz mono PCM → AudioChunk.
/// Photo: streamSession.capturePhoto() → photoDataPublisher callback.
///
/// @MainActor because StreamSession and its publishers are MainActor-isolated.
@MainActor
final class GlassesCaptureProvider: CaptureProvider {

    // MARK: - Properties

    private let wearables: WearablesInterface
    private let deviceSelector: AutoDeviceSelector
    private var streamSession: StreamSession

    // DAT SDK listener tokens — MUST retain, nil = subscription canceled
    private var stateListenerToken: AnyListenerToken?
    private var videoFrameListenerToken: AnyListenerToken?
    private var errorListenerToken: AnyListenerToken?
    private var photoDataListenerToken: AnyListenerToken?
    private var deviceMonitorTask: Task<Void, Never>?

    // Audio (glasses mic via Bluetooth HFP, not DAT SDK)
    private let audioEngine = AVAudioEngine()

    // Frame throttle — only encode 1 frame per samplingInterval (checked on MainActor, ~24 comparisons/sec)
    private var lastYieldTime: TimeInterval = -999
    private var samplingInterval: TimeInterval = NoteVConfig.Frame.periodicSamplingInterval

    // Session state
    private var sessionStartTime: Date?
    private var frameIndex: Int = 0
    private var isStreaming = false

    // Photo capture async continuation
    private var photoContinuation: CheckedContinuation<Data, Error>?

    // AsyncStream continuations
    private var frameContinuation: AsyncStream<TimestampedFrame>.Continuation?
    private var audioContinuation: AsyncStream<AudioChunk>.Continuation?

    private(set) var isAvailable: Bool = false

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

    init(wearables: WearablesInterface = Wearables.shared) {
        self.wearables = wearables
        self.deviceSelector = AutoDeviceSelector(wearables: wearables)

        let config = StreamSessionConfig(
            videoCodec: VideoCodec.raw,
            resolution: StreamingResolution.high,
            frameRate: 2
        )
        self.streamSession = StreamSession(
            streamSessionConfig: config,
            deviceSelector: deviceSelector
        )

        NSLog("[GlassesCaptureProvider] Initialized — monitoring device availability")

        // Monitor device availability
        deviceMonitorTask = Task { [weak self, deviceSelector] in
            for await device in deviceSelector.activeDeviceStream() {
                self?.isAvailable = device != nil
                NSLog("[GlassesCaptureProvider] Device availability changed: \(device != nil)")
            }
        }

        attachListeners()
    }

    // MARK: - Listeners

    private func attachListeners() {
        // Session state changes
        stateListenerToken = streamSession.statePublisher.listen { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch state {
                case .streaming:
                    self.isStreaming = true
                    NSLog("[GlassesCaptureProvider] StreamSession state: streaming")
                case .stopped:
                    self.isStreaming = false
                    NSLog("[GlassesCaptureProvider] StreamSession state: stopped")
                case .waitingForDevice:
                    NSLog("[GlassesCaptureProvider] StreamSession state: waitingForDevice")
                case .starting:
                    NSLog("[GlassesCaptureProvider] StreamSession state: starting")
                case .stopping:
                    NSLog("[GlassesCaptureProvider] StreamSession state: stopping")
                case .paused:
                    NSLog("[GlassesCaptureProvider] StreamSession state: paused")
                }
            }
        }

        // Video frames — throttle on MainActor (24 comparisons/sec, encode only ~12/min at 5s interval)
        videoFrameListenerToken = streamSession.videoFramePublisher.listen { [weak self] videoFrame in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let now = self.currentTimestamp()
                guard now - self.lastYieldTime >= self.samplingInterval else { return }
                self.lastYieldTime = now

                guard let uiImage = videoFrame.makeUIImage(),
                      let jpegData = uiImage.jpegData(compressionQuality: NoteVConfig.Storage.jpegCompressionQuality) else {
                    return
                }

                self.frameIndex += 1
                let filename = String(format: "frame_%04d.jpg", self.frameIndex)

                let frame = TimestampedFrame(
                    timestamp: now,
                    trigger: .periodic,
                    changeScore: 0.0,
                    imageFilename: filename,
                    imageData: jpegData
                )

                self.frameContinuation?.yield(frame)
            }
        }

        // Errors — suppress device-not-found when not streaming
        errorListenerToken = streamSession.errorPublisher.listen { [weak self] error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if !self.isStreaming {
                    if case .deviceNotConnected = error { return }
                    if case .deviceNotFound = error { return }
                }
                NSLog("[GlassesCaptureProvider] StreamSession error: \(error)")
            }
        }

        // Photo capture results
        photoDataListenerToken = streamSession.photoDataPublisher.listen { [weak self] photoData in
            Task { @MainActor [weak self] in
                guard let self else { return }
                NSLog("[GlassesCaptureProvider] Photo captured — \(photoData.data.count) bytes")
                self.photoContinuation?.resume(returning: photoData.data)
                self.photoContinuation = nil
            }
        }
    }

    // MARK: - CaptureProvider

    /// Update the sampling interval dynamically (called by FramePipeline for burst mode).
    /// nonisolated because FramePipeline calls this from a non-MainActor context.
    nonisolated func setSamplingInterval(_ interval: TimeInterval) {
        Task { @MainActor [weak self] in
            self?.samplingInterval = interval
            NSLog("[GlassesCaptureProvider] Sampling interval set to \(String(format: "%.1f", interval))s")
        }
    }

    func startCapture() async throws {
        NSLog("[GlassesCaptureProvider] startCapture() called")

        // Force lazy stream init so continuations are set before configureAudioEngine()
        // captures them. Without this, audioContinuation is nil when installTap runs.
        _ = self.audioStream
        _ = self.frameStream

        // Check/request camera permission via DAT SDK
        do {
            let status = try await wearables.checkPermissionStatus(.camera)
            if status != .granted {
                let requestStatus = try await wearables.requestPermission(.camera)
                if requestStatus != .granted {
                    throw NSError(domain: "GlassesCaptureProvider", code: -3,
                                  userInfo: [NSLocalizedDescriptionKey: "Camera permission denied on glasses"])
                }
            }
        } catch {
            NSLog("[GlassesCaptureProvider] Permission error: \(error.localizedDescription)")
            throw error
        }

        // Reset state
        sessionStartTime = Date()
        frameIndex = 0
        lastYieldTime = -999
        samplingInterval = NoteVConfig.Frame.periodicSamplingInterval

        // Start video streaming
        await streamSession.start()
        NSLog("[GlassesCaptureProvider] StreamSession started")

        // Configure audio for glasses (Bluetooth HFP, not A2DP)
        do {
            try configureAudioEngine()
            try audioEngine.start()
            NSLog("[GlassesCaptureProvider] AVAudioEngine started — glasses mic via Bluetooth")
        } catch {
            NSLog("[GlassesCaptureProvider] ERROR starting audio: \(error.localizedDescription) — rolling back stream")
            await streamSession.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
            sessionStartTime = nil
            throw error
        }
    }

    func stopCapture() async {
        NSLog("[GlassesCaptureProvider] stopCapture() called")

        await streamSession.stop()

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)

        frameContinuation?.finish()
        audioContinuation?.finish()

        // Clean up pending photo continuation
        photoContinuation?.resume(throwing: NSError(domain: "GlassesCaptureProvider", code: -4,
                                                     userInfo: [NSLocalizedDescriptionKey: "Capture stopped during photo"]))
        photoContinuation = nil

        sessionStartTime = nil
        NSLog("[GlassesCaptureProvider] Capture stopped — \(frameIndex) frames produced")
    }

    func capturePhoto() async throws -> Data {
        NSLog("[GlassesCaptureProvider] capturePhoto() called")

        guard photoContinuation == nil else {
            throw NSError(domain: "GlassesCaptureProvider", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "Photo capture already in progress"])
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.photoContinuation = continuation
            _ = streamSession.capturePhoto(format: .jpeg)
        }
    }

    // MARK: - Audio Configuration

    private func configureAudioEngine() throws {
        let audioSession = AVAudioSession.sharedInstance()
        // Glasses mode: .videoChat for mild AEC (mic on glasses, speaker on phone)
        // .allowBluetoothHFP routes glasses 5-mic array via Bluetooth HFP
        try audioSession.setCategory(.playAndRecord, mode: .videoChat, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try audioSession.setActive(true)

        let inputNode = audioEngine.inputNode
        let hardwareFormat = inputNode.outputFormat(forBus: 0)

        NSLog("[GlassesCaptureProvider] Audio hardware format: \(Int(hardwareFormat.sampleRate))Hz, \(hardwareFormat.channelCount)ch")

        // Target: 16kHz mono Int16 PCM (same as PhoneCaptureProvider)
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Double(NoteVConfig.Audio.sampleRate),
            channels: AVAudioChannelCount(NoteVConfig.Audio.channels),
            interleaved: true
        ) else {
            NSLog("[GlassesCaptureProvider] ERROR: Could not create target audio format")
            throw NSError(domain: "GlassesCaptureProvider", code: -5,
                          userInfo: [NSLocalizedDescriptionKey: "Could not create target audio format"])
        }

        guard let converter = AVAudioConverter(from: hardwareFormat, to: targetFormat) else {
            NSLog("[GlassesCaptureProvider] ERROR: Could not create audio converter (\(Int(hardwareFormat.sampleRate))Hz → \(NoteVConfig.Audio.sampleRate)Hz)")
            throw NSError(domain: "GlassesCaptureProvider", code: -6,
                          userInfo: [NSLocalizedDescriptionKey: "Could not create audio converter"])
        }

        // Capture continuation reference for use in audio tap closure (runs off MainActor)
        let audioCont = self.audioContinuation

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: hardwareFormat) { [weak self] buffer, _ in
            let frameCount = AVAudioFrameCount(Double(buffer.frameLength) * targetFormat.sampleRate / hardwareFormat.sampleRate)
            guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCount) else { return }

            var error: NSError?
            let status = converter.convert(to: convertedBuffer, error: &error) { inNumPackets, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            guard status != .error, error == nil else {
                NSLog("[GlassesCaptureProvider] Audio conversion error: \(error?.localizedDescription ?? "unknown")")
                return
            }

            guard let channelData = convertedBuffer.int16ChannelData else { return }
            let byteCount = Int(convertedBuffer.frameLength) * 2
            let data = Data(bytes: channelData[0], count: byteCount)

            // Compute timestamp on audio thread (Date arithmetic is thread-safe)
            let timestamp: TimeInterval
            if let start = self?.sessionStartTime {
                timestamp = Date().timeIntervalSince(start)
            } else {
                timestamp = 0
            }
            let duration = Double(convertedBuffer.frameLength) / targetFormat.sampleRate

            let chunk = AudioChunk(
                timestamp: timestamp,
                data: data,
                duration: duration
            )

            // AsyncStream.Continuation.yield is thread-safe
            audioCont?.yield(chunk)
        }

        NSLog("[GlassesCaptureProvider] Audio engine configured — \(Int(hardwareFormat.sampleRate))Hz → \(NoteVConfig.Audio.sampleRate)Hz")
    }

    // MARK: - Helpers

    private func currentTimestamp() -> TimeInterval {
        guard let start = sessionStartTime else { return 0 }
        return Date().timeIntervalSince(start)
    }
}
