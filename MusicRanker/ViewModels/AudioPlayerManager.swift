import AVFoundation
import SwiftUI
import Combine

/// Manages audio playback of 30-second iTunes previews
@MainActor
final class AudioPlayerManager: ObservableObject {

    // MARK: - Published State

    @Published var currentTrack: iTunesTrack?
    @Published var isPlaying = false
    @Published var progress: Double = 0 // 0...1

    // MARK: - Private

    private var player: AVPlayer?
    private var endObserver: (any NSObjectProtocol)?
    private var progressObserver: Any?

    // MARK: - Playback Controls

    /// Play a track (or toggle pause if already playing this track)
    func play(track: iTunesTrack) {
        if currentTrack?.id == track.id {
            togglePause()
            return
        }
        guard let url = track.previewURL else { return }
        startPlayback(track: track, url: url)
    }

    /// Force play a track (always starts from beginning)
    func forcePlay(track: iTunesTrack) {
        guard let url = track.previewURL else { return }
        startPlayback(track: track, url: url)
    }

    /// Toggle pause/resume
    func togglePause() {
        guard player != nil else { return }
        if isPlaying {
            player?.pause()
            isPlaying = false
        } else {
            player?.play()
            isPlaying = true
        }
    }

    /// Stop playback entirely
    func stop() {
        cleanup()
        currentTrack = nil
        isPlaying = false
        progress = 0
    }

    /// Check if a specific track is currently playing
    func isCurrentlyPlaying(id: Int) -> Bool {
        currentTrack?.id == id && isPlaying
    }

    /// Check if a specific track is the current one (playing or paused)
    func isCurrent(id: Int) -> Bool {
        currentTrack?.id == id
    }

    // MARK: - Callback for end of playback

    var onTrackEnded: (() -> Void)?

    // MARK: - Private Methods

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {
            print("[Audio] Session error: \(error.localizedDescription)")
        }
    }

    private func cleanup() {
        if let observer = endObserver {
            NotificationCenter.default.removeObserver(observer)
            endObserver = nil
        }
        if let observer = progressObserver {
            player?.removeTimeObserver(observer)
            progressObserver = nil
        }
        player?.pause()
        player = nil
    }

    private func startPlayback(track: iTunesTrack, url: URL) {
        cleanup()
        configureAudioSession()

        let item = AVPlayerItem(url: url)
        let newPlayer = AVPlayer(playerItem: item)
        player = newPlayer
        newPlayer.play()

        currentTrack = track
        isPlaying = true
        progress = 0

        // Track progress
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        progressObserver = newPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self, let duration = newPlayer.currentItem?.duration else { return }
            let total = CMTimeGetSeconds(duration)
            let current = CMTimeGetSeconds(time)
            if total > 0 && total.isFinite {
                Task { @MainActor in
                    self.progress = current / total
                }
            }
        }

        // End of track
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isPlaying = false
                self?.progress = 0
                self?.onTrackEnded?()
            }
        }
    }

    deinit {
        if let observer = endObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
