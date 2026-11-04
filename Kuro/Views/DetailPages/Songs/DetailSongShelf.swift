import SwiftUI

// MARK: - The sound of it. (details-songs spec §8; owner items 7 and 8)
// The prototype D8 panel (`material.base → deep`, radius 16, padding 19/16/12, the existing heading) as a
// short player list:
//   - parts by episode span (`SongShelfGrouping`; no invented arc names), versions collapsed into tags,
//     the artist on every row ("Artist not listed" when the source has none for that row; when no row
//     of the shelf has one, a single footer note "Artists not listed by the source." instead);
//   - a verified Apple match shows Apple's artwork (never fetched while the row is veiled) and ▶, which
//     streams Apple's 30-second preview through the injected `SongPreviewPlayer` (data lane, one preview
//     at a time; it stops on background, interruption, unplugged headphones and account change, and this
//     view stops it when the panel leaves the screen or the scene is no longer active). A match without a
//     preview offers "Apple Music ↗"; no match keeps the existing Listen chooser (Apple Music / Spotify
//     SEARCH, nothing stored from either service).
//   - spoilers stay veiled until tapped, or until the viewer's progress reached the song's first episode;
//     NSFW songs are never revealed automatically.
// The signature is fixed (§8.1) so the integrator swaps it in for `DetailSoundPanel`.
// Both environment owners are optional, so the view drops into any host: without `SongPreviewPlayer` there
// is no ▶ (a matched row offers "Apple Music ↗"), and without `NetworkMonitor` the device counts as online.

struct DetailSongShelf: View {
    let songs: [ThemeSong]
    let material: ArtworkMaterial
    /// The Library progress of this title (0 when untracked).
    let progress: Int
    /// "Show all N songs" open or closed (F3, `DetailFold.songs`).
    @Binding var showsAll: Bool
    /// F2: the page scrolls the panel back into view after it folds, when needed.
    let onCollapse: () -> Void

    init(songs: [ThemeSong],
         material: ArtworkMaterial,
         progress: Int,
         showsAll: Binding<Bool>,
         onCollapse: @escaping () -> Void) {
        self.songs = songs
        self.material = material
        self.progress = progress
        self._showsAll = showsAll
        self.onCollapse = onCollapse
    }

    /// Rows shown before "Show all" (spec §8.5).
    nonisolated static let collapsedRows = 6

    @Environment(SongPreviewPlayer.self) private var player: SongPreviewPlayer?
    @Environment(NetworkMonitor.self) private var network: NetworkMonitor?
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Rows revealed for this visit, by row id (never by `ThemeSong`: its hash includes the Apple match).
    @State private var revealed: Set<String> = []
    /// When the active preview started playing (the player reports no position: the clock is the view's).
    @State private var playingSince: Date?

    private var german: Bool { KuroLocale.isGerman }

