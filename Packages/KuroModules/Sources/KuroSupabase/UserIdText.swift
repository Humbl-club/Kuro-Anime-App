import KuroCore

/// The single decision point for the text the app sends as a legacy TEXT `user_id`: in every filter
/// and insert body on `anime_user_lists` / `manga_user_lists` (this adapter), in the realtime filters on
/// those tables and in the `user_airing_next` filter (app).
///
/// F16 (canonical form): the SDK reports the session user as `User.id.uuidString`, which is UPPER-case,
/// while the captured list-table RLS compares the TEXT column with `auth.uid()::text`, which PostgreSQL
/// renders lower-case; an upper-case id containing hex letters is rejected by that comparison. The id
/// therefore leaves the client in the canonical lower-case form, decided here and nowhere else.
/// Historical rows stored with another casing are the SQL side's to normalise (a forward migration,
/// qualified against the effective schema); the account's identity itself (`AccountContext.userId`)
/// keeps the SDK's spelling and compares case-insensitively.
public enum UserIdText {
    public static func value(for account: AccountContext) -> String {
        account.userId.lowercased()
    }
}
