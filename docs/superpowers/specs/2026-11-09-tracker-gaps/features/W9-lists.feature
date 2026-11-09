Feature: Organise my list my way

  @workstream-F2
  Rule: Repeat count and dates are editable (F2 contract)

    @pkg:LibraryEditV2Tests/repeatCountAndDatesTravelThroughLibraryEdit
    Scenario: Editing repeat count and dates
      Given an entry with no dates
      When I set repeat count 2, started "2024-05" and finished "2024-07-14"
      Then the entry stores them at that precision and the editor shows them

    @pkg:LibraryEditV2Tests/statusChangeFillsEmptyDatesWithUndo
    Scenario: Status changes fill empty dates
      Given the date auto-fill switch is on
      And an entry with no start date
      When I change its status to Watching
      Then the start date becomes today
      And Undo restores both status and the empty date

    @pkg:PartialDateTests/rejectsImpossibleDatesAndKeepsPrecision
    Scenario: Partial dates are validated
      Then "2024-02-30" is rejected, "2024" and "2024-02" keep their precision

    @pkg:LibraryEditV2Tests/flagOffSendsNoRequest
    Scenario: Date auto-fill sends nothing extra while its switch is off
      Given the date auto-fill switch is off
      And an entry with no start date
      When I change its status to Watching
      Then only the status change is sent and no date write follows
      And setting a date by hand in the editor is still one normal save

    @swift:FirstRunLaneTests/planUndoKeepsADatedPlan
    Scenario: Undo of a one-tap plan keeps a plan I have since dated
      Given I planned a title with the Plan key
      And I then set its start date or its rewatch count
      When I tap Undo on the Plan toast
      Then nothing is written and the title stays on my list with what I added

    @load:status-with-date-fill
    Scenario: Status changes with a date fill stay within budget
      Given the populated qualification fixture with a dedicated entry per account
      When status changes that fill and clear a date run at their declared rate in qualification mode
      Then the status write and the date write each meet the Progress class p95 of 750 ms
      And each has at least 100 completions and at least 30 per library size

  Rule: Tags

    @sql:rls/107_library_tags.sql
    Scenario: Tags are private and bounded
      Given account A tags an entry "comfy"
      Then account B cannot read or change it
      And an 11th tag on one entry and a 25-character tag are rejected

    @swift:LibraryTagsStoreTests/filterByTagShowsOnlyTaggedEntries
    Scenario: Filter Collection by tag
      Given entries tagged "comfy" and "rewatch"
      When I filter by "comfy"
      Then only "comfy" entries show

    @swift:LibraryTagsStoreTests/organiseSaveSendsOnlyTheDelta
    Scenario: Saving tags sends only what I changed
      Given the tags and lists sheet opened with "comfy" and list "L1"
      And my other device has since added "rewatch" and list "L2"
      When I add "slow burn", remove "comfy" and untick "L1", then save
      Then the app sends only those changes, never my whole tag set
      And the sheet shows "rewatch", "slow burn" and list "L2" afterwards

  Rule: Custom lists with manual order

    @sql:rls/108_custom_lists.sql
    Scenario: Custom lists are private, bounded and mixed-medium
      Given account A creates "Winter picks" with an anime and a manga
      Then account B cannot see it
      And a 51st list is rejected

    @pkg:CustomListOrderTests/moveWritesOnePositionAndKeepsOrder
    Scenario: Dragging writes one item row
      Given a list of 200 titles
      When I move the 150th title to position 3
      Then exactly one item's position changes and the order survives a reload

    @swift:CustomListsStoreTests/importedCustomListNamesCanSeedLists
    Scenario: Imported custom lists become Kuro lists on request
      Given an import carried custom list names "Favourites" and "To rewatch"
      When I choose "Create these lists"
      Then both lists exist with their titles

    @sql:concurrency/108_organisation_two_devices.sql
    Scenario: Two devices never overwrite each other's lists
      Given my tags and lists sheet is open on one device
      And my other device adds a tag and a list membership to the same title
      When I save on the first device
      Then the other device's tag and membership are kept
      And when both devices reorder the same list at once, the second reorder is refused as stale

    @swift:CustomListsStoreTests/staleReorderReloadsAndRetriesOnlyOnRequest
    Scenario: A reorder against a changed list is not saved silently
      Given my list changed on another device since it loaded
      When I drag a title
      Then the move is not saved, the list reloads and I am told it changed
      And the move is tried again only when I choose "Try again", and only once

    @swift:CustomListsStoreTests/exportListsKeepManualOrderEmptyListsAndRemovedTitles
    Scenario: Lists keep titles I removed from my library
      Given "Comfort" holds an anime I track and a manga I removed from my library, and "Later" is empty
      Then both titles stay in "Comfort" in my order and the manga is known to be no longer in my library
      And the lists handed to the export are "Comfort" in that order, removed manga included, and the empty "Later"

  Rule: Everything goes with the account

    @sql:rls/108_custom_lists_account_deletion.sql
    Scenario: Account deletion removes tags and lists
      When I delete my account
      Then my tags, lists and list items are gone

    @load:collection-with-tags-and-lists
    Scenario: Collection stays within budget
      Given the populated 2,000-title fixture with tags, 20 lists, one list of 2,000 titles and entries with 10 tags
      When the profile runs in qualification mode with reads and organisation writes (tag changes, list create, reorder, rebalance, seed from import)
      Then Collection reads meet the Browse class p95 of 750 ms and the writes meet the Progress class p95 of 750 ms
      And every endpoint has at least 100 completions and every library-size group at least 30, otherwise the result is "insufficient"
      And afterwards each account holds exactly its fixture lists and tags

  Rule: Release switch and account safety

    @swift:LibraryTagsStoreTests/flagOffSendsNoRequest
    Scenario: Tags stay hidden and silent while the switch is off
      Given the "library_organise_v1" switch is off
      When Collection opens and I try to load or save tags
      Then no request is sent and the tag words are hidden

    @swift:CustomListsStoreTests/flagOffSendsNoRequest
    Scenario: Lists stay hidden and silent while the switch is off
      Given the "library_organise_v1" switch is off
      When I try to load, create, reorder, remove from or seed lists
      Then no request is sent and "Your lists" is hidden

    @swift:OrganiseCredentialLeaseTests/preDispatchSwitchSendsNoOrganiseRequestAsB
    Scenario: A tag or list change is never sent as the next account
      Given I started a tag, list or order change as account A
      When the app switches to account B before the request leaves
      Then nothing of A's is sent, and certainly not with B's sign-in
