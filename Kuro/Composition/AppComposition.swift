import Foundation
import KuroCore
import KuroLibrary
import KuroSupabase

#if canImport(Supabase)
import Supabase
import UIKit

/// The app's composition root: builds the object graph ONCE at launch (`makeGraph`, the single
/// construction path; KuroTests build theirs with the same builder through `testingGraph`).
///
/// - One SDK client (`makeClient`) and one `AccountSessionCoordinator`, shared by every owner.
/// - Identity (E6c1): `identity` (the only holder of auth state), `auth` (SDK auth transport) and
///   `session` (the E1 session funnel: restore, SDK events, sign-in/out, deletion, callbacks, the ONE
///   account-scoped invalidation list from `makeAccountScopedStates`), plus `libraryRealtime` (the
///   account's user-list channel).
/// - `library`: the single authoritative tracking projection (`LibraryStore`) over
///   `SupabaseLibraryBackend` + `PostgrestLibraryTransport` on that same client, with the explicit
///   Releases, Collection, Concierge and Clubs change sinks; `libraryActions` (E6c2): the legacy
///   writer mapping and the Library refresh paths over it.
/// - Shell owners (E6c2): `flags` (runtime flags, the single instance), `banner` (transient banner),
///   `interactionTelemetry` (account-scoped event queue) and `outboundLinks`; `memoryPressure` holds
///   the ONE list of owners trimmed on a memory warning.
/// - Public-data owners (E5a) on that same client: `catalog`, `search`, `discovery`,
///   `recommendations`.
/// - Personal-data owners (E5b) on that same client: `reminders` (ReminderDelivery), plus the
///   Releases, ProviderAvailability and SocialActivity owners.
/// - Clubs owner (E6a) on that same client: `clubs` (with its realtime coordinator), wired to the
///   SocialActivity and ProviderAvailability owners for club revocation.
/// - Collection owner (E5c) on that same client: `collection` (the account's card pages and feed,
///   refreshed by the Collection change sink).
/// - Assistant owners (E6b) on that same client: `imports` (Imports), `concierge` (Concierge) and
///   `taste` (Taste, with the deck signal outbox drained whenever the app returns to the foreground),
///   plus `deviceIntelligence`, the single on-device FM service. The server-side list writers among
///   them reach the Library through one hook (`LibraryRefreshHook`), connected to `libraryActions`.
/// `KuroApp` injects the view-facing owners into the environment.
@MainActor
final class AppComposition {
    static let shared = AppComposition()

    /// The app's object graph (built by `makeGraph`).
    let graph: AppGraph
    /// Drains the deck signal outbox whenever the app returns to the foreground (app lifetime).
    private var foregroundSignalDrain: TasteForegroundDrain?

    var accountSession: AccountSessionCoordinator { graph.accountSession }
    var identity: IdentityStore { graph.identity }
    var auth: AuthService { graph.auth }
    var session: SessionController { graph.session }
    var library: LibraryStore { graph.library }
    /// The Library writer mapping and refresh paths (over `library`).
    var libraryActions: LibraryActions { graph.libraryActions }
    var libraryRealtime: LibraryRealtime { graph.libraryRealtime }
    var home: HomeStore { graph.home }
    var catalog: CatalogStore { graph.catalog }
    var search: SearchStore { graph.search }
    var discovery: DiscoveryStore { graph.discovery }
    var recommendations: RecommendationsReader { graph.recommendations }
    var releases: ReleasesStore { graph.releases }
    var social: SocialActivityStore { graph.social }
    var availability: ProviderAvailabilityStore { graph.availability }
    var clubs: ClubsStore { graph.clubs }
    var collection: CollectionStore { graph.collection }
    var imports: ImportsService { graph.imports }
    var concierge: ConciergeStore { graph.concierge }
    var taste: TasteStore { graph.taste }
    var deviceIntelligence: AppleFMService { graph.deviceIntelligence }
    /// The runtime flags (the single instance; views read it from the environment).
    var flags: FeatureFlags { graph.flags }
    /// The transient banner (newest wins, auto-clear).
    var banner: BannerCenter { graph.banner }
    /// Interaction events (account-scoped offline queue; over `ConciergeAnalytics.shared`).
    var interactionTelemetry: InteractionTelemetry { graph.interactionTelemetry }
    /// The outbound-link ledger (fire-and-forget).
    var outboundLinks: OutboundLinkTelemetry { graph.outboundLinks }
    /// Artwork materials (seed colour first, then derived from the artwork; memory + disk cache).
    var artworkMaterials: ArtworkMaterialStore { graph.artworkMaterials }
    /// The owners that shed public caches on a memory warning (the ONE registration list:
    /// `memoryPressureOwners(publicData:assistant:)`).
    var memoryPressure: MemoryPressureRelief { graph.memoryPressure }

