import Testing
import Foundation
@testable import Kuro

@MainActor
@Suite("Deep review failure reproductions", .timeLimit(.minutes(1)))
struct DeepReviewProbes {
 @Test("Revoked club's late friend response is still handed out")
 func lateRevokedFriendResponse() async throws {
  let slow=StubGate()
  let h=try PublicDataHarness { r in
   guard r.resource == "rpc/fetch_friend_activity_for_title" else {return .emptyArray}
   return StubResponse.json(#"{"friends_tracking":[{"user_id":"revoked-friend","display_name":"F","status":"CURRENT","progress":3,"rating":null,"updated_at":null}],"comments":[]}"#).held(by:slow)
  }
  await h.service.session.applySession(userId:LifecycleFixtures.userA,email:"a@example.com")
  let read=Task.immediate { @MainActor in try await h.service.social.fetchFriendActivityForTitle(mediaType:"ANIME",mediaId:101) }
  _=await h.server.waitForRequest {$0.resource == "rpc/fetch_friend_activity_for_title"}
  h.service.clubs.invalidateClub("revoked-club")
  slow.open()
  let result=try await read.value
  #expect(result.friends_tracking.first?.user_id == "revoked-friend", "Reproduces stale permission response, not desired behavior")
  await h.tearDown()
 }
 @Test("A's failed sign-in clears a later successful B sign-in")
 func lateFailedSignInEndsB() async throws {
  let slow=StubGate()
  let h=try SessionSDKHarness { r in
   if StubAuth.isAuth(r,"token") {
    if r.jsonObject?["email"] as? String == "a@example.com" {return StubResponse.json(#"{"error":"invalid_grant","error_description":"Invalid login credentials"}"#,status:400).held(by:slow)}
    return .json(StubAuth.sessionJSON(StubAuth.userB,email:"b@example.com"))
   }
   if StubAuth.isAuth(r,"logout") {return .json("",status:204)}
   return .emptyArray
  }
  let old=Task.immediate { @MainActor in try? await h.session.signInWithEmail(email:"a@example.com",password:"bad") }
  _=await h.server.waitForRequest {StubAuth.isAuth($0,"token") && $0.jsonObject?["email"] as? String == "a@example.com"}
  try await h.session.signInWithEmail(email:"b@example.com",password:"good")
  #expect(h.identity.currentUserId == StubAuth.userB)
  slow.open();_=await old.value
  #expect(!h.identity.isAuthenticated, "Reproduces newer account being cleared by old failure")
  await h.tearDown()
 }
 @Test("Parse begun before a tracking change refills the cleared cache afterward")
 func staleParseRefillsCache() async throws {
  let slow=StubGate()
  let h=try PublicDataHarness { r in
   if r.path.contains("/functions/v1/concierge-parse") {return StubResponse.json(ImportsContractTests.parseJSON).held(by:slow)}
   return .emptyArray
  }
  await h.service.session.applySession(userId:LifecycleFixtures.userA,email:"a@example.com")
  let read=Task.immediate { @MainActor in try await h.service.imports.conciergeParse(text:"naruto") }
  _=await h.server.waitForRequest {$0.path.contains("/functions/v1/concierge-parse")}
  h.service.imports.dropTrackingCopies()
  #expect(h.service.imports.conciergeParseCache.isEmpty)
  slow.open();_=try await read.value
  #expect(h.service.imports.conciergeParseCache.count == 1,"Reproduces stale pre-change result restoring cache")
  await h.tearDown()
 }
 @Test("A's comment mutation result is handed out after B signs in")
 func staleCommentMutationReturns() async throws {
  let slow=StubGate()
  let h=try PublicDataHarness { r in
   guard r.resource == "rpc/upsert_title_comment" else {return .emptyArray}
   return StubResponse.json(#"{"id":"comment-a","user_id":"account-a","text":"A private draft","created_at":"2026-10-05","updated_at":"2026-10-05"}"#).held(by:slow)
  }
  await h.service.session.applySession(userId:LifecycleFixtures.userA,email:"a@example.com")
  let write=Task.immediate { @MainActor in try await h.service.social.upsertTitleComment(mediaType:"ANIME",mediaId:101,text:"A private draft") }
  _=await h.server.waitForRequest {$0.resource == "rpc/upsert_title_comment"}
  await h.service.session.applySession(userId:LifecycleFixtures.userB,email:"b@example.com")
  slow.open();let result=try await write.value
  #expect(result.user_id == "account-a", "Reproduces old-account success being handed out")
  #expect(h.service.identity.currentUserId == LifecycleFixtures.userB)
  await h.tearDown()
 }
}
