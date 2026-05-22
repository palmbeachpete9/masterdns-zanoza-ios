import Foundation

#if os(iOS)
import AVFoundation
import UIKit

public enum BackgroundRuntimeKeeperError: LocalizedError {
    case audioFormatUnavailable
    case audioBufferUnavailable

    public var errorDescription: String? {
        switch self {
        case .audioFormatUnavailable: "Unable to create background audio format."
        case .audioBufferUnavailable: "Unable to create background audio buffer."
        }
    }
}

// Keeps the process alive in the background by rendering a 1-second silent
// PCM buffer on loop through AVAudioEngine. Requires UIBackgroundModes=audio.
@MainActor
public final class BackgroundRuntimeKeeper {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var didAttachPlayer = false
    private var isRunning = false
    private var loopBuffer: AVAudioPCMBuffer?
    private var interruptionObserver: NSObjectProtocol?
    private var routeChangeObserver: NSObjectProtocol?

    public init() {}

    public func start() throws {
        guard !isRunning else { return }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try session.setActive(true)

        let format = try makeAudioFormat()
        try configureGraph(format: format)
        guard let loopBuffer else { throw BackgroundRuntimeKeeperError.audioBufferUnavailable }

        player.scheduleBuffer(loopBuffer, at: nil, options: .loops)
        try engine.start()
        player.play()
        installObservers()
        isRunning = true
    }

    public func stop() {
        guard isRunning else { return }
        player.stop()
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        removeObservers()
        isRunning = false
    }

    private func makeAudioFormat() throws -> AVAudioFormat {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1) else {
            throw BackgroundRuntimeKeeperError.audioFormatUnavailable
        }
        return format
    }

    private func configureGraph(format: AVAudioFormat) throws {
        if !didAttachPlayer {
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            didAttachPlayer = true
        }
        if loopBuffer == nil {
            loopBuffer = try makeSilentLoopBuffer(format: format)
        }
    }

    private func makeSilentLoopBuffer(format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        let frameCount = AVAudioFrameCount(format.sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw BackgroundRuntimeKeeperError.audioBufferUnavailable
        }
        buffer.frameLength = frameCount
        return buffer
    }

    private func installObservers() {
        let center = NotificationCenter.default
        interruptionObserver = center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] note in
            Task { @MainActor [weak self] in
                self?.handleInterruption(note)
            }
        }
        routeChangeObserver = center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.resumePlaybackIfNeeded()
            }
        }
    }

    private func removeObservers() {
        let center = NotificationCenter.default
        if let observer = interruptionObserver { center.removeObserver(observer) }
        if let observer = routeChangeObserver { center.removeObserver(observer) }
        interruptionObserver = nil
        routeChangeObserver = nil
    }

    private func handleInterruption(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        switch type {
        case .began:
            // System will pause us; nothing to do.
            break
        case .ended:
            resumePlaybackIfNeeded()
        @unknown default:
            break
        }
    }

    private func resumePlaybackIfNeeded() {
        guard isRunning else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            if !engine.isRunning {
                try engine.start()
            }
            if !player.isPlaying {
                player.play()
            }
        } catch {
            // Best effort resume; failures are logged via the engine elsewhere.
        }
    }
}
#endif