    private init() {
        // The client is chosen BEFORE it is built: a test host or `--kuro-fixture-host` run gets the
        // fixture client (no real URL/key, no Keychain, every request refused locally).
        let client: SupabaseClient?
        let configError: String?
        #if DEBUG
        if FixtureHost.isActive() {
            FixtureHost.installDenyAll()
            client = FixtureHost.makeClient()
            configError = nil
        } else {
            (client, configError) = Self.makeClient()
        }
        #else
        (client, configError) = Self.makeClient()
        #endif
        let flags = FeatureFlags()
        let malRegistration: MALNativeRegistration?
        #if DEBUG
        malRegistration = FixtureHost.isActive() ? nil : AppConfig.malNativeRegistration
        #else
        malRegistration = AppConfig.malNativeRegistration
        #endif
        let graph = Self.makeGraph(
            client: client,
            configError: configError,
            userDefaults: .standard,
            notificationCenter: LiveNotificationCenter(),
            flags: flags,
            interactionTelemetry: InteractionTelemetry(analytics: .shared, client: client),
            libraryBackend: Self.libraryBackend(client: client, fenceEnabled: { flags.seriesFoundationFenceEnabled() }),
            clubChannels: nil,
            clubRefreshDebounce: ClubRealtimeCoordinator.defaultRefreshDebounce,
            userListChannels: SupabaseUserListChannelFactory(client: client),
            libraryRealtimeDebounce: LibraryRealtime.defaultRefreshDebounce,
            malRegistration: malRegistration
        )
        self.graph = graph
        foregroundSignalDrain = graph.taste.installForegroundDrain()
        #if DEBUG
        // The unit-test host never restores a session at launch (tests drive the funnel themselves).
        if !FixtureHost.isTestHost() { graph.session.startLaunchRestore() }
        #else
        graph.session.startLaunchRestore()
        #endif
    }

    /// The app's SDK client from AppConfig, or the configuration error when it is missing.
    static func makeClient() -> (client: SupabaseClient?, configError: String?) {
        guard let url = AppConfig.supabaseURL, let key = AppConfig.supabaseAnonKey else {
            return (nil, "Missing SUPABASE_URL or SUPABASE_ANON_KEY in configuration")
        }
        let client = SupabaseClient(
            supabaseURL: url,
            supabaseKey: key,
            options: SupabaseClientOptions(
                db: .init(encoder: PostgrestRequestEncoding.encoder(), decoder: ClubError.postgrestDecoder())
            )
        )
        #if DEBUG
        print("🔥 Supabase client initialized: \(url.host ?? url.absoluteString)")
        #endif
        return (client, nil)
    }