    var body: some View {
        let parts = SongShelfGrouping.parts(songs)
        let total = SongShelfGrouping.rowCount(parts)
        let shown = showsAll ? parts : SongShelfGrouping.folded(parts, limit: Self.collapsedRows)
        let headed = parts.count > 1
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        let shownRows = shown.flatMap(\.rows)
        VStack(alignment: .leading, spacing: 0) {
            header(total: total)
            ForEach(shown) { part in
                partView(part, headed: headed)
            }
            if total > Self.collapsedRows {
                KuroFoldButton(isExpanded: $showsAll,
                               expandLabel: SongShelfCopy.showAll(total, german: german),
                               collapseLabel: SongShelfCopy.showFewer(german: german),
                               onCollapse: onCollapse) { title, _ in
                    Text(title)
                        .font(.detailSF(11, .medium, relativeTo: .footnote))
                        .foregroundStyle(DetailInk.soundInk)
                        .frame(minHeight: 44)
                }
            }
            footer(rows: shownRows)
        }
        .padding(.top, 19)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .background {
            shape.fill(LinearGradient(colors: [material.base.color, material.deep.color], startPoint: .topLeading, endPoint: .bottomTrailing))
                .shadow(color: Color(hex: "14291C", opacity: 0x0B / 255.0), radius: 7, x: 0, y: 6)
        }
        .overlay(shape.strokeBorder(material.base.color, lineWidth: 1))
        .padding(.top, 25)
        .onChange(of: player?.phase) { _, phase in
            if case .playing = phase ?? .idle {
                if playingSince == nil { playingSince = Date() }
            } else {
                playingSince = nil
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { stopOwnPreview() }
        }
        .onDisappear { stopOwnPreview() }
    }

    // MARK: Header and parts

    private func header(total: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(SongShelfCopy.heading(german: german))
                .font(.detailSF(17, .semibold, relativeTo: .title3))
                .tracking(-0.4)
                .foregroundStyle(DetailInk.soundInk)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            Text(SongShelfCopy.count(total, german: german))
                .font(.detailSF(9, relativeTo: .caption2))
                .foregroundStyle(DetailInk.soundNote)
        }
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func partView(_ part: SongShelfPart, headed: Bool) -> some View {
        let heading = headed ? SongShelfCopy.partHeading(part.kind, german: german) : nil
        VStack(alignment: .leading, spacing: 0) {
            if let heading {
                Text(heading.uppercased())
                    .font(.detailSF(8, .medium, relativeTo: .caption2))
                    .tracking(1.4)
                    .foregroundStyle(DetailInk.soundKicker)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 12)
                    .padding(.bottom, 6)
                    .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(Double(0x18) / 255)).frame(height: 1) }
                    .accessibilityHidden(true)
            }
            ForEach(part.rows) { row in
                rowView(row, singlePart: !headed)
                    .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(Double(0x12) / 255)).frame(height: 1) }
            }
        }
        .accessibilityElement(children: .contain)
        .modifier(SongPartLabel(label: headed ? SongShelfCopy.partSpoken(part.kind, german: german) : nil))
    }

    // MARK: Row

    private func rowView(_ row: SongShelfRow, singlePart: Bool) -> some View {
        let veiled = SongShelfGrouping.isVeiled(row, revealed: revealed.contains(row.id), progress: progress)
        let matched = row.matched
        let failed = matched.flatMap { song in player.map { $0.didFail(song) } } ?? false
        let action = SongShelfGrouping.action(for: row, veiled: veiled, previewFailed: failed, canPlay: player != nil)
        let active = matched.flatMap { song in player.map { $0.isPlaying(song) || $0.isLoading(song) } } ?? false
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                art(row, veiled: veiled)
                if veiled {
                    Button {
                        revealed.insert(row.id)
                    } label: {
                        text(row, veiled: true, singlePart: singlePart)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(SongShelfCopy.veiledSpoken(row, german: german))
                } else {
                    text(row, veiled: false, singlePart: singlePart)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(SongShelfCopy.rowSpoken(row, german: german))
                }
                actionView(action, row: row, active: active)
            }
            if active, let matched {
                playingLine(row: row, song: matched)
            } else if failed, !veiled {
                Text(SongShelfCopy.previewUnavailable(german: german))
                    .font(.detailSF(9, relativeTo: .caption2))
                    .foregroundStyle(DetailInk.soundNote)
                    .padding(.leading, 56)
                    .padding(.top, 2)
            }
        }
        .frame(minHeight: 60, alignment: .leading)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func art(_ row: SongShelfRow, veiled: Bool) -> some View {
        let tileWord = veiled ? SongShelfCopy.spoilerArt(german: german) : SongShelfCopy.tileWord(row.song)
        let tile = KuroBrandedTile(kind: tileWord, style: .onMaterial(material), cornerRadius: 4)
        // A veiled row never asks for its artwork (spec §8.3).
        if !veiled, let url = SongShelfGrouping.artworkURL(row.matched?.apple?.artworkURL, side: 132) {
            KuroCachedAsyncImage(url: url, maxPixelSize: 44) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFill()
                default: tile
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .accessibilityHidden(true)
        } else {
            tile.frame(width: 44, height: 44)
        }
    }

    private func text(_ row: SongShelfRow, veiled: Bool, singlePart: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            FlowLayout(spacing: 4) {
                Text(kindLine(row, singlePart: singlePart).uppercased())
                    .font(.detailSF(7, .medium, relativeTo: .caption2))
                    .tracking(1.4)
                    .foregroundStyle(DetailInk.soundKicker)
                if !veiled {
                    ForEach(tags(row), id: \.self) { tag in
                        Text(tag)
                            .font(.detailSF(7, .medium, relativeTo: .caption2))
                            .foregroundStyle(DetailInk.soundKicker)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
                    }
                }
            }
            if veiled {
                Text(SongShelfCopy.spoiler(german: german))
                    .font(.detailSF(13, .medium, relativeTo: .subheadline))
                    .foregroundStyle(Color(hex: "C9D6CC"))
                    .lineLimit(2)
            } else {
                Text(row.displayTitle)
                    .font(.detailSF(13, .semibold, relativeTo: .subheadline))
                    .foregroundStyle(DetailInk.soundInk)
                    .lineLimit(2)
            }
            if let artist = row.song.artist?.trimmingCharacters(in: .whitespacesAndNewlines), !artist.isEmpty {
                Text(artist)
                    .font(.detailSF(10, relativeTo: .footnote))
                    .foregroundStyle(DetailInk.soundArtist)
                    .lineLimit(1)
            } else if shelfHasArtists {
                Text(SongShelfCopy.artistNotListed(german: german))
                    .font(.detailSF(10, relativeTo: .footnote))
                    .italic()
                    .foregroundStyle(DetailInk.soundNote)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }

    private func kindLine(_ row: SongShelfRow, singlePart: Bool) -> String {
        let kind = SongShelfCopy.kind(row.song, german: german)
        guard singlePart, row.versions.count == 1, let span = SongShelfCopy.rowSpan(row, german: german) else { return kind }
        return "\(kind) · \(span)"
    }

    private func tags(_ row: SongShelfRow) -> [String] {
        var tags = row.versionTags(german: german)
        if row.isTVSize { tags.append(SongShelfCopy.tvSize(german: german)) }
        return tags
    }

    // MARK: Actions

    @ViewBuilder
    private func actionView(_ action: SongShelfGrouping.Action, row: SongShelfRow, active: Bool) -> some View {
        switch action {
        case .none:
            EmptyView()
        case .preview(let song):
            let offline = !isConnected && !active
            Button {
                KuroAccessibility.impactHaptic(.light)
                player?.toggle(song)
            } label: {
                SongPreviewKeyFace(playing: active)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(HomeContactStyle())
            .disabled(offline)
            .opacity(offline ? 0.5 : 1)
            .accessibilityLabel(active ? SongShelfCopy.stopLabel(german: german)
                                : SongShelfCopy.playLabel(row.displayTitle, german: german))
            .accessibilityHint(offline ? SongShelfCopy.youreOffline(german: german) : "")
        case .appleMusic(let url):
            Button {
                openURL(url)
            } label: {
                Text(SongShelfCopy.appleMusicLink(german: german))
                    .font(.detailSF(10, .medium, relativeTo: .footnote))
                    .foregroundStyle(DetailInk.soundInk)
                    .lineLimit(1)
                    .fixedSize()
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(HomeContactStyle())
            .accessibilityLabel(SongShelfCopy.openInAppleMusic(german: german))
        case .listen:
            listenMenu(row.song)
        }
    }

    @ViewBuilder
    private func listenMenu(_ song: ThemeSong) -> some View {
        let apple = song.appleMusicSearchURL
        let spotify = song.spotifySearchURL
        Menu {
            if let apple { Button("Apple Music") { openURL(apple) } }
            if let spotify { Button("Spotify") { openURL(spotify) } }
        } label: {
            Text(SongShelfCopy.listen(german: german) + " ↗")
                .font(.detailSF(10, .medium, relativeTo: .footnote))
                .foregroundStyle(DetailInk.soundInk)
                .lineLimit(1)
                .fixedSize()
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(SongShelfCopy.listenLabel(song.title, german: german))
        .accessibilityHint(SongShelfCopy.listenHint(german: german))
    }

    /// The open row: the scrub with elapsed / 0:30, "Open in Apple Music ↗" and "Spotify ↗" (a search).
    private func playingLine(row: SongShelfRow, song: ThemeSong) -> some View {
        let playing = player?.isPlaying(song) ?? false
        return VStack(alignment: .leading, spacing: 4) {
            Group {
                if playing, let since = playingSince {
                    TimelineView(.periodic(from: since, by: reduceMotion ? 1 : 0.25)) { context in
                        scrub(elapsed: context.date.timeIntervalSince(since))
                    }
                } else {
                    scrub(elapsed: 0)
                }
            }
            .accessibilityHidden(true)
            HStack(spacing: 16) {
                if let music = song.apple.flatMap({ ProviderAvailabilityStore.validatedOutboundURL($0.musicURL.absoluteString) }) {
                    Button { openURL(music) } label: {
                        Text(SongShelfCopy.openInAppleMusicLink(german: german))
                            .font(.detailSF(9, .medium, relativeTo: .caption2))
                            .foregroundStyle(DetailInk.soundInk)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(HomeContactStyle())
                    .accessibilityLabel(SongShelfCopy.openInAppleMusic(german: german))
                }
                if let spotify = song.spotifySearchURL {
                    Button { openURL(spotify) } label: {
                        Text(SongShelfCopy.spotifyLink(german: german))
                            .font(.detailSF(9, .medium, relativeTo: .caption2))
                            .foregroundStyle(DetailInk.soundInk)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(HomeContactStyle())
                    .accessibilityLabel(SongShelfCopy.listenLabel(song.title, german: german) + ", Spotify")
                }
            }
        }
        .padding(.leading, 56)
        .padding(.top, 4)
    }

    private func scrub(elapsed: TimeInterval) -> some View {
        let length = SongPreviewClock.length
        let seconds = SongPreviewClock.shownSeconds(elapsed: elapsed, stepsWholeSeconds: reduceMotion)
        return HStack(spacing: 8) {
            Text(SongShelfCopy.clock(Int(seconds)))
                .font(.detailSF(9, relativeTo: .caption2).monospacedDigit())
                .foregroundStyle(DetailInk.soundArtist)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.white.opacity(0.2))
                    Rectangle().fill(Color.white.opacity(0.9))
                        .frame(width: proxy.size.width * CGFloat(seconds / length))
                }
            }
            .frame(height: 1)
            Text(SongShelfCopy.clock(Int(length)))
                .font(.detailSF(9, relativeTo: .caption2).monospacedDigit())
                .foregroundStyle(DetailInk.soundArtist)
        }
        .frame(height: 14)
    }

    // MARK: Footer

    private func footer(rows: [SongShelfRow]) -> some View {
        let fromAnimeThemes = !songs.isEmpty && songs.allSatisfy { $0.source.lowercased() == "animethemes" }
        let showsAttribution = rows.contains { row in
            row.matched != nil && !SongShelfGrouping.isVeiled(row, revealed: revealed.contains(row.id), progress: progress)
        }
        let offlineNote = !isConnected && rows.contains { row in
            if case .preview = SongShelfGrouping.action(for: row, veiled: false, previewFailed: false,
                                                       canPlay: player != nil) { return true }
            return false
        }
        return VStack(alignment: .leading, spacing: 6) {
            if !shelfHasArtists, !songs.isEmpty {
                Text(SongShelfCopy.artistsNotListed(german: german))
                    .font(.detailSF(9, relativeTo: .caption2))
                    .italic()
                    .foregroundStyle(DetailInk.soundNote)
            }
            if offlineNote {
                Text(SongShelfCopy.youreOffline(german: german))
                    .font(.detailSF(9, relativeTo: .caption2))
                    .foregroundStyle(DetailInk.soundNote)
            }
            if fromAnimeThemes || showsAttribution {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline) {
                        footerTexts(source: fromAnimeThemes, attribution: showsAttribution, spaced: true)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        footerTexts(source: fromAnimeThemes, attribution: showsAttribution, spaced: false)
                    }
                }
            }
        }
        .padding(.top, 13)
    }

    @ViewBuilder
    private func footerTexts(source: Bool, attribution: Bool, spaced: Bool) -> some View {
        if source {
            Text(SongShelfCopy.songListSource(german: german))
                .font(.detailSF(9, relativeTo: .caption2))
                .foregroundStyle(DetailInk.soundNote)
                .fixedSize(horizontal: spaced, vertical: false)
        }
        if source && attribution && spaced { Spacer(minLength: 8) }
        if attribution {
            Text(SongShelfCopy.attribution(german: german))
                .font(.detailSF(9, relativeTo: .caption2))
                .foregroundStyle(DetailInk.soundNote)
                .fixedSize(horizontal: spaced, vertical: false)
        }
    }

    /// Stops the preview when it is one of this panel's songs (leaving the page must not stop another).
    private func stopOwnPreview() {
        guard let player, let active = player.activeSongID else { return }
        if songs.contains(where: { $0.id == active }) { player.stop() }
    }

    /// Whether any song on the shelf names its artist (otherwise one footer note says so for all).
    private var shelfHasArtists: Bool { SongShelfGrouping.anyArtist(songs) }

    /// Without a `NetworkMonitor` in the environment the device counts as online.
    private var isConnected: Bool { network?.isConnected ?? true }
}

