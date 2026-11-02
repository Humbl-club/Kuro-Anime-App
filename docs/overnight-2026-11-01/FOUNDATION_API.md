# Foundation lane F: final component API (2026-11-01)

```swift
// Final exact API lanes call (lane F, 2026-11-01)

// MARK: Shared views (Kuro/Views/Shared/)
struct KuroStateView: View {
  nonisolated enum Kind: Equatable, Sendable { case loading; case empty; case offline(hasCachedContent: Bool); case failed(hasCachedContent: Bool); case denied }
  enum Layout { case page; case inline }
  init(_ kind: Kind, title: String? = nil, message: String? = nil, layout: Layout = .page, retry: (() -> Void)? = nil)
}
nonisolated enum KuroStateCopy { struct Copy: Equatable, Sendable { let title: String; let message: String? }
  static func copy(for kind: KuroStateView.Kind, german: Bool) -> Copy; static func retryTitle(german: Bool) -> String }
// Default copy: offline(false) "Offline." / "Connect to load this." (DE "Verbinde dich, um das zu laden."); offline(true) "Showing what you saw last."; failed(false) "Couldn't load this." / "Try again in a moment."; failed(true) "Couldn't refresh." / "What you had is still here."
struct KuroInkButton: View { enum Role { case primary, secondary, destructive }
  init(_ title: String, role: Role = .primary, isLoading: Bool = false, haptic: Bool = true, action: @escaping () -> Void) }
struct KuroPressStyle: ButtonStyle { var pressedScale: CGFloat = 0.98 }
struct KuroSectionHeader: View { enum Size { case headline, title }
  init(_ title: String, kicker: String? = nil, size: Size = .headline, actionTitle: String? = nil, action: (() -> Void)? = nil) }
struct KuroReleaseLine: View {
  init(_ item: ReleaseScheduleItem, showsSource: Bool = false, undatedFallback: Bool = false, font: Font = .kuroMeta(), color: Color = .kuroInkSecondary, now: Date = Date()) }
struct KuroThemeSongRow: View { init(_ song: ThemeSong) }
struct KuroMediumSwitch: View { enum Size { case large, compact }; init(selection: Binding<MediaKind>, size: Size = .large) }
struct KuroAdvanceKey: View { enum Style { case light, dark }; enum Phase: Equatable { case advance, caughtUp, needsChoice, pending }
  init(style: Style, phase: Phase = .advance, accessibilityText: String, action: @escaping () -> Void) }
nonisolated enum KuroAdvanceCopy {
  static func label(medium: MediaKind, nextUnit: Int, title: String?, current: Int? = nil, total: Int? = nil, german: Bool) -> String
  static func caughtUpLabel(title: String?, german: Bool) -> String }
extension View { func kuroReadableWidth(_ maxWidth: CGFloat = KuroReadableWidth.maxWidth) -> some View }  // 680 pt column on regular width
enum KuroReadableWidth { static let maxWidth: CGFloat = 680 }
extension EnvironmentValues { var kuroPagerWidth: CGFloat }  // gesture edge check ONLY, not a layout width; size cards from your container (onGeometryChange / containerRelativeFrame / GeometryReader)

// MARK: Design (Kuro/Design/)
extension Color { static let kuroInk, kuroInkSecondary, kuroInkQuiet, kuroHairline, kuroMissingArt, kuroKeyRim, kuroRoom, kuroRoomText, kuroRoomTextSecondary, kuroInkPressed, kuroCanvasQuiet; static let kuroDestructiveInk /* #C4271D, destructive text/outline */; static let kuroError /* icons/inline marks */ }
extension Font { static func kuroHero/kuroDisplay/kuroFeature/kuroHeadline/kuroTitle/kuroBody/kuroCaption/kuroMicro/kuroNavigation/kuroTitleName/kuroMeta/kuroButtonLabel(weight: Font.Weight = <role default>) -> Font
  static func kuroCustom(_ baseSize: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default, relativeTo textStyle: UIFont.TextStyle = .body, maxSize: CGFloat? = nil) -> Font }
enum KuroTypeRole { case hero, display, feature, headline, title, body, caption, micro, navigation, titleName, meta, buttonLabel; var spec: (base: CGFloat, style: UIFont.TextStyle, cap: CGFloat); var pointSize: CGFloat }
@MainActor @Observable final class KuroTypeScale { static let current; private(set) var category: UIContentSizeCategory?; func update(_ size: DynamicTypeSize); func update(category: UIContentSizeCategory); func scaled(_ baseSize: CGFloat, relativeTo: UIFont.TextStyle) -> CGFloat; nonisolated static func category(for: DynamicTypeSize) -> UIContentSizeCategory }  // follows the system content-size notification on its own
extension View { func kuroDynamicTypeScale() -> some View; func kuroKicker() -> some View }
enum KuroLocale { static var isGerman: Bool; static func isGerman(preferredLanguages: [String]) -> Bool; static func text(_ english: String, _ german: String) -> String; static var locale: Locale; static var timeZone: TimeZone; static var calendar: Calendar; static func calendar(locale: Locale, timeZone: TimeZone) -> Calendar }
enum KuroMotion { static let contact: Animation; static let settle: Animation }

// MARK: Release models (Kuro/Releases/ReleaseModels.swift)
nonisolated enum ReleaseBasis: String { case confirmed, announced, estimated }
nonisolated enum ReleaseUnitKind: String { case episode, chapter, volume, season }
nonisolated struct ReleaseScheduleItem: Hashable, Sendable, Identifiable { let medium: MediaKind; let mediaId: Int; let title: String; let coverImage: String?; let unitKind: ReleaseUnitKind; let unitNumber: Double?; let unitLabel: String?; let releaseAt: Date?; let basis: ReleaseBasis; let confidence: Double?; let source: String; let sourceURL: URL?; let isPast: Bool
  init(medium:mediaId:title:coverImage: = nil, unitKind:unitNumber:unitLabel: = nil, releaseAt:basis:confidence: = nil, source:sourceURL: = nil, isPast: = false)
  var key: MediaKey; var id: String; var isDisplayable: Bool /* estimates need confidence >= 0.7 */; var wholeUnitNumber: Int? }
nonisolated enum ThemeSongKind: String { case opening = "OP", ending = "ED", insert = "IN" }
nonisolated struct ThemeSong: Hashable, Sendable, Identifiable { let kind: ThemeSongKind; let sequence: Int?; let title: String; let artist: String?; let episodes: String?; let version: Int?; let isSpoiler: Bool; let isNSFW: Bool; let source: String; let sourceURL: URL?
  var id: String; var label: String /* "OP1" */; func spokenLabel(german: Bool) -> String /* "Opening 1" / "Vorspann 1" */; var searchQuery: String; var appleMusicSearchURL: URL?; var spotifySearchURL: URL? }
nonisolated struct ReleaseCopy { init(now: Date, german: Bool, locale: Locale, timeZone: TimeZone); static func current(now: Date = Date()) -> ReleaseCopy
  func unitLabel(_:) -> String; func unitSpokenLabel(_:) -> String; func datePhrase(_:) -> String?; func line(_ item: ReleaseScheduleItem, undatedFallback: Bool = false) -> String; func accessibilityLine(_:) -> String; var datesToCome: String; func sourceAttribution(_:) -> String? }
// Estimated: "expected around Sun 18 Oct" / "voraussichtlich am So. 18. Okt."; announced day-only = UTC calendar date

// MARK: ReleasesStore (@MainActor @Observable, inject via @Environment(ReleasesStore.self))
var upcomingAirings: [UpcomingAiring]; var countdownByAnimeId: [Int: String]
var schedule: [ReleaseScheduleItem]; var scheduleSource: ScheduleSource /* .none | .schedule | .airingFallback */
func fetchUpcomingForUser(days: Int = 7) async                 // unchanged Void signature
func refreshUpcomingForUser(days: Int = 7) async -> Bool        // NEW: true = upcomingAirings holds a successful read (fresh, or within the 20 s throttle)
nonisolated static let upcomingThrottle: TimeInterval = 20
func scheduleItems(for medium: MediaKind?) -> [ReleaseScheduleItem]
func nextRelease(for key: MediaKey) -> ReleaseScheduleItem?
@discardableResult func loadSchedule(limit: Int = ReleasesStore.defaultScheduleLimit, force: Bool = false) async -> [ReleaseScheduleItem]
func mediaSchedule(kind: MediaKind, id: Int, limit: Int = 6, force: Bool = false) async -> [ReleaseScheduleItem]
func themes(animeId: Int, force: Bool = false) async -> [ThemeSong]
func startCountdownUpdates(for context: AccountContext); func stopCountdownUpdates()

// MARK: Library realtime echo (Kuro/Library/)
nonisolated struct LibraryRealtimeEvent: Equatable, Sendable { enum Action { case insert, update, delete, unknown }
  let action: Action; let key: MediaKey?; let rowId: Int?; let listType: String?; let progress: Int?; let rating: Int?; let notes: String?; let verdict: String?; let serverRevision: Int64?; let lifecycleId: UUID?
  init(action:key:rowId: = nil, listType: = nil, progress: = nil, rating: = nil, notes: = nil, verdict: = nil, serverRevision: = nil, lifecycleId: = nil); static let unknown }
nonisolated enum LibraryEchoPolicy { static let window: TimeInterval = 5; static func resolvedKey(_:ledger:) -> MediaKey?; static func isOwnEcho(_:resolvedKey:inFlight:lastLocalWrite:local:now:) -> Bool; static func matches(_:_:) -> Bool; static func statusMatches(listType:local:) -> Bool }
SupabaseUserListChannel: nonisolated static func event(from action: AnyAction, kind: MediaKind) -> LibraryRealtimeEvent; nonisolated static func event(action: LibraryRealtimeEvent.Action, record: [String: AnyJSON], kind: MediaKind) -> LibraryRealtimeEvent

// MARK: Routing and flags
enum AppRoute { ...; case browse }; EnvironmentValues.kuroRoutes.openBrowse: () -> Void
FeatureFlags: nonisolated func seriesFoundationFenceEnabled() -> Bool; func refresh(client: Any, userId: String?, accountSession: AccountSessionCoordinator? = nil) async; nonisolated static var readsAccountOverrides: Bool; nonisolated static func overridesFailure(for: any Error) -> OverridesFailure
```
