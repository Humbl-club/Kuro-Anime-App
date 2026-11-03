import AVFoundation
import Foundation
import Observation

// MARK: - Song previews (owner item 7, 2026-11-03)
// Plays Apple's 30-second preview of a theme song (`ThemeSong.previewURL`, from a verified iTunes
// match) when the user taps ▶ on a detail page. Exactly one preview at a time: playing another song
// stops the first. Nothing is downloaded or stored: AVPlayer streams Apple's own URL (Apple receives
// the device's IP address and the request; Privacy Policy section "Song previews").
//
// Stops on: a second ▶ of the same song, another song, `stop()` / `stop(ifPlaying:)` from a view
// leaving the screen, the app entering the background, an audio interruption (call, Siri), the
// headphones being unplugged, and every account transition (`AccountScopedState`).
//
// Audio session decision (documented, one constant): category `.soloAmbient`.
//   - It honours the Ring/Silent switch: with the phone on silent a preview is not heard. A preview
//     is a short sample inside a browsing page, not media playback the user started in a player, so
//     it behaves like the app's other sounds instead of overriding silent mode (`.playback` would).
//   - It is not mixable: other audio (the user's music) pauses while a preview plays, and is told it
//     may resume (`.notifyOthersOnDeactivation`) when the preview stops.
//   - It never plays in the background (and the app declares no background audio mode).
//   The session is activated only when ▶ is tapped, never at launch.

/// What the audio engine reports about the item it was asked to play.
nonisolated enum SongPreviewEvent: Equatable, Sendable {
    /// Audio is ready / started.
    case started
    /// The preview played to its end.
    case finished
    /// The stream could not be played (network, format, refused).
    case failed
}

/// The audio engine behind `SongPreviewPlayer` (AVPlayer in the app, a fake in tests).
@MainActor
protocol SongPreviewEngine: AnyObject {
    /// Starts streaming `url` from the beginning, replacing anything playing. `onEvent` is delivered
    /// on the main actor for THIS item only.
    func play(_ url: URL, onEvent: @escaping @MainActor (SongPreviewEvent) -> Void)
    /// Stops and releases the current item (no further events for it).
    func stop()
}

/// The shared audio session, as the player uses it (AVAudioSession in the app, a fake in tests).
@MainActor
protocol SongPreviewAudioSession: AnyObject {
    func activateForPreview() throws
    func deactivateAfterPreview()
}

@MainActor
@Observable
final class SongPreviewPlayer: AccountScopedState {
    /// The player's visible state for one song id (`ThemeSong.id`).
    enum Phase: Equatable {
        case idle
        /// ▶ tapped, the stream is buffering.
        case loading(songID: String)
        case playing(songID: String)
        /// The last ▶ could not be played (the row may show a quiet retry state).
        case failed(songID: String)
    }

    private(set) var phase: Phase = .idle

    @ObservationIgnored private let engine: any SongPreviewEngine
    @ObservationIgnored private let audioSession: any SongPreviewAudioSession
    /// Ignores late events of an item that was already replaced or stopped.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []
    @ObservationIgnored private let notificationCenter: NotificationCenter

    init(engine: (any SongPreviewEngine)? = nil,
         audioSession: (any SongPreviewAudioSession)? = nil,
         notificationCenter: NotificationCenter = .default) {
        self.engine = engine ?? AVSongPreviewEngine()
        self.audioSession = audioSession ?? SystemSongPreviewAudioSession()
        self.notificationCenter = notificationCenter
        observeLifecycle()
    }

    // MARK: Reading

    /// The song currently loading or playing, if any.
    var activeSongID: String? {
        switch phase {
        case .loading(let id), .playing(let id): return id
        case .idle, .failed: return nil
        }
    }

    func isPlaying(_ song: ThemeSong) -> Bool { phase == .playing(songID: song.id) }
    func isLoading(_ song: ThemeSong) -> Bool { phase == .loading(songID: song.id) }
    func didFail(_ song: ThemeSong) -> Bool { phase == .failed(songID: song.id) }