    /// THE construction path of the object graph (production `init` and `testingGraph` both call it):
    /// every owner over the single `client` and one account coordinator, the Library sinks and the
    /// assistant's Library hook connected, the identity owners and the session funnel with the ONE
    /// account-scoped list. Starts nothing (the production launch restore is started by `init`).
    /// - `userDefaults` / `notificationCenter`: the device stores (reminder owner marker, club
    ///   preferences); production `.standard` + `LiveNotificationCenter`.
    /// - `flags` / `interactionTelemetry`: built by the caller (production: `.standard`, this
    ///   process's launch arguments, `ConciergeAnalytics.shared`).
    /// - `clubChannels` / `userListChannels`: the realtime channel factories (nil club channels =
    ///   channels on `client`); `clubRefreshDebounce` / `libraryRealtimeDebounce` between an event and
    ///   the re-read.
    static func makeGraph(
        client: SupabaseClient?,
        configError: String?,
        userDefaults: UserDefaults,
        notificationCenter: any PendingNotificationCenter,
        flags: FeatureFlags,
        interactionTelemetry: InteractionTelemetry,
        libraryBackend: any LibraryBackend,
        clubChannels: (any ClubChannelFactory)?,
        clubRefreshDebounce: Duration,
        userListChannels: any UserListChannelFactory,
        libraryRealtimeDebounce: Duration,
        malRegistration: MALNativeRegistration? = nil,
        progressOutbox: ProgressOutbox? = nil,
        malCredentials: any MALCredentialStore = KeychainMALCredentialStore()
    ) -> AppGraph {
        let accountSession = AccountSessionCoordinator()
        let shell = makeShell(
            client: client,
            accountSession: accountSession,
            flags: flags,
            interactionTelemetry: interactionTelemetry
        )
        let wiring = makeLibrary(backend: libraryBackend)
        let publicData = makePublicData(client: client, accountSession: accountSession, library: wiring.store)
        let personalData = makePersonalData(
            client: client,
            accountSession: accountSession,
            catalog: publicData.catalog,
            userDefaults: userDefaults,
            notificationCenter: notificationCenter,
            flags: shell.flags
        )
        let clubs = makeClubs(
            client: client,
            accountSession: accountSession,
            userDefaults: userDefaults,
            personalData: personalData,
            flags: shell.flags,
            channels: clubChannels,
            refreshDebounce: clubRefreshDebounce
        )
        let assistant = makeAssistant(
            client: client,
            accountSession: accountSession,
            library: wiring.store,
            catalog: publicData.catalog,
            malRegistration: malRegistration,
            malCredentials: malCredentials
        )
        let collection = makeCollection(client: client, accountSession: accountSession)
        let home = HomeStore(client: client, accountSession: accountSession, library: wiring.store,
            outbox: progressOutbox,
            progressWritesEnabled: { shell.flags.seriesFoundationV1Enabled })
        let libraryActions = makeLibraryActions(
            accountSession: accountSession,
            library: wiring.store,
            collection: collection,
            assistant: assistant,
            shell: shell
        )
        wiring.sinks.connect(
            releases: personalData.releases,
            collection: collection,
            imports: assistant.imports,
            clubs: clubs
        )
        wiring.sinks.home.store = home
        libraryActions.home = home
        libraryActions.releases = personalData.releases
        clubs.home = home
        collection.home = home
        collection.library = wiring.store
        assistant.libraryHook.connect(to: libraryActions)

        let identity = IdentityStore(configError: client == nil ? configError : nil)
        let auth = AuthService(client: client, identity: identity)
        let libraryRealtime = LibraryRealtime(
            channels: userListChannels,
            accountSession: accountSession,
            library: wiring.store,
            libraryActions: libraryActions,
            collection: collection,
            releases: personalData.releases,
            refreshDebounce: libraryRealtimeDebounce
        )
        wiring.sinks.realtimeEcho.realtime = libraryRealtime
        let session = SessionController(
            client: client,
            identity: identity,
            auth: auth,
            accountSession: accountSession,
            library: wiring.store,
            libraryActions: libraryActions,
            libraryRealtime: libraryRealtime,
            reminders: personalData.reminders,
            releases: personalData.releases,
            collection: collection,
            clubs: clubs,
            availability: personalData.availability,
            shell: shell,
            accountScopedStates: makeAccountScopedStates(
                libraryActions: libraryActions,
                home: home,
                collection: collection,
                publicData: publicData,
                personalData: personalData,
                clubs: clubs,
                assistant: assistant,
                shell: shell
            )
        )
        return AppGraph(
            accountSession: accountSession,
            identity: identity,
            auth: auth,
            session: session,
            library: wiring.store,
            librarySinks: wiring.sinks,
            libraryActions: libraryActions,
            libraryRealtime: libraryRealtime,
            home: home,
            catalog: publicData.catalog,
            search: publicData.search,
            discovery: publicData.discovery,
            recommendations: publicData.recommendations,
            reminders: personalData.reminders,
            releases: personalData.releases,
            social: personalData.social,
            availability: personalData.availability,
            clubs: clubs,
            collection: collection,
            imports: assistant.imports,
            concierge: assistant.concierge,
            taste: assistant.taste,
            deviceIntelligence: assistant.deviceIntelligence,
            libraryHook: assistant.libraryHook,
            flags: shell.flags,
            banner: shell.banner,
            interactionTelemetry: shell.interactionTelemetry,
            outboundLinks: shell.outboundLinks,
            artworkMaterials: shell.artworkMaterials,
            memoryPressure: MemoryPressureRelief(owners: memoryPressureOwners(publicData: publicData, assistant: assistant))
        )
    }

