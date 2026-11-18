Feature: One list entry per series

  @pkg:SeriesListGroupingTests/reviewedContinuityMembersShareOneRow
  Scenario: Seasons in one reviewed continuity share a row
    Given I track season 1 (Completed) and season 2 (Watching, 5 of 12) of one reviewed continuity
    When Collection groups my list
    Then I see one row showing "S2 · 5/12"

  @pkg:SeriesListGroupingTests/unreviewedRelationsStayOwnRows
  Scenario: A relation without reviewed continuity is not merged
    Given two titles linked only by an AniList relation without reviewed continuity
    When Collection groups my list
    Then each title keeps its own row

  @pkg:SeriesListGroupingTests/activeMemberDecidesGroupStatus
  Scenario: Re-rating a finished season doesn't move a series I'm still watching
    Given season 2 of a reviewed series is Watching and season 1 is Completed
    When I re-rate season 1 after my last change to season 2
    Then the series stays in Watching showing season 2
    And +1 still advances season 2

  @pkg:SeriesListGroupingTests/advanceTargetsActiveMember
  Scenario: +1 advances the season I'm on
    Given a grouped row whose season 2 is Watching
    When I tap +1 on the row
    Then season 2's progress goes up by one and season 1 is unchanged

  @pkg:SeriesListGroupingTests/groupingNeverChangesEntries
  Scenario: Grouping is display only
    Given any library
    When it is grouped and ungrouped
    Then every entry's id, status, progress and imported ids are identical to before

  @swift:SeriesGroupingCollectionTests/expandShowsEverySeasonWithOwnStatus
  Scenario: Expanding a series
    Given a grouped row with 3 seasons
    When I expand it
    Then I see each season with its own status and +1

  @swift:SeriesGroupingCollectionTests/groupSeasonsSwitchIsRememberedPerAccount
  Scenario: Turning grouping off
    Given grouping is on
    When I switch "Group seasons" off and relaunch
    Then my list shows one row per entry
    And another account on the phone keeps its own choice

  @pkg:SeriesListGroupingTests/groupingTwoThousandEntriesWithinBudget
  Scenario: Grouping a large library is fast
    Given 2,000 entries
    When they are grouped
    Then grouping finishes within the baseline-confirmed budget (proposed 50 ms)

  @sql:rls/111_series_membership_read.sql
  Scenario: Only reviewed membership is read, through an index
    Given published, default-inserted, superseded and cross-medium series spans for 2,000 titles
    When the Collection reads membership for 300 of my titles
    Then only published same-medium spans are returned and the read uses the anime_id index

  @load:collection-series-membership
  Scenario: The membership read stays inside the Browse budget
    Given reviewed series membership is published and the qualification fixture names its member ids
    When the membership read runs in qualification mode at its declared 1 request per second on top of the unchanged base mix
    Then the read's p95 is at most 750 ms with zero errors
    And it has at least 100 completions and at least 30 per library size, otherwise the result is "insufficient"

  @swift:SeriesGroupingCollectionTests/flagOffSendsNoRequest
  Scenario: Grouping switched off on the server sends nothing
    Given the collection_series_grouping_v1 flag is off
    When I open Collection or add a title
    Then no membership or member-card request is sent
    And my list shows one row per entry
