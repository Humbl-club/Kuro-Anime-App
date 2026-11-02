import Foundation
import KuroCore
import KuroLibrary

/// One progress/status mutation sent to `apply_progress_mutations_v1`.
public struct LibraryFenceProgressMutation: Sendable, Equatable, Encodable {
    public let mutationId: UUID
    public let medium: String
    public let mediaId: Int
    public let lifecycleId: UUID
    public let baseRevision: Int64
    public let position: Int?
    public let positionLabel: String?
    public let status: String?

    public init(
        mutationId: UUID,
        medium: String,
        mediaId: Int,
        lifecycleId: UUID,
        baseRevision: Int64,
        position: Int? = nil,
        positionLabel: String? = nil,
        status: String? = nil
    ) {
        self.mutationId = mutationId
        self.medium = medium
        self.mediaId = mediaId
        self.lifecycleId = lifecycleId
        self.baseRevision = baseRevision
        self.position = position
        self.positionLabel = positionLabel
        self.status = status
    }

    enum CodingKeys: String, CodingKey {
        case mutationId = "mutation_id"
        case medium
        case mediaId = "media_id"
        case lifecycleId = "lifecycle_id"
        case baseRevision = "base_revision"
        case position
        case positionLabel = "position_label"
        case status
    }
}

/// One removal mutation sent to `apply_remove_mutations_v1`.
public struct LibraryFenceRemoveMutation: Sendable, Equatable, Encodable {
    public let mutationId: UUID
    public let medium: String
    public let mediaId: Int
    public let lifecycleId: UUID
    public let baseRevision: Int64

    public init(
        mutationId: UUID,
        medium: String,
        mediaId: Int,
        lifecycleId: UUID,
        baseRevision: Int64
    ) {
        self.mutationId = mutationId
        self.medium = medium
        self.mediaId = mediaId
        self.lifecycleId = lifecycleId
        self.baseRevision = baseRevision
    }

    enum CodingKeys: String, CodingKey {
        case mutationId = "mutation_id"
        case medium
        case mediaId = "media_id"
        case lifecycleId = "lifecycle_id"
        case baseRevision = "base_revision"
    }
}

/// Per-item outcome from a fence RPC.
public struct LibraryFenceItemResult: Sendable, Equatable, Decodable {
    public let mutationId: String
    public let outcome: String
    public let serverRevision: Int64?
    public let position: Int?
    public let notes: String?
    public let rating: Int?
    public let status: String?

    enum CodingKeys: String, CodingKey {
        case mutationId = "mutation_id"
        case outcome
        case serverRevision = "server_revision"
        case position, notes, rating, status
    }
}

public struct LibraryFenceBatchResult: Sendable, Equatable, Decodable {
    public let items: [LibraryFenceItemResult]
}

/// RPC seam for receipt-safe progress, status, and removal. Separate from row CRUD so
/// notes/rating can keep using PATCH while tracked field writers go through the fence.
public protocol LibraryFenceTransport: Sendable {
    func applyProgressMutations(_ mutations: [LibraryFenceProgressMutation]) async throws -> LibraryFenceBatchResult
    func applyRemoveMutations(_ mutations: [LibraryFenceRemoveMutation]) async throws -> LibraryFenceBatchResult
}