    /// KuroTests' graph, built by `makeGraph` (the production construction path): no AppConfig read,
    /// no launch restore (`identity.isAuthBootstrapping` stays false), the test's own device stores and
    /// collaborators. `client` is nil or a client whose requests a test answers in-process; the Library
    /// store runs over `libraryBackend` when given, otherwise over `client` exactly as in production.
    /// Club channels come from `clubChannels` and list channels from `userListChannels` when given
    /// (test fakes), otherwise from `client` as in production. `flags` defaults to an instance over
    /// `testingUserDefaults` with no launch arguments (never the app graph's); `interactionTelemetry`
    /// to an unconfigured analytics instance that never sends.
    static func testingGraph(
        testingUserDefaults: UserDefaults,
        notificationCenter: any PendingNotificationCenter,
        client: SupabaseClient? = nil,
        libraryBackend: (any LibraryBackend)? = nil,
        clubChannels: (any ClubChannelFactory)? = nil,
        clubRefreshDebounce: Duration = ClubRealtimeCoordinator.defaultRefreshDebounce,
        userListChannels: (any UserListChannelFactory)? = nil,
        libraryRealtimeDebounce: Duration = LibraryRealtime.defaultRefreshDebounce,
        flags: FeatureFlags? = nil,
        interactionTelemetry: InteractionTelemetry? = nil,
        progressOutbox: ProgressOutbox? = nil
    ) -> AppGraph {
        makeGraph(
            client: client,
            configError: nil,
            userDefaults: testingUserDefaults,
            notificationCenter: notificationCenter,
            flags: flags ?? FeatureFlags(userDefaults: testingUserDefaults, launchArguments: []),
            interactionTelemetry: interactionTelemetry ?? InteractionTelemetry(analytics: ConciergeAnalytics(), client: nil),
            libraryBackend: libraryBackend ?? Self.libraryBackend(client: client),
            clubChannels: clubChannels,
            clubRefreshDebounce: clubRefreshDebounce,
            userListChannels: userListChannels ?? SupabaseUserListChannelFactory(client: client),
            libraryRealtimeDebounce: libraryRealtimeDebounce,
            progressOutbox: progressOutbox,
            // A test graph never touches the device Keychain, and graphs never share MAL credentials.
            malCredentials: InMemoryMALCredentialStore()
        )
    }

    /// The ONE list of account-scoped owners the session funnel cancels and clears on every
    /// transition (production and KuroTests alike), in this order: the Library actions first (the
    /// account's Library refreshes are cancelled before anything else; the funnel rebinds/resets the
    /// store itself before this list runs), the Collection pages, the public-data owners (Discovery),
    /// the personal-data owners (Releases, Social, ProviderAvailability), Clubs, the assistant owners
    /// (Imports, Concierge, Taste) and the interaction telemetry LAST (the ending account's queued
    /// events are dropped before the funnel sets the new user id).
    static func makeAccountScopedStates(
        libraryActions: LibraryActions,
        home: HomeStore,
        collection: CollectionStore,
        publicData: PublicDataOwners,
        personalData: PersonalDataOwners,
        clubs: ClubsStore,
        assistant: AssistantOwners,
        shell: ShellOwners
    ) -> [any AccountScopedState] {
        [libraryActions, home, collection] + publicData.accountScopedStates
            + personalData.accountScopedStates + [clubs] + assistant.accountScopedStates + [shell.interactionTelemetry]
    }

    /// The Library writer mapping and refresh paths over `library` (account-scoped: refreshes,
    /// toggle guard, write error). The toggles post their results to the shell's banner; a skipped
    /// Collection refresh goes through `collection`; tracking copies held by `assistant.imports` are
    /// dropped after server-side writes. Connect `assistant.libraryHook` to it.
    static func makeLibraryActions(
        accountSession: AccountSessionCoordinator,
        library: LibraryStore,
        collection: CollectionStore,
        assistant: AssistantOwners,
        shell: ShellOwners
    ) -> LibraryActions {
        LibraryActions(
            library: library,
            accountSession: accountSession,
            collection: collection,
            imports: assistant.imports,
            banner: shell.banner
        )
    }

