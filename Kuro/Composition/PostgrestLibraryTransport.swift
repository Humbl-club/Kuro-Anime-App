import Foundation
import KuroSupabase

#if canImport(Supabase)
import Supabase

/// `LibraryRowTransport` over the app's single supabase-swift client.
///
/// A dumb binding: every table, column, filter, body, order and range is decided by
/// `SupabaseLibraryBackend` and mapped 1:1 onto the SDK builders (supabase-swift 2.54.1):
/// - select: `GET ?select=<columns>&user_id=eq.<id>[&<media>_id=eq.<id>]&order=<column>.asc.nullslast&offset=&limit=`
/// - patch: `PATCH ?user_id=eq.<id>&<media>_id=eq.<id>&select=<columns>`, `Prefer: return=representation`
/// - insert: `POST ?on_conflict=<columns>&select=<columns>`, `Prefer: resolution=ignore-duplicates,return=representation`
/// - delete: `DELETE ?user_id=eq.<id>&<media>_id=eq.<id>`
/// Bodies are `[String: AnyJSON]`, so a cleared field is an explicit JSON `null`. Rows are decoded by
/// the SDK's PostgREST decoder (the same decoder the pre-Library list fetch used for `created_at` /
/// `updated_at`). SDK failures are mapped onto `LibraryTransportError`; the adapter maps those onto
/// `LibraryError`.
nonisolated struct PostgrestLibraryTransport: LibraryRowTransport, LibraryFenceTransport {
    let client: SupabaseClient

    func select(_ request: LibraryRowSelect) async throws -> [LibraryRow] {
        try await Self.mapped {
            var query = client.from(request.table)
                .select(request.columns)
                .eq("user_id", value: request.userId)
            if let mediaId = request.mediaId {
                query = query.eq(request.mediaColumn, value: mediaId)
            }
            return try await query
                .order(request.orderColumn, ascending: true)
                .range(from: request.offset, to: request.offset + request.limit - 1)
                .execute()
                .value
        }
    }

    func patch(_ request: LibraryRowPatch) async throws -> [LibraryRow] {
        try await Self.mapped {
            try await client.from(request.table)
                .update(Self.json(request.body), returning: .representation)
                .eq("user_id", value: request.userId)
                .eq(request.mediaColumn, value: request.mediaId)
                .select(request.columns)
                .execute()
                .value
        }
    }

    func insertIgnoringDuplicates(_ request: LibraryRowInsert) async throws -> [LibraryRow] {
        try await Self.mapped {
            try await client.from(request.table)
                .upsert(
                    Self.json(request.body),
                    onConflict: request.onConflict,
                    returning: .representation,
                    ignoreDuplicates: true
                )
                .select(request.columns)
                .execute()
                .value
        }
    }

    func delete(_ request: LibraryRowDelete) async throws {
        try await Self.mapped {
            _ = try await client.from(request.table)
                .delete()
                .eq("user_id", value: request.userId)
                .eq(request.mediaColumn, value: request.mediaId)
                .execute()
        }
    }

    func applyProgressMutations(_ mutations: [LibraryFenceProgressMutation]) async throws -> LibraryFenceBatchResult {
        try await Self.mapped {
            try await client
                .rpc("apply_progress_mutations_v1", params: FenceProgressParams(p_mutations: mutations))
                .execute()
                .value
        }
    }

    func applyRemoveMutations(_ mutations: [LibraryFenceRemoveMutation]) async throws -> LibraryFenceBatchResult {
        try await Self.mapped {
            try await client
                .rpc("apply_remove_mutations_v1", params: FenceRemoveParams(p_mutations: mutations))
                .execute()
                .value
        }
    }

    // MARK: Mapping

    static func json(_ body: [String: LibraryJSONValue]) -> [String: AnyJSON] {
        body.mapValues { value in
            switch value {
            case .string(let string): return .string(string)
            case .int(let int): return .integer(int)
            case .null: return .null
            }
        }
    }

    /// PostgREST error body -> `.server(status: nil, code:)` (the SDK does not expose the status of a
    /// decoded PostgREST error); any other non-2xx answer -> `.server(status:)`; `URLError` ->
    /// `.network`. Everything else (cancellation, decoding) is passed on for the adapter to map.
    static func transportError(_ error: any Error) -> any Error {
        switch error {
        case let error as PostgrestError:
            return LibraryTransportError.server(status: nil, code: error.code, message: error.message)
        case let error as HTTPError:
            return LibraryTransportError.server(
                status: error.response.statusCode,
                code: nil,
                message: String(decoding: error.data, as: UTF8.self)
            )
        case let error as URLError:
            return LibraryTransportError.network(message: error.localizedDescription)
        default:
            return error
        }
    }

    private struct FenceProgressParams: Encodable {
        let p_mutations: [LibraryFenceProgressMutation]
        enum CodingKeys: String, CodingKey { case p_mutations }
    }

    private struct FenceRemoveParams: Encodable {
        let p_mutations: [LibraryFenceRemoveMutation]
        enum CodingKeys: String, CodingKey { case p_mutations }
    }

    private static func mapped<T>(_ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch {
            throw transportError(error)
        }
    }
}
#endif
