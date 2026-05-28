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
//
// Robustness layers (defense in depth — iOS will silently pause our session
// whenever Spotify / Apple Music / YouTube start playing, and the
// `interruptionNotification` only fires reliably for "began", not for the
// transition where another app preempts the route):
//
//   1. AVAudioEngine + observers on .interruption & .routeChange — handles
//      the "graceful" interruption case efficiently (no polling).
//   2. A 5-second watchdog Timer that asks the engine / player whether
//      they are still running and re-asserts setActive(true) / engine.start()
//      / player.play() if not. 5 s is the upper bound for an undetected
//      preemption to last; cost ≈ one timer fire / 5 s.
//   3. We never call setActive(false) on stop — that releases our hold on
//      the audio session and can briefly clash with another app that is
//      currently playing. ImmortalizerJailed dropped the same line for the
//      same reason. Stop just stops our player; the silent session lingers
//      until the OS reaps it on app exit.
@MainActor
public final class BackgroundRuntimeKeeper {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var didAttachPlayer = false
    private var isRunning = false
    private var loopBuffer: AVAudioPCMBuffer?
    private var interruptionObserver: NSObjectProtocol?
    private var routeChangeObserver: NSObjectProtocol?
    private var watchdog: Timer?

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
        startWatchdog()
        isRunning = true
    }

    public func stop() {
        guard isRunning else { return }
        stopWatchdog()
        player.stop()
        engine.stop()
        // Intentionally NOT calling setActive(false) — see file header.
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

    private func startWatchdog() {
        stopWatchdog()
        // 5 s — long enough to cost essentially nothing battery-wise,
        // short enough to catch a silent preemption before the SOCKS
        // listener is reaped by the OS (usually ~30 s of audio silence
        // before iOS terminates the process).
        let timer = Timer(timeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.resumePlaybackIfNeeded()
            }
        }
        timer.tolerance = 1.0
        RunLoop.main.add(timer, forMode: .common)
        watchdog = timer
    }

    private func stopWatchdog() {
        watchdog?.invalidate()
        watchdog = nil
    }

    private func handleInterruption(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        switch type {
        case .began:
            break
        case .ended:
            resumePlaybackIfNeeded()
        @unknown default:
            break
        }
    }

    private func resumePlaybackIfNeeded() {
        guard isRunning else { return }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            if !engine.isRunning {
                try engine.start()
            }
            if !player.isPlaying {
                player.play()
            }
        } catch {
            // Best-effort resume; next watchdog tick will try again.
        }
    }
}
#endif
