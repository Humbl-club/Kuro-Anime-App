@gated
Feature: Home Screen widget (needs decision D-E: App Group registered)

  @swift:WidgetSnapshotBuilderTests/snapshotShowsNextReleaseAndNowWatching
  Scenario: The widget shows what is next
    Given I watch two airing shows
    Then the widget snapshot lists the next confirmed release and Now Watching

  @swift:WidgetIntentInboxTests/queuedAdvanceDrainsThroughLibraryActions
  Scenario: +1 from the widget
    Given I tapped +1 on the widget
    When Kuro becomes active
    Then the progress goes up once through the library writer

  @swift:WidgetSnapshotWriterTests/signOutClearsSnapshot
  Scenario: Nothing private after sign-out
    When I sign out
    Then the widget shows the signed-out state

  @manual:release-build-with-widget @owner-gate
  Scenario: The shipped build contains the widget
    Given the App Group is registered
    Then the TestFlight build embeds KuroWidgets and the release candidate check passes
