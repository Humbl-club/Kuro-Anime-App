# Catalogue sources without AniList. Spec: docs/superpowers/specs/2026-11-09-catalogue-sources-design.md
# One test tag per scenario: @deno (offline Deno test), @sql (local DB harness), @swift (package/app
# unit test), @ui (app UI test), @report (comparator run on live data, read-only, with run id),
# @manual (only with @owner-gate), @gated (skipped until its gate is decided).

Feature: Kuro's catalogue comes from sources whose terms allow it

  # ---------- Foundation ----------

  @sql
  Scenario: Source tables are private to the service
    Given the catalogue sources migration is applied
    Then anon and authenticated have no SELECT, INSERT, UPDATE or DELETE on catalogue_source_records, catalogue_id_links, catalogue_shadow_values, catalogue_cutover and catalogue_rollback_snapshots
    And every new function sets search_path to public, extensions

  @sql
  Scenario: Every field group starts on AniList
    Given the catalogue sources migration is applied
    Then catalogue_cutover has one row per field group, each with mode "anilist"

  @sql
  Scenario: An accepted link is unique on both sides
    Given anime 101 has an accepted link to ANN anime 5000
    When another accepted link from anime 102 to ANN anime 5000 is inserted
    Then the insert fails with a unique violation
    And a second accepted ANN link for anime 101 also fails

  @deno
  Scenario: An unchanged source record writes nothing
    Given an ANN record for anime 5000 was stored with payload hash H
    When the ANN handler fetches the same payload again
    Then no row in catalogue_source_records is updated

  @deno
  Scenario: Requests identify Kuro with a working contact
    When any catalogue source client sends a request
    Then its User-Agent is "Kuro-Catalogue/1.0 (+https://kuro-legal.vercel.app/kontakt.html)"

  # ---------- Identity ----------

  @deno
  Scenario: Wikidata links a title through the AniList id we hold
    Given anime 101 has anilist_id 16498
    And Wikidata item Q123 has AniList anime ID 16498, ANN anime ID 14713 and MyAnimeList anime ID 16498
    When the Wikidata crosswalk runs
    Then anime 101 has accepted links wikidata Q123, ann 14713 and mal 16498 with method "wikidata"

  @deno
  Scenario: Two Wikidata items claiming the same AniList id link nothing
    Given Wikidata items Q1 and Q2 both carry AniList anime ID 16498
    When the Wikidata crosswalk runs
    Then anime 101 gets no accepted Wikidata link
    And the conflict is listed in the run results

  @deno
  Scenario: A unique long-tail title match is accepted, an ambiguous one is proposed
    Given anime 202 "Kaiju Gakuen" (TV, 2009) has no Wikidata link
    And the ANN title report has exactly one TV title normalising to "kaiju gakuen" with vintage 2009
    And anime 203 matches two ANN titles equally well
    When the ANN matcher runs
    Then anime 202 has an accepted ANN link with method "title_match"
    And anime 203 has two proposed ANN links and is on the review list

  # ---------- Shadow ----------

  @deno
  Scenario: Precedence picks the first source that has a value
    Given Wikidata has no English label for anime 101 and ANN has "Attack on Titan"
    When the composer runs for anime 101
    Then the shadow title_english is "Attack on Titan" with source "ann"

  @deno
  Scenario: The adult flag is set when any source says adult
    Given MangaUpdates lists genre "Hentai" for manga 300 and Wikidata has no genre
    When the composer runs for manga 300
    Then the shadow is_adult is true

  @deno
  Scenario: A title adult today never turns non-adult on its own
    Given manga 301 has is_adult true today and no source marks it adult
    When the composer runs for manga 301
    Then the shadow is_adult is true and manga 301 is on the adult review list

  @deno
  Scenario: The MangaUpdates budget is shared with release intake
    Given release-intake's MangaUpdates schedule
    When the catalogue MangaUpdates schedule is built
    Then the two never run in the same minute and every request waits at least 1.1 s after the previous one

  @deno
  Scenario: Schedules finish a full pass in the time the spec states
    Given the per-source rate constants and the 2026-11-09 catalogue counts
    When initial-pass and refresh times are computed
    Then each is within 10 % of the throughput table in spec section 3.1

  @report
  Scenario: The comparator reports coverage and agreement per tier
    When catalogue_shadow_report_v1 runs on live data
    Then it returns, per field group and tier (top 1k, top 5k, in lists, curated, all), the coverage count, the agreement count and the disagreement sample

  # ---------- Cutover ----------

  @deno
  Scenario: The AniList importer leaves a cut-over group alone
    Given field group "facts" has mode "new"
    When bulk-import-anime processes a changed AniList payload for anime 101
    Then the update contains no facts columns (format, status, dates, episodes, duration, season, country_of_origin)
    And it still writes the groups that are on "anilist"

  @deno
  Scenario: Publish writes only groups in "new" mode
    Given field group "titles" has mode "new" and "facts" has mode "shadow"
    When the publish handler runs for anime 101
    Then title columns are updated from shadow values
    And facts columns are unchanged

  @deno
  Scenario: Rollback restores the snapshot without asking AniList
    Given field group "credits" was switched to "new" and published, which snapshotted anime 101's credits
    When the group is switched back to "anilist" and restore runs
    Then anime 101's studios, characters and staff links equal the pre-switch rows
    And no column was null at any step
    And the AniList client received no requests

  @deno
  Scenario: The importer's unchanged-payload path also skips a switched group
    Given field group "episodes" has mode "new"
    And AniList returns anime 101 with an unchanged updatedAt but a new next episode
    When bulk-import-anime processes it
    Then no update is sent for anime 101

  @deno
  Scenario: The importer leaves a switched group's linked tables alone
    Given field group "links" has mode "new" and "tags" has mode "anilist"
    When bulk-import-anime processes a changed payload for anime 101
    Then external_links is not written
    And anime_tags is written

  @deno
  Scenario: Release intake stops writing airing times once episodes switched
    Given field group "episodes" has mode "new"
    When release-intake runs its airing pass
    Then anime next_airing_at is not updated
    And release events are still recorded

  @deno
  Scenario: Image mirroring skips switched titles
    Given field group "images" has mode "new"
    When mirror-images runs
    Then no cover or banner column is rewritten

  @sql
  Scenario: List-only titles leave browsing but stay in lists
    Given manga 400 has catalogue_visibility "list_only" and is in a user's list
    Then every reader in the visibility inventory omits manga 400
    And the list read, the export identity lookup and the detail read still return it

  @deno
  Scenario: A new title is linked, not duplicated, when it already exists
    Given ANN anime 6000 has no accepted link and its title matches anime 101 above the threshold
    When create runs in insert mode
    Then anime 101 gets an accepted ANN link 6000
    And no new anime row is inserted

  @deno
  Scenario: Before AniList is off, new titles are only reported
    Given create runs in report mode
    Then no catalogue row is inserted and the would-create list is in the run results

  @deno
  Scenario: A credited person already in the catalogue is reused
    Given Wikidata links ANN person 1000 to AniList staff 95000, held by staff row 7
    When ANN credits for anime 101 are resolved
    Then the credit points to staff row 7 and no staff row is created

  @swift
  Scenario: A hidden-from-browse title stays in the user's list
    Given the user's list contains manga 400, which no allowed source knows
    When the Collection loads
    Then manga 400 is shown with its stored title

  @ui
  Scenario: Title pages credit their sources
    Given anime 101's published data comes from ANN and Wikidata
    When the title page is opened
    Then a "Sources" line reads "Data: Anime News Network, Wikidata"
    And "Anime News Network" opens the title's ANN page

  # ---------- Gated content ----------

  @gated
  Scenario: Episodes and next airing come from the L1 provider
    Given gate L1 chose a provider and anime 101 is airing
    When the episodes handler runs
    Then anime 101's next_airing_at is within 24 h of the provider's next episode time

  @gated
  Scenario: Synopses never use AniList text
    Given gate L2 is decided
    When the synopsis worker builds its input for anime 101
    Then the input contains no AniList description

  @manual @owner-gate
  Scenario: Owner approves a field group cutover
    Given the comparator shows the field group's gate in section 6 met for 3 consecutive daily runs
    When the owner reviews the report
    Then the owner sets the group to "new" or records why not

  @manual @owner-gate
  Scenario: Owner authorises switching AniList off
    Given every field group has been "new" for at least 14 days with no gate regressed
    When the owner authorises Task 17
    Then the four AniList import cron jobs, AniList airing in release-intake and the s4.anilist.co mirror host are disabled
