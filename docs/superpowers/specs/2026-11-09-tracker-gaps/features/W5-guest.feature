Feature: Browse before signing up

  Rule: Signed-out people can look around

    @ui:GuestBrowsingUITests/testSignedOutLaunchShowsDiscoverNotAuthWall
    Scenario: First launch without an account
      Given I have never signed in
      When I open Kuro
      Then I see Discover with Search and Browse available
      And Home, Collection, Taste and Clubs show an invitation to create an account

    @swift:GuestModeTests/flagOffSendsNoRequest
    Scenario: Guest browsing switched off on the server
      Given the guest_browsing_v1 flag is off
      When I open Kuro without an account
      Then I see the sign-in screen
      And Kuro sends nothing but the flag read

    @swift:GuestModeTests/guestCanOpenTitleEntityAndSeasonPages
    Scenario: Opening pages as a guest
      Given I am a guest
      When I open a title, a character and a season overview
      Then each page loads public catalogue data only

  Rule: Saving asks for an account and then finishes what I started

    @swift:GuestModeTests/saveAsGuestOpensSignUpWithPendingIntent
    Scenario: Saving as a guest
      Given I am a guest on a title page
      When I tap Plan
      Then the sign-up sheet opens and says Kuro keeps nothing on this phone until I have an account

    @swift:GuestModeTests/pendingIntentReplaysOnceAfterSignUp
    Scenario: The pending action completes after sign-up
      Given I tapped Plan on "Frieren" as a guest
      When I finish sign-up
      Then "Frieren" is in my Planning list exactly once
      And a banner confirms it

    @swift:GuestModeTests/pendingIntentDiscardedWhenSignUpCancelled
    Scenario: Cancelling sign-up forgets the action
      Given I tapped Plan as a guest
      When I cancel sign-up
      Then nothing is saved and no later sign-in replays it

  Rule: The anonymous role can do only what guests need

    @sql:rls/106_guest_anon_allowlist.sql
    Scenario: Anonymous EXECUTE is an explicit allowlist
      Given the list of read RPCs that guest pages call
      Then the anon role can execute exactly those
      And the anon role cannot execute any function that writes or reads private data

    @load:guest-browse
    Scenario: Guest traffic stays inside the budgets
      Given anonymous Discover, Search, Browse and Detail at 5 requests per second on top of the unchanged 20 requests per second qualification mix
      Then each class meets its p95 budget and no request fails
      And the base mix's result is not worse than without guests
