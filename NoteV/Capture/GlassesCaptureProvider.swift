import Foundation
import MWDATCore
import MWDATCamera
@preconcurrency import AVFoundation
import UIKit

// MARK: - GlassesCaptureProvider

/// Captures frames and audio from Meta Ray-Ban smart glasses via the DAT SDK.
/// Video: StreamSession → VisualSampleProcessor → MP4 + throttled JPEG frames.
/// Audio: Glasses mic routes through Bluetooth HFP → AVAudioEngine tap → 16kHz mono PCM → AudioChunk.
/// Note: Glasses audio timestamps use wall-clock (`Date`); video frames use PTS. Small drift is accepted in v1.
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

    // Session state
    private var sessionStartTime: Date?
    private var isStreaming = false

    // Photo capture async continuation
    private var photoContinuation: CheckedContinuation<Data, Error>?

    // AsyncStream continuations
    private var audioContinuation: AsyncStream<AudioChunk>.Continuation?

    private(set) var isAvailable: Bool = false

    var videoRecorder: VideoRecorder?
    var visualSampleProcessor: VisualSampleProcessor?

    /// Set in `startCapture()` so DAT callbacks can fan out samples without hopping to MainActor.
    private nonisolated(unsafe) var videoIngressProcessor: VisualSampleProcessor?

    var frameStream: AsyncStream<TimestampedFrame> {
        visualSampleProcessor?.frameStream ?? AsyncStream { $0.finish() }
    }

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
            frameRate: UInt(NoteVConfig.Video.glassesStreamFrameRate)
        )
        self.streamSession = StreamSession(
            streamSessionConfig: config,
            deviceSelector: deviceSelector
        )

        NSLog("[GlassesCaptureProvider] Initialized — monitoring device availability")

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

        videoFrameListenerToken = streamSession.videoFramePublisher.listen { [weak self] videoFrame in
            self?.videoIngressProcessor?.processVideoSample(videoFrame.sampleBuffer)
        }

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

    func startCapture() async throws {
        NSLog("[GlassesCaptureProvider] startCapture() called")

        _ = self.audioStream
        _ = self.frameStream

        guard visualSampleProcessor != nil else {
            throw NSError(
                domain: "GlassesCaptureProvider",
                code: -7,
                userInfo: [NSLocalizedDescriptionKey: "VisualSampleProcessor must be set before startCapture()"]
            )
        }

        visualSampleProcessor?.reset()
        videoIngressProcessor = visualSampleProcessor

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

        sessionStartTime = Date()

        await streamSession.start()
        NSLog("[GlassesCaptureProvider] StreamSession started")

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

        visualSampleProcessor?.finishFrames()
        videoIngressProcessor = nil
        audioContinuation?.finish()

        photoContinuation?.resume(throwing: NSError(domain: "GlassesCaptureProvider", code: -4,
                                                     userInfo: [NSLocalizedDescriptionKey: "Capture stopped during photo"]))
        photoContinuation = nil

        sessionStartTime = nil
        NSLog("[GlassesCaptureProvider] Capture stopped")
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
        try audioSession.setCategory(.playAndRecord, mode: .videoChat, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try audioSession.setActive(true)

        let inputNode = audioEngine.inputNode
        let hardwareFormat = inputNode.outputFormat(forBus: 0)

        NSLog("[GlassesCaptureProvider] Audio hardware format: \(Int(hardwareFormat.sampleRate))Hz, \(hardwareFormat.channelCount)ch")

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Double(NoteVConfig.Audio.sampleRate),
            channels: AVAudioChannelCount(NoteVConfig.Audio.channels),
            interleaved: true
        ) else {
            throw NSError(domain: "GlassesCaptureProvider", code: -5,
                          userInfo: [NSLocalizedDescriptionKey: "Could not create target audio format"])
        }

        guard let converter = AVAudioConverter(from: hardwareFormat, to: targetFormat) else {
            throw NSError(domain: "GlassesCaptureProvider", code: -6,
                          userInfo: [NSLocalizedDescriptionKey: "Could not create audio converter"])
        }

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

            // v1: wall-clock timestamps for glasses audio (video uses PTS via VisualSampleProcessor).
            let timestamp: TimeInterval
            if let start = self?.sessionStartTime {
                timestamp = Date().timeIntervalSince(start)
            } else {
                timestamp = 0
            }
            let duration = Double(convertedBuffer.frameLength) / targetFormat.sampleRate

            audioCont?.yield(AudioChunk(timestamp: timestamp, data: data, duration: duration))
        }

        NSLog("[GlassesCaptureProvider] Audio engine configured — \(Int(hardwareFormat.sampleRate))Hz → \(NoteVConfig.Audio.sampleRate)Hz")
    }
}
