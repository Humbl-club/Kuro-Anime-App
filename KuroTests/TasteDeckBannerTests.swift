//
//  TasteDeckBannerTests.swift
//  KuroTests
//
//  The Taste deck's "didn't save" banner rule (E6b-V fix round): the deck reads the TasteStore outbox's
//  current state, so the copy must match it. "will retry" only while a repeatedly failing signal is
//  still queued; a dropped signal (queue full, attempts used up) is never promised a retry.
//

import Testing
import Foundation
import KuroCore
@testable import Kuro

@MainActor
@Suite("Taste: deck 'didn't save' banner")
struct TasteDeckBannerTests {
    enum OutboxState: String, CaseIterable, Sendable {
        case nothingWrong
        case failingSignalStillQueued
        case signalDropped
        case droppedWhileAFreshSignalWaits
    }

    static func signal(_ id: Int, failures: Int) -> TasteStore.PendingSignal {
        TasteStore.PendingSignal(
            token: id,
            card: MediaKey(kind: .anime, id: id),
            action: .love,
            failures: failures,
            notBefore: Date(timeIntervalSince1970: 0)
        )
    }

    static func state(_ outbox: OutboxState) -> (needsAttention: Bool, pending: [TasteStore.PendingSignal], banner: String?) {
        switch outbox {
        case .nothingWrong:
            return (false, [signal(1, failures: 1)], nil)
        case .failingSignalStillQueued:
            return (true, [signal(1, failures: TasteStore.attentionAfterFailures)], "Signal didn't save — will retry")
        case .signalDropped:
            return (true, [], "Signal didn't save")
        case .droppedWhileAFreshSignalWaits:
            return (true, [signal(2, failures: 0)], "Signal didn't save")
        }
    }

    @Test("The banner matches the outbox: 'will retry' only while a failing signal is still queued",
          arguments: OutboxState.allCases)
    func bannerMatchesTheOutbox(outbox: OutboxState) {
        let state = Self.state(outbox)
        #expect(TasteDeckModel.signalBanner(needsAttention: state.needsAttention, pending: state.pending) == state.banner)
    }
}
