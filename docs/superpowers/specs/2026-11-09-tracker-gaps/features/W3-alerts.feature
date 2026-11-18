Feature: Release alerts people actually turn on

  Rule: The offer appears at the moment it matters and never prompts by itself

    @swift:ReleaseAlertOfferTests/offerShownAfterSavingAiringTitleWithExactNextRelease
    Scenario: Offer after adding an airing show
      Given release notifications are off and I have no setting for this title
      And the title's next episode has a confirmed exact time
      When I save it as Watching
      Then the save confirmation offers "Notify me when episode 5 airs"

    @swift:ReleaseAlertOfferTests/noOfferForEstimatesDaysOrFinishedTitles
    Scenario: No offer without an exact time
      Given the next release is only an estimate or an announced day
      When I save the title as Watching
      Then no alert offer appears

    @swift:ReleaseAlertOfferTests/notifyMeUsesBellToggleOnly
    Scenario: Accepting uses the existing bell
      Given the offer is showing
      When I tap "Notify me"
      Then the per-title bell is turned on through the same call the detail bell uses
      And the system permission prompt appears only because of that tap

    @swift:ReleaseAlertOfferTests/threeDeclinesStopOffersForTheAccount
    Scenario: Declining three times stops the offers
      Given I tapped "Not now" on three different titles
      When I save another airing title
      Then no offer appears
      And the Profile toggle still works

    @swift:ReleaseAlertOfferTests/offerStateIsClearedOnAccountSwitch
    Scenario: Offer memory belongs to the account
      Given account A declined three times
      When account B signs in on the same phone and saves an airing title
      Then account B sees the offer

  Rule: Only the page I am looking at shows the offer

    @swift:ReleaseAlertOfferTests/offerFollowsTheVisiblePageNotAttachOrder
    Scenario: The visible page shows the offer, not the page that loaded last
      Given Home, Discover and Collection are all loaded in the pager and Collection loaded last
      And I am looking at Discover
      When an offer is raised
      Then only Discover's confirmation shows it
      And an offer that no visible page could show within 30 seconds goes away without counting as offered or declined

    @ui:ReleaseAlertOfferUITests/testOffscreenNeighbourPagesNeverShowTheOffer
    Scenario: An offscreen page never receives the offer
      Given the offer is showing on Discover and the neighbouring Taste page is loaded offscreen
      Then exactly one offer is on screen
      When I swipe to Taste and wait longer than the offer stays on screen
      Then Taste shows no offer
      And when I swipe back to Discover the offer is still there

    @ui:ReleaseAlertOfferUITests/testJourneySheetOnTopHidesThePagerOfferUntilItCloses
    Scenario: A page under a sheet does not show or use up the offer
      Given an offer is waiting and a sheet with pages is open over the pager
      Then no offer is on screen while the sheet is open, even after the offer's display time has passed
      When I close the sheet
      Then the offer appears once on the page I am looking at

  @gated @owner-gate
  Rule: Manga chapter alerts (needs decision D-B; scenarios written when decided)

    @manual:awaits-D-B @owner-gate
    Scenario: Manga chapter alert behaviour follows the decision taken on D-B
      Given the owner chose an option for D-B
      Then this rule is rewritten with that option's scenarios
