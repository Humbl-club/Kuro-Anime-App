import Foundation
import KuroCore
import KuroLibrary
import Testing

@Suite("Custom list order")
struct CustomListOrderTests {
    private func slots(_ count: Int) -> [CustomListSlot] {
        (1...count).map {
            CustomListSlot(itemId: UUID(), key: MediaKey(kind: .anime, id: $0), position: 1024 * Double($0))
        }
    }

    private func ids(_ slots: [CustomListSlot]) -> [Int] { CustomListOrder.ordered(slots).map(\.key.id) }

    @Test func moveWritesOnePositionAndKeepsOrder() throws {
        let old = slots(200)
        let move = CustomListOrder.move(old, from: 149, to: 2)
        #expect(move == .single(itemId: old[149].itemId, position: 2560, after: 2048, before: 3072))

        guard case let .single(itemId, position, _, _) = move else { Issue.record("expected single"); return }
        var new = old
        let index = try #require(new.firstIndex { $0.itemId == itemId })
        new[index].position = position
        let expected = [1, 2, 150] + Array(3...149) + Array(151...200)
        #expect(ids(new) == expected)
        let changed = zip(old, new).filter { $0.position != $1.position }.count
        #expect(changed == 1)

        let reloaded = try JSONDecoder().decode([CustomListSlot].self, from: JSONEncoder().encode(new))
        #expect(ids(reloaded) == expected)
    }

    @Test func headAndTailMoves() {
        let old = slots(200)
        #expect(CustomListOrder.move(old, from: 5, to: 0)
                == .single(itemId: old[5].itemId, position: 0, after: nil, before: 1024))
        let tailPosition: Double = 201 * 1024
        let tailAfter: Double = 200 * 1024
        let tail = CustomListOrder.move(old, from: 0, to: 199)
        #expect(tail == .single(itemId: old[0].itemId, position: tailPosition, after: tailAfter, before: nil))
        #expect(CustomListOrder.move(old, from: 3, to: 3) == .none)
    }

    @Test func exhaustedGapRebalances() {
        let base = slots(3)
        let tight = [
            CustomListSlot(itemId: base[0].itemId, key: base[0].key, position: 1),
            CustomListSlot(itemId: base[1].itemId, key: base[1].key, position: 1.0.nextUp),
            CustomListSlot(itemId: base[2].itemId, key: base[2].key, position: 3),
        ]
        guard case let .rebalance(result) = CustomListOrder.move(tight, from: 2, to: 1) else {
            Issue.record("expected rebalance"); return
        }
        #expect(result.map(\.position) == [1024, 2048, 3072])
        #expect(result.map(\.key.id) == [1, 3, 2])
    }

    @Test func tiesBreakByItemIdLikeTheServer() {
        let low = UUID(uuidString: "00000000-0000-4000-8000-000000000001") ?? UUID()
        let high = UUID(uuidString: "FFFFFFFF-0000-4000-8000-000000000001") ?? UUID()
        let a = CustomListSlot(itemId: high, key: MediaKey(kind: .anime, id: 1), position: 5)
        let b = CustomListSlot(itemId: low, key: MediaKey(kind: .anime, id: 2), position: 5)
        #expect(CustomListOrder.ordered([a, b]).map(\.key.id) == [2, 1])
    }

    @Test func onMoveOffsetsMapToFinalIndex() {
        #expect(CustomListOrder.indices(fromOffsets: [149], toOffset: 2)?.from == 149)
        #expect(CustomListOrder.indices(fromOffsets: [149], toOffset: 2)?.to == 2)
        #expect(CustomListOrder.indices(fromOffsets: [2], toOffset: 150)?.to == 149)
        #expect(CustomListOrder.indices(fromOffsets: [1, 4], toOffset: 0) == nil)
    }

    @Test func appendPositionIsLastPlusSpacing() {
        #expect(CustomListOrder.appendPosition(after: []) == 1024)
        #expect(CustomListOrder.appendPosition(after: slots(3)) == 4096)
    }
}
