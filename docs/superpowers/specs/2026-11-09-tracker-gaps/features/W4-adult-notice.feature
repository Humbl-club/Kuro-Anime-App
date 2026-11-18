Feature: Say plainly that 18+ titles are not listed

  @sql:rls/113_search_hidden_adult_count.sql
  Scenario: The search reports how many adult titles it left out
    Given the catalogue holds an adult title "X" and a non-adult title "Y"
    When a client searches for a query matching only "X"
    Then the search returns no rows and a hidden-adult count of 1
    And the adult title's name, id and picture are never returned

  @swift:AdultNoticeTests/searchShowsNoticeOnlyWhenAdultTitlesWereHidden
  Scenario: Search footnote
    Given my search hid 1 adult title
    Then I see "Kuro doesn't list 18+ titles" under the results
    And with a hidden count of 0 the line is absent

  @swift:AdultNoticeTests/importReviewLabelsAdultMatchesAndKeepsThemInUnresolvedFile
  Scenario: Import review explains missing adult titles
    Given my AniList import contains 3 adult titles
    When I review the import
    Then they are counted as "18+ — not listed in Kuro"
    And they appear in the unresolved download, not as failures

  @swift:AdultNoticeTests/flagOffSendsNoRequest
  Scenario: The notice switched off on the server asks for no count
    Given the server switch for the 18+ notice is off
    When I search for "velvet hush"
    Then no request for the hidden-adult count is sent
    And the search runs exactly as it does today

  @load:search-with-hidden-adult-count
  Scenario: Search stays within budget
    Given the qualification fixture whose search words match real catalogue titles
    When search with the hidden-adult count runs in qualification mode at its declared 1 request per second
    Then Search p95 stays at or below 750 ms
    And it has at least 100 completions and at least 30 per library size, otherwise the result is "insufficient"
