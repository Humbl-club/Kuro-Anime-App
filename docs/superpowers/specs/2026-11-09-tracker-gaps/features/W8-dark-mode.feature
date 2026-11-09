@gated
Feature: Dark mode (needs decision D-D: dark palette accepted)

  @manual:awaits-D-D @owner-gate
  Scenario: Every screen renders with tokens in both appearances
    Given the Appearance setting is Dark
    Then every gallery screen renders with dark tokens and no raw colours

  @manual:awaits-D-D @owner-gate
  Scenario: Title text on artwork stays readable
    Then white text on ArtworkMaterial keeps a contrast of at least 7:1 in dark

  @manual:awaits-D-D @owner-gate
  Scenario: The choice is remembered
    Given I choose System, Light or Dark
    Then the app follows it after relaunch