    /// Whether ▶ can be offered for `song` (a verified Apple preview on an allowed host).
    nonisolated static func canPreview(_ song: ThemeSong) -> Bool { allowedPreviewURL(song) != nil }

    // MARK: Actions

    /// ▶ / ■ for one song: stops it when it is the active one, otherwise plays it (stopping any other).
    func toggle(_ song: ThemeSong) {
        if activeSongID == song.id {
            stop()
        } else {
            play(song)
        }
    }

    /// Plays `song`'s preview, replacing any other. Returns false (and changes nothing) when the song
    /// has no allowed preview URL.
    @discardableResult
    func play(_ song: ThemeSong) -> Bool {
        guard let url = Self.allowedPreviewURL(song) else { return false }
        generation += 1
        let token = generation
        engine.stop()
        do {
            try audioSession.activateForPreview()
        } catch {
            phase = .failed(songID: song.id)
            return true
        }
        phase = .loading(songID: song.id)
        engine.play(url) { [weak self] event in
            self?.handle(event, songID: song.id, token: token)
        }
        return true
    }

    /// Stops whatever is playing.
    func stop() {
        generation += 1
        let wasActive = activeSongID != nil
        engine.stop()
        phase = .idle
        if wasActive { audioSession.deactivateAfterPreview() }
    }

    /// Stops only when `songID` is the active song (a row leaving the screen must not stop another).
    func stop(ifPlaying songID: String) {
        guard activeSongID == songID || phase == .failed(songID: songID) else { return }
        stop()
    }

    // MARK: AccountScopedState

    func cancelAccountWork() { stop() }
    func clearPrivateState() { stop() }

    // MARK: Engine events

    private func handle(_ event: SongPreviewEvent, songID: String, token: Int) {
        guard token == generation else { return }
        switch event {
        case .started:
            if phase == .loading(songID: songID) { phase = .playing(songID: songID) }
        case .finished:
            generation += 1
            engine.stop()
            phase = .idle
            audioSession.deactivateAfterPreview()
        case .failed:
            generation += 1
            engine.stop()
            phase = .failed(songID: songID)
            audioSession.deactivateAfterPreview()
        }
    }

    /// The song's preview URL when it is https on Apple's preview hosts (checked again here; the
    /// server and the decoder already refuse anything else).
    nonisolated static func allowedPreviewURL(_ song: ThemeSong) -> URL? {
        guard let url = song.previewURL else { return nil }
        return AppleSongMatch.url(url.absoluteString, hosts: ["audio-ssl.itunes.apple.com"], suffix: ".mzstatic.com")
    }

    // MARK: Lifecycle

    /// `UIApplication.didEnterBackgroundNotification` by name, so this owner needs no UIKit import
    /// (KuroTests asserts the two are equal).
    nonisolated static let didEnterBackground = Notification.Name("UIApplicationDidEnterBackgroundNotification")

    private func observeLifecycle() {
        let names: [Notification.Name] = [
            Self.didEnterBackground,
            AVAudioSession.interruptionNotification,
        ]
        for name in names {
            observers.append(notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.stop() }
            })
        }
        observers.append(notificationCenter.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil,
                                                        queue: .main) { [weak self] note in
            let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt)
                .flatMap(AVAudioSession.RouteChangeReason.init(rawValue:))
            guard reason == .oldDeviceUnavailable else { return }
            MainActor.assumeIsolated { self?.stop() }
        })
    }
}

// MARK: - Localised copy

/// The attribution Apple asks for next to a preview (EN/DE through `KuroLocale`).
enum SongPreviewCopy {
    static var attribution: String {
        KuroLocale.text("Preview courtesy of Apple Music", "Vorschau mit freundlicher Genehmigung von Apple Music")
    }

