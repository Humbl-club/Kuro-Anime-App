Feature: Export your list
  People must be able to take their whole list with them, for free, in formats other trackers read.

  Rule: The MyAnimeList file round-trips through Kuro's own importer

    @pkg:LibraryExportTests/malXmlRoundTripPreservesEveryMappedEntry
    Scenario: Exported MAL XML re-imports without changes
      Given a library with anime and manga entries in every status, with progress, scores, notes, repeat counts and dates
      And every entry has a MyAnimeList id
      When I export it as MyAnimeList XML
      And the files are parsed by MALExportParser
      Then every entry comes back with the same status, progress, score, notes, repeat count and dates

    @pkg:LibraryExportTests/entriesWithoutMalIdAreReportedNotDropped
    Scenario: Titles without a MyAnimeList id are reported, not silently dropped
      Given a library where 2 titles have no MyAnimeList id
      When I export it as MyAnimeList XML
      Then the XML contains every other entry
      And the export summary lists the 2 titles by name
      And the CSV and JSON exports still contain all titles

    @pkg:LibraryExportTests/malXmlSplitsLargeLibrariesIntoReimportableParts
    Scenario: A very large MyAnimeList file is split into parts the importer accepts
      Given 2,000 anime entries whose notes are each 16,384 bytes of "&", "<", ">" and quote characters
      When I export it as MyAnimeList XML
      Then the export is split into numbered files like "kuro-anime-2026-11-09-part1.xml"
      And every file is within the importer's size and item limits
      And every file parses on its own and together they return all 2,000 entries with identical notes

  Rule: CSV and JSON keep everything Kuro knows

    @pkg:LibraryExportTests/csvHasDocumentedHeaderAndEscapesText
    Scenario: CSV columns and escaping
      Given an entry whose notes contain a comma, a quote and a line break
      When I export CSV
      Then the first row is the documented header
      And the notes cell round-trips exactly through an RFC 4180 reader

    @pkg:LibraryExportTests/csvNeutralisesFormulaCellsAndJsonKeepsExactText
    Scenario: Spreadsheet formulas in my text are neutralised in CSV but kept exact in JSON
      Given entries whose notes start with "=", "+", "-", "@", a tab or a carriage return
      When I export CSV and JSON
      Then each of those CSV cells starts with an apostrophe before the original text
      And a cell with the same character later in the text is unchanged
      And the JSON file keeps every note exactly as I wrote it

    @pkg:LibraryExportTests/jsonCarriesIdsTagsListsAndDates
    Scenario: JSON is full fidelity
      Given an entry with tags, custom lists, a partial start date and imported ids
      When I export JSON
      Then the entry carries Kuro, AniList and MyAnimeList ids, tags, list names and the dates at their original precision
      And it carries the tracking unit it points at, or null when none is stored

    @pkg:LibraryExportTests/jsonExportsListsInManualOrderWithItemsOutsideTheLibrary
    Scenario: My custom lists export as lists, in my order
      Given a list "Comfort" with three titles in my drag order, one of them no longer in my library
      And an empty list "Empty one"
      When I export JSON
      Then both lists appear as separate objects with id, name and creation date, in the order I see them
      And "Comfort" lists its titles in my order with positions 1, 2 and 3
      And the title no longer in my library is kept and marked as not in the library
      And the empty list is exported with no items

    @pkg:LibraryExportTests/summaryDistinguishesCompleteIdentityAndOrganisationGaps
    Scenario: The export says whether it is complete
      Given an export where every id was found and tags and lists loaded
      Then the summary and the JSON file say the export is complete
      But when some ids could not be looked up the export names that gap
      And when tags and lists could not be loaded the export names that gap
      And both gaps can be named at once

  Rule: Export is a tool reachable from Profile and never costs money

    @swift:LibraryExportFlowTests/exportSheetSharesFilesForSignedInAccount
    Scenario: Exporting from Profile
      Given I am signed in with 25 titles
      When I open Profile, choose "Export your list" and pick CSV
      Then a share sheet offers one CSV file named with today's date

    @swift:LibraryExportFlowTests/exportWorksOfflineWithCachedCatalogueOrReportsMissingIds
    Scenario: Exporting offline
      Given I am offline and my library is loaded
      When I export CSV
      Then the file contains every entry
      And any MyAnimeList id that could not be looked up is reported in the summary

    @swift:LibraryExportFlowTests/identityLookupNeverSendsOldLibraryWithNewCredentials
    Scenario: Switching accounts during an export never sends my titles under the other account
      Given account A started an export and the id lookup has not been sent yet
      When the phone switches to account B
      Then no lookup of A's titles is sent with B's sign-in
      And no file is shared and nothing of A's is kept

    @swift:LibraryExportFlowTests/flagOffSendsNoRequest
    Scenario: Export sends nothing until it is released
      Given the export switch is off for my account
      When an export is started
      Then no request is sent and no file is written

    @load:export-mal-id-lookup
    Scenario: The id lookup stays inside the Browse budget
      Given the populated qualification fixture whose libraries hold real catalogue ids, up to 2,000 titles
      When the export's id lookup runs in qualification mode at its declared 0.2 requests per second, in batches of at most 500 ids
      Then each batch meets the Browse class p95 of 750 ms
      And it has at least 100 completions and at least 30 per library size, otherwise the result is "insufficient"