    /// The app-shell owners over `client` (the single SDK client; never a second one): the runtime
    /// flags and the interaction telemetry (both built by the caller: production reads `.standard`,
    /// this process's launch arguments and `ConciergeAnalytics.shared`; tests and previews pass their
    /// own), the transient banner, the outbound-link ledger and the artwork materials.
    static func makeShell(
        client: SupabaseClient?,
        accountSession: AccountSessionCoordinator,
        flags: FeatureFlags,
        interactionTelemetry: InteractionTelemetry
    ) -> ShellOwners {
        ShellOwners(
            flags: flags,
            banner: BannerCenter(),
            interactionTelemetry: interactionTelemetry,
            outboundLinks: OutboundLinkTelemetry(client: client, accountSession: accountSession),
            artworkMaterials: ArtworkMaterialStore()
        )
    }

    /// The ONE list of owners whose public caches are shed under memory pressure (entity, ladder and
    /// detail caches, the Discover bundle, the concierge parse and recommendation caches). Image memory
    /// is cleared by `MemoryPressureRelief` itself; user-facing state is never trimmed.
    static func memoryPressureOwners(
        publicData: PublicDataOwners,
        assistant: AssistantOwners
    ) -> [any MemoryPressureTrimmable] {
        [publicData.catalog, publicData.discovery, assistant.imports, assistant.concierge]
    }

    /// The assistant owners over `client` (the single SDK client; never a second one): Imports
    /// (parse, apply/Undo, AniList import, library export), Concierge (recommend, warmup, feedback) and
    /// Taste (deck, signals + outbox, profile, personalised NEW TO YOU), plus the on-device FM service.
    /// Imports reads the Library store and the Catalog's legacy anime pages (export text). Imports and
    /// Taste share one `LibraryRefreshHook`; connect it to `LibraryActions` once that exists. Without a
    /// `deviceIntelligence`, a new FM service is created (one per object graph).
    static func makeAssistant(
        client: SupabaseClient?,
        accountSession: AccountSessionCoordinator,
        library: LibraryStore,
        catalog: CatalogStore,
        deviceIntelligence: AppleFMService? = nil,
        malRegistration: MALNativeRegistration? = nil,
        malCredentials: any MALCredentialStore = KeychainMALCredentialStore()
    ) -> AssistantOwners {
        let libraryHook = LibraryRefreshHook()
        let imports = ImportsService(
            client: client,
            accountSession: accountSession,
            library: library,
            catalog: catalog,
            libraryHook: libraryHook,
            malRegistration: malRegistration,
            malCredentials: malCredentials
        )
        let concierge = ConciergeStore(client: client, accountSession: accountSession)
        let taste = TasteStore(client: client, accountSession: accountSession, libraryHook: libraryHook)
        return AssistantOwners(
            imports: imports,
            concierge: concierge,
            taste: taste,
            deviceIntelligence: deviceIntelligence ?? AppleFMService(),
            libraryHook: libraryHook,
            accountScopedStates: [imports, concierge, taste]
        )
    }

    /// The Clubs owner over `client` (the single SDK client; never a second one). `userDefaults` is
    /// the graph's device store (account-scoped club preferences). Club revocation drops the friend
    /// projection (`personalData.social`) and the club's shared providers (`personalData.availability`).
    /// `channels` defaults to realtime channels on `client`; KuroTests pass a fake and a short debounce.
    /// `flags` gates club notifications and realtime (`clubs_notifications_v1`, `clubs_realtime_v1`).
    static func makeClubs(
        client: SupabaseClient?,
        accountSession: AccountSessionCoordinator,
        userDefaults: UserDefaults,
        personalData: PersonalDataOwners,
        flags: FeatureFlags,
        channels: (any ClubChannelFactory)? = nil,
        refreshDebounce: Duration = ClubRealtimeCoordinator.defaultRefreshDebounce
    ) -> ClubsStore {
        ClubsStore(
            client: client,
            accountSession: accountSession,
            userDefaults: userDefaults,
            social: personalData.social,
            availability: personalData.availability,
            flags: flags,
            channels: channels ?? SupabaseClubChannelFactory(client: client, accountSession: accountSession),
            refreshDebounce: refreshDebounce
        )
    }