    static var openInAppleMusic: String { KuroLocale.text("Open in Apple Music", "In Apple Music öffnen") }

    static func playLabel(_ song: ThemeSong) -> String {
        KuroLocale.text("Play preview of \(song.title)", "Hörprobe von \(song.title) abspielen")
    }

    static func stopLabel(_ song: ThemeSong) -> String {
        KuroLocale.text("Stop preview of \(song.title)", "Hörprobe von \(song.title) stoppen")
    }

    static var unavailable: String { KuroLocale.text("Preview unavailable", "Hörprobe nicht verfügbar") }
}

// MARK: - System implementations

/// AVPlayer streaming Apple's preview URL. Events are delivered only for the current item.
@MainActor
final class AVSongPreviewEngine: SongPreviewEngine {
    private var player: AVPlayer?
    private var observers: [any NSObjectProtocol] = []
    private var statusObservation: NSKeyValueObservation?
    private var itemToken = 0

    func play(_ url: URL, onEvent: @escaping @MainActor (SongPreviewEvent) -> Void) {
        stop()
        itemToken += 1
        let token = itemToken
        let item = AVPlayerItem(url: url)
        let deliver: @MainActor (SongPreviewEvent) -> Void = { [weak self] event in
            guard let self, self.itemToken == token else { return }
            onEvent(event)
        }
        observers.append(NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) { _ in
                MainActor.assumeIsolated { deliver(.finished) }
            })
        observers.append(NotificationCenter.default.addObserver(
            forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: item, queue: .main) { _ in
                MainActor.assumeIsolated { deliver(.failed) }
            })
        statusObservation = item.observe(\.status, options: [.new]) { item, _ in
            let status = item.status
            Task { @MainActor in
                switch status {
                case .readyToPlay: deliver(.started)
                case .failed: deliver(.failed)
                case .unknown: break
                @unknown default: break
                }
            }
        }
        let player = AVPlayer(playerItem: item)
        self.player = player
        player.play()
    }

    func stop() {
        itemToken += 1
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        statusObservation?.invalidate()
        statusObservation = nil
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
    }
}

/// The real audio session: `.soloAmbient` (see the decision at the top of this file).
@MainActor
final class SystemSongPreviewAudioSession: SongPreviewAudioSession {
    func activateForPreview() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.soloAmbient, mode: .default)
        try session.setActive(true)
    }

    func deactivateAfterPreview() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

#if DEBUG
// MARK: - Fixtures (UI renders and tests; never shipped)

extension ThemeSong {
    /// Demon Slayer-like songs: OP1/ED1 with verified Apple matches (artwork + preview), an insert
    /// song without a match (search link only), and a spoiler ED2 v2 with a match.
    static var fixturesWithApple: [ThemeSong] {
        func apple(_ id: Int) -> AppleSongMatch? {
            AppleSongMatch(trackId: id,
                           artwork: "https://is1-ssl.mzstatic.com/image/thumb/Music/fixture\(id)/600x600bb.jpg",
                           preview: "https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview/fixture\(id).m4a",
                           music: "https://music.apple.com/jp/album/fixture/\(id + 1)?i=\(id)", confidence: 0.97)
        }
        return [
            ThemeSong(kind: .opening, sequence: 1, title: "Gurenge", artist: "LiSA", episodes: "1-19", apple: apple(1_488_408_568)),
            ThemeSong(kind: .ending, sequence: 1, title: "from the edge", artist: "FictionJunction feat. LiSA", episodes: "1-25",
                      apple: apple(1_488_408_600)),
            ThemeSong(kind: .insert, sequence: 1, title: "Kamado Tanjiro no Uta", artist: "Go Shiina feat. Nami Nakagawa"),
            ThemeSong(kind: .ending, sequence: 2, title: "Shirogane", artist: "LiSA", episodes: "26", version: 2,
                      isSpoiler: true, apple: apple(1_550_000_001)),
        ]
    }
}
#endif

