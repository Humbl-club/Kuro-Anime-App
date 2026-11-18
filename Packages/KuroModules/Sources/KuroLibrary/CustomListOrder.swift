import Foundation
import KuroCore

/// One item of a custom list with its sparse server position.
public struct CustomListSlot: Equatable, Sendable, Codable {
    /// The list-item row id.
    public let itemId: UUID
    /// The title the row points at.
    public let key: MediaKey
    /// Sparse position; the server orders by `(position, id)`.
    public var position: Double

    /// Creates a slot.
    public init(itemId: UUID, key: MediaKey, position: Double) {
        self.itemId = itemId
        self.key = key
        self.position = position
    }

    private enum CodingKeys: String, CodingKey { case itemId, kind, id, position }

    /// Decodes a slot (the key is stored as kind + id).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        itemId = try c.decode(UUID.self, forKey: .itemId)
        let kind = try c.decode(MediaKind.self, forKey: .kind)
        key = MediaKey(kind: kind, id: try c.decode(Int.self, forKey: .id))
        position = try c.decode(Double.self, forKey: .position)
    }

    /// Encodes a slot.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(itemId, forKey: .itemId)
        try c.encode(key.kind, forKey: .kind)
        try c.encode(key.id, forKey: .id)
        try c.encode(position, forKey: .position)
    }
}

/// What a drag means for the server.
public enum CustomListMove: Equatable, Sendable {
    /// Nothing moved.
    case none
    /// Exactly one row changes. `after`/`before` are the neighbours' positions (nil at head/tail), sent to
    /// `move_custom_list_item_v1`, which recomputes the same position.
    case single(itemId: UUID, position: Double, after: Double?, before: Double?)
    /// The gap is exhausted: the full ordered list with positions `spacing * (i + 1)`.
    case rebalance([CustomListSlot])
}

/// Sparse-position ordering for custom lists, identical to the server's rule so a drag writes one item row.
public enum CustomListOrder {
    /// Gap used for head/tail placement and rebalancing.
    public static let spacing: Double = 1024

    /// `(position, itemId.uuidString.lowercased())` ascending, the server's `ORDER BY position, id`.
    public static func ordered(_ slots: [CustomListSlot]) -> [CustomListSlot] {
        slots.sorted {
            if $0.position != $1.position { return $0.position < $1.position }
            return $0.itemId.uuidString.lowercased() < $1.itemId.uuidString.lowercased()
        }
    }

    /// Moves the item at `from` to final index `to` (both indices in `ordered(slots)`).
    public static func move(_ slots: [CustomListSlot], from: Int, to: Int) -> CustomListMove {
        let list = ordered(slots)
        guard list.indices.contains(from), list.indices.contains(to), from != to else { return .none }
        var arranged = list
        let moved = arranged.remove(at: from)
        arranged.insert(moved, at: to)
        let after: Double? = to > 0 ? arranged[to - 1].position : nil
        let before: Double? = to + 1 < arranged.count ? arranged[to + 1].position : nil
        let candidate: Double?
        switch (after, before) {
        case (nil, nil): candidate = nil
        case let (nil, b?): candidate = b - spacing
        case let (a?, nil): candidate = a + spacing
        case let (a?, b?): candidate = (a + b) / 2
        }
        if let position = candidate, position.isFinite,
           after.map({ $0 < position }) ?? true, before.map({ position < $0 }) ?? true {
            return .single(itemId: moved.itemId, position: position, after: after, before: before)
        }
        return .rebalance(rebalanced(arranged))
    }

    /// SwiftUI `.onMove(fromOffsets:toOffset:)` to `(from, final index)` for a single-item move.
    public static func indices(fromOffsets: IndexSet, toOffset: Int) -> (from: Int, to: Int)? {
        guard fromOffsets.count == 1, let from = fromOffsets.first else { return nil }
        return (from, toOffset > from ? toOffset - 1 : toOffset)
    }

    /// Position for an item appended after `slots`.
    public static func appendPosition(after slots: [CustomListSlot]) -> Double {
        (slots.map(\.position).max() ?? 0) + spacing
    }

    /// Renumbers an ordered list `spacing * (i + 1)`.
    public static func rebalanced(_ ordered: [CustomListSlot]) -> [CustomListSlot] {
        ordered.enumerated().map {
            CustomListSlot(itemId: $1.itemId, key: $1.key, position: spacing * Double($0 + 1))
        }
    }
}