    /// The Collection owner over `client` (the single SDK client; never a second one): the account's
    /// card pages and feed (account-scoped). The Collection change sink points at it once it exists
    /// (`LibraryChangeSinks.connect(releases:collection:imports:clubs:)`).
    static func makeCollection(client: SupabaseClient?, accountSession: AccountSessionCoordinator) -> CollectionStore {
        CollectionStore(client: client, accountSession: accountSession)
    }

    /// The public-data owners over `client` (the single SDK client; never a second one).
    static func makePublicData(
        client: SupabaseClient?,
        accountSession: AccountSessionCoordinator,
        library: LibraryStore
    ) -> PublicDataOwners {
        let catalog = CatalogStore(client: client)
        let discovery = DiscoveryStore(client: client, accountSession: accountSession, library: library)
        return PublicDataOwners(
            catalog: catalog,
            search: SearchStore(client: client),
            discovery: discovery,
            recommendations: RecommendationsReader(client: client, catalog: catalog),
            accountScopedStates: [discovery]
        )
    }

    /// The personal-data owners over `client` (the single SDK client; never a second one).
    /// `userDefaults` and `notificationCenter` are the graph's device collaborators (production:
    /// `.standard` and `LiveNotificationCenter`; KuroTests: the testing seam's), so the reminder owner
    /// marker and the other account preferences share one store. `flags` gates the provider
    /// observability snapshot (`streaming_availability_v1`).
    static func makePersonalData(
        client: SupabaseClient?,
        accountSession: AccountSessionCoordinator,
        catalog: CatalogStore,
        userDefaults: UserDefaults,
        notificationCenter: any PendingNotificationCenter,
        flags: FeatureFlags
    ) -> PersonalDataOwners {
        let reminders = ReminderScheduler(
            client: client,
            accountSession: accountSession,
            userDefaults: userDefaults,
            notificationCenter: notificationCenter
        )
        let releases = ReleasesStore(client: client, accountSession: accountSession, reminders: reminders)
        let social = SocialActivityStore(client: client, accountSession: accountSession)
        let availability = ProviderAvailabilityStore(
            client: client,
            accountSession: accountSession,
            catalog: catalog,
            flags: flags
        )
        return PersonalDataOwners(
            reminders: reminders,
            releases: releases,
            social: social,
            availability: availability,
            accountScopedStates: [releases, social, availability]
        )
    }

    /// The list backend on `client`. Without a client (missing configuration) nobody can sign in;
    /// every operation reports `.unavailable`.
    static func libraryBackend(
        client: SupabaseClient?,
        fenceEnabled: @escaping @Sendable () -> Bool = { false }
    ) -> any LibraryBackend {
        guard let client else { return UnconfiguredLibraryBackend() }
        let transport = PostgrestLibraryTransport(client: client)
        return SupabaseLibraryBackend(transport: transport, fence: transport, fenceEnabled: fenceEnabled)
    }

    /// A store over `backend` with the Releases, Collection, Concierge and Clubs sinks; connect the
    /// sinks to their owners once those exist.
    static func makeLibrary(backend: any LibraryBackend) -> (store: LibraryStore, sinks: LibraryChangeSinks) {
        let sinks = LibraryChangeSinks()
        return (LibraryStore(backend: backend, sinks: sinks.all), sinks)
    }
}

/// The object graph built by `AppComposition.makeGraph` (production and KuroTests alike).
@MainActor
struct AppGraph {
    let accountSession: AccountSessionCoordinator
    let identity: IdentityStore
    let auth: AuthService
    let session: SessionController
    let library: LibraryStore
    /// The Library store's change sinks, connected to `releases`, `collection`, `imports`, `clubs`.
    let librarySinks: LibraryChangeSinks
    let libraryActions: LibraryActions
    let libraryRealtime: LibraryRealtime
    let home: HomeStore
    let catalog: CatalogStore
    let search: SearchStore
    let discovery: DiscoveryStore
    let recommendations: RecommendationsReader
    let reminders: ReminderScheduler
    let releases: ReleasesStore
    let social: SocialActivityStore
    let availability: ProviderAvailabilityStore
    let clubs: ClubsStore
    let collection: CollectionStore
    let imports: ImportsService
    let concierge: ConciergeStore
    let taste: TasteStore
    let deviceIntelligence: AppleFMService
    /// The single Library hook of the server-side list writers, connected to `libraryActions`.
    let libraryHook: LibraryRefreshHook
    let flags: FeatureFlags
    let banner: BannerCenter
    let interactionTelemetry: InteractionTelemetry
    let outboundLinks: OutboundLinkTelemetry
    let artworkMaterials: ArtworkMaterialStore
    let memoryPressure: MemoryPressureRelief
}

