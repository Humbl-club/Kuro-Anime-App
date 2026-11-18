Feature: Up next in your series

  @sql:rls/109_library_up_next.sql
  Scenario: Sequels of completed titles that I don't have yet
    Given I completed season 1 and season 2 exists in the catalogue
    And season 2 is not in my library
    When Collection loads "Up next in your series"
    Then season 2 is listed with "Sequel to <season 1>"
    And titles already in my library or dismissed are not listed

  @sql:rls/109_library_up_next_signed_out.sql
  Scenario: Another account's library is never read
    Then the RPC derives the account from the token and returns nothing for a signed-out caller

  @swift:UpNextStoreTests/planFromUpNextAddsToPlanningAndRemovesRow
  Scenario: One tap to plan
    When I tap Plan on an up-next title
    Then it is added to Planning and leaves the section with a stamp and Undo

  @swift:UpNextStoreTests/dismissHidesTitleForThisAccount
  Scenario: Dismissing
    When I choose "Not interested"
    Then it disappears and stays hidden for this account

  @swift:UpNextStoreTests/planOfAnExistingEntryOffersNoUndo
  Scenario: Plan on a title I already have offers no Undo
    Given an up-next title is already in my library
    When I tap Plan on it
    Then nothing changes, I am told it is already in my library, and no Undo is offered

  @swift:UpNextStoreTests/undoPlanRefusedAfterTheEntryChanged
  Scenario: Undo never removes an entry I changed after planning it
    Given I planned an up-next title
    And I then changed its progress, only its start date, its repeat count, or removed and re-added it
    When I tap Undo on the plan
    Then the entry stays in my library and I am told it was not undone

  @swift:UpNextStoreTests/flagOffSendsNoRequest
  Scenario: Hidden and silent while the switch is off
    Given the "collection_up_next_v1" switch is off
    When I open Collection's Completed view
    Then no up-next request is sent and the section does not appear

  @swift:UpNextStoreTests/preDispatchSwitchNeverSendsUpNextReadAsB
  Scenario: Up next is never read as the next account
    Given Collection started loading "Up next in your series" for account A
    When the app switches to account B before the request leaves
    Then nothing is sent, and certainly not with B's sign-in

  @load:collection-up-next
  Scenario: The section stays within budget
    Given the populated 2,000-title fixture in which completed titles have sequels I do not own
    When the profile runs in qualification mode with the up-next read, Plan and Not interested, and their Undos
    Then the up-next RPC meets the Browse class p95 of 750 ms and the writes meet the Progress class p95 of 750 ms
    And every endpoint has at least 100 completions and every library-size group at least 30, otherwise the result is "insufficient"
    And afterwards each account's up-next answer is what it was before the run and no up-next title is left in its library

  @gated @owner-gate
  Rule: Dub info and where to watch (needs decision D-C)

    @manual:awaits-D-C @owner-gate
    Scenario: Rewritten when the data source is chosen
      Given the owner chose a data source for D-C
      Then this rule is rewritten with its scenarios
