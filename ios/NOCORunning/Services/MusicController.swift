import Foundation
import MediaPlayer
import Combine

@MainActor
final class MusicController: ObservableObject {
    @Published private(set) var title: String = "Musik"
    @Published private(set) var artist: String = "Systemwiedergabe"
    @Published private(set) var isPlaying: Bool = false

    private let player = MPMusicPlayerController.systemMusicPlayer
    private var observers: [NSObjectProtocol] = []

    init() {
        refresh()
        let playing = NotificationCenter.default.addObserver(
            forName: .MPMusicPlayerControllerPlaybackStateDidChange,
            object: player,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        let item = NotificationCenter.default.addObserver(
            forName: .MPMusicPlayerControllerNowPlayingItemDidChange,
            object: player,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        observers = [playing, item]
        player.beginGeneratingPlaybackNotifications()
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    func toggle() {
        if player.playbackState == .playing {
            player.pause()
        } else {
            player.play()
        }
        refresh()
        Haptics.light()
    }

    func next() {
        player.skipToNextItem()
        refresh()
        Haptics.light()
    }

    func previous() {
        player.skipToPreviousItem()
        refresh()
        Haptics.light()
    }

    private func refresh() {
        isPlaying = player.playbackState == .playing
        if let item = player.nowPlayingItem {
            title = item.title ?? "Unbekannter Titel"
            artist = item.artist ?? "Unbekannter Interpret"
        } else {
            title = "Musik"
            artist = "Apple Music / System"
        }
    }
}
