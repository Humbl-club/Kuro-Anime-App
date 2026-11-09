@gated
Feature: Two-way AniList sync (needs decision D-A: AniList authorization and API client)

  @manual:awaits-D-A @owner-gate
  Scenario: Linking shows what will change before anything is written
    Given I link my AniList account
    Then I see an identity preview with counts of additions, updates and conflicts before any write

  @manual:awaits-D-A @owner-gate
  Scenario: Kuro changes reach AniList within the rate limit
    Given I advance 10 episodes in Kuro
    Then the on-device queue sends at most one write every 2.5 seconds and shows its progress

  @manual:awaits-D-A @owner-gate
  Scenario: Conflicts are shown, never silently overwritten
    Given AniList and Kuro changed the same entry
    Then I choose which value wins and can undo the choice
