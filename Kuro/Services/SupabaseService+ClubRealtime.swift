import Foundation
import Observation
import UserNotifications

#if canImport(Supabase)
import Supabase

extension SupabaseService {
// MARK: - Club Realtime


    func subscribeToClubUpdates(clubId: String) async {
        guard FeatureFlags.shared.isClubsRealtimeV1Enabled else { return }
        guard clubRealtimeSubscribedId != clubId else { return }

        await unsubscribeFromClubUpdates()
        clubRealtimeSubscribedId = clubId

        let channel = client.channel("kuro.club.\(clubId)")
        clubRealtimeChannel = channel

        let itemStream = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "club_rail_items"
        )
        let voteStream = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "club_votes"
        )
        let reactionStream = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "club_rail_item_reactions"
        )
        let pollStream = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "club_polls",
            filter: .eq("club_id", value: clubId)
        )
        let messageStream = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "club_messages",
            filter: .eq("club_id", value: clubId)
        )

        clubRealtimeListenTasks = [
            Task { [weak self] in
                guard let self else { return }
                for await _ in itemStream {
                    await MainActor.run { self.scheduleClubRefresh(clubId: clubId) }
                }
            },
            Task { [weak self] in
                guard let self else { return }
                for await _ in voteStream {
                    await MainActor.run { self.scheduleClubRefresh(clubId: clubId) }
                }
            },
            Task { [weak self] in
                guard let self else { return }
                for await _ in reactionStream {
                    await MainActor.run { self.scheduleClubRefresh(clubId: clubId) }
                }
            },
            Task { [weak self] in
                guard let self else { return }
                for await _ in pollStream {
                    await MainActor.run { self.scheduleClubRefresh(clubId: clubId) }
                }
            },
            Task { [weak self] in
                guard let self else { return }
                for await _ in messageStream {
                    await MainActor.run { self.scheduleClubRefresh(clubId: clubId) }
                }
            },
        ]

        do {
            _ = try await channel.subscribeWithError()
        } catch {
            #if DEBUG
            print("⚠️ club realtime subscribe failed: \(error)")
            #endif
        }
    }

    func unsubscribeFromClubUpdates() async {
        for task in clubRealtimeListenTasks { task.cancel() }
        clubRealtimeListenTasks.removeAll()
        clubRealtimeDebounceTask?.cancel()
        clubRealtimeDebounceTask = nil

        if let channel = clubRealtimeChannel {
            await channel.unsubscribe()
            clubRealtimeChannel = nil
        }
        clubRealtimeSubscribedId = nil
        clubOnlineMemberCount = 0
    }

    @MainActor
    private func scheduleClubRefresh(clubId: String) {
        clubRealtimeDebounceTask?.cancel()
        clubRealtimeDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard let self, !Task.isCancelled else { return }
            _ = try? await self.refreshClubBundle(clubId: clubId)
        }
    }

    /// Scans cached club bundles to find clubs that have this media item in a rail.
    func clubActivityForMedia(mediaId: Int, mediaType: String) -> [ClubMediaActivity] {
        let mt = mediaType.uppercased()
        var results: [ClubMediaActivity] = []
        for (_, cached) in clubBundleCache {
            let bundle = cached.value
            var matches: [ClubMediaActivityMatch] = []
            for rail in bundle.rails {
                for item in rail.items {
                    if item.media_id == mediaId && item.media_type.uppercased() == mt {
                        matches.append(ClubMediaActivityMatch(rail: rail, item: item))
                    }
                }
            }
            if !matches.isEmpty {
                results.append(ClubMediaActivity(
                    club: bundle.club,
                    memberCount: bundle.member_count,
                    sharingLevel: bundle.club.sharing_level,
                    members: bundle.members,
                    matchingItems: matches
                ))
            }
        }
        return results
    }
}
#endif