/// The app-shell owners built by `AppComposition.makeShell` (E6c2): injected into the environment and
/// handed to the session funnel.
@MainActor
struct ShellOwners {
    /// The runtime flags: the single instance of this graph (owners gate on it; the session funnel
    /// sets its user id and refreshes it).
    let flags: FeatureFlags
    /// The transient banner (newest wins, auto-clear).
    let banner: BannerCenter
    /// Interaction events; account-scoped (the ending account's queued events are dropped).
    let interactionTelemetry: InteractionTelemetry
    /// The outbound-link ledger (fire-and-forget).
    let outboundLinks: OutboundLinkTelemetry
    /// Artwork materials: AniList seed colour first, then the on-device `art-hue-v1` material
    /// (memory + disk cache keyed by image URL). Not account-scoped: derived from public artwork.
    let artworkMaterials: ArtworkMaterialStore
}

/// The public-data owners built by `AppComposition.makePublicData`.
@MainActor
struct PublicDataOwners {
    let catalog: CatalogStore
    let search: SearchStore
    let discovery: DiscoveryStore
    let recommendations: RecommendationsReader
    /// The owners holding personalised results; the session funnel cancels and clears exactly these.
    let accountScopedStates: [any AccountScopedState]
}

/// The personal-data owners built by `AppComposition.makePersonalData`.
@MainActor
struct PersonalDataOwners {
    /// ReminderDelivery: device airing reminders. Not an `AccountScopedState`: the session funnel
    /// calls its account rules (remove on end/switch, keep for the restored owner) directly.
    let reminders: ReminderScheduler
    /// Releases: upcoming airings and countdowns (account-scoped); triggers the reminders.
    let releases: ReleasesStore
    /// SocialActivity: friend counts and title comments (account- and club-membership-scoped).
    let social: SocialActivityStore
    /// ProviderAvailability: public registry/caches/legal links (survive sign-out) plus the account's
    /// services and club-shared providers (account-scoped).
    let availability: ProviderAvailabilityStore
    /// The owners holding account-scoped state; the session funnel cancels and clears exactly these.
    let accountScopedStates: [any AccountScopedState]
}

/// The assistant owners built by `AppComposition.makeAssistant`.
@MainActor
struct AssistantOwners {
    /// Imports: concierge parse (+ cache), apply/Undo (server-side list writers), AniList import,
    /// library export text (account-scoped).
    let imports: ImportsService
    /// Concierge: recommendations (+ cache), warmup, retrieval feedback (account-scoped).
    let concierge: ConciergeStore
    /// Taste: deck batch, signals + outbox, taste profile, realm copy, personalised NEW TO YOU
    /// (account-scoped).
    let taste: TasteStore
    /// DeviceIntelligence: the single on-device FM service (`FMProvider` seam; devices without Foundation Models fall back through `AppleFMService`'s availability guards).
    let deviceIntelligence: AppleFMService
    /// The single Library hook of the server-side list writers (Imports apply/Undo, Taste 'love').
    let libraryHook: LibraryRefreshHook
    /// The owners holding account-scoped state; the session funnel cancels and clears exactly these.
    let accountScopedStates: [any AccountScopedState]
}

/// Backend used when SUPABASE_URL / SUPABASE_ANON_KEY are missing.
nonisolated struct UnconfiguredLibraryBackend: LibraryBackend {
    private static let error = LibraryError.unavailable(message: "Missing Supabase configuration.")

    func fetchAll(for account: AccountContext) async throws -> [LibraryEntry] {
        throw Self.error
    }

    func edit(
        _ edit: LibraryEdit,
        key: MediaKey,
        createIfMissing: ListStatus?,
        mutationId: UUID,
        baseRevision: Int64?,
        account: AccountContext
    ) async throws -> LibraryWriteResult {
        throw Self.error
    }

    func insertIfMissing(_ key: MediaKey, status: ListStatus, account: AccountContext) async throws -> LibraryWriteResult {
        throw Self.error
    }

    func remove(_ key: MediaKey, account: AccountContext) async throws {
        throw Self.error
    }
}
#endif