/// A part's container label ("Episodes 1 to 5"), only when the shelf shows part headings.
private struct SongPartLabel: ViewModifier {
    let label: String?

    func body(content: Content) -> some View {
        if let label {
            content.accessibilityLabel(label)
        } else {
            content
        }
    }
}

/// The ▶ / ■ key: the light raised face (`KuroKeyFace(.light)` recipe) at 36 pt with an ink glyph.
struct SongPreviewKeyFace: View {
    let playing: Bool

    var body: some View {
        let face = KuroKeyFace(style: .light)
        let shape = RoundedRectangle(cornerRadius: face.radius, style: .continuous)
        ZStack {
            shape.fill(LinearGradient(colors: [face.top, face.bottom], startPoint: .top, endPoint: .bottom))
                .overlay(shape.strokeBorder(face.border, lineWidth: 1))
                .shadow(color: face.drop, radius: 1, x: 0, y: 1)
            if playing {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(face.ink)
                    .frame(width: 10, height: 10)
            } else {
                SongPlayGlyph()
                    .fill(face.ink)
                    .frame(width: 10, height: 11)
                    .offset(x: 1)
            }
        }
        .frame(width: 36, height: 36)
        .accessibilityHidden(true)
    }
}

/// The ▶ triangle.
struct SongPlayGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// The preview clock (pure): Apple's previews are 30 s; the player reports no position, so the shown time
/// is the time since the stream started, capped at the preview's length.
nonisolated enum SongPreviewClock {
    static let length: TimeInterval = 30

    /// Seconds shown on the scrub; Reduce Motion steps in whole seconds.
    static func shownSeconds(elapsed: TimeInterval, stepsWholeSeconds: Bool) -> TimeInterval {
        let clamped = min(length, max(0, elapsed))
        return stepsWholeSeconds ? clamped.rounded(.down) : clamped
    }
}
