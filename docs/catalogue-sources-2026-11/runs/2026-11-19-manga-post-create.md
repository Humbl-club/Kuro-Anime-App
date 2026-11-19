# Catalogue shadow report 2026-11-19-manga-post-create

Medium: manga. Generated: 2026-11-19T00:22:17.864Z.
This compares composed shadow values with the published columns as they were at that moment. It is local-shadow evidence, not a cutover decision and not proof of hosted behaviour.

Tier sizes: {"all":42060,"top1k":1000,"top5k":5000,"curated":429,"in_lists":12}

## Gate summary

| group | status |
|---|---|
| identity | fail |
| data | pass |
| titles | fail |
| facts | fail |
| adult | pass |
| relations | insufficient |
| popularity | insufficient |
| tags | insufficient |
| episodes | insufficient |
| synopsis | insufficient |
| images | insufficient |

A tier with fewer than 30 compared rows is insufficient, never pass.

## Gates

| group | metric | tier | threshold | value | n | status | note |
|---|---|---|---|---|---|---|---|
| identity | linked_share | in_lists | 100.0% | 100.0% | 12 | insufficient | accepted non-AniList link |
| identity | linked_share | curated | 100.0% | 88.1% | 429 | fail | accepted non-AniList link |
| identity | linked_share | top5k | 85.0% | 46.9% | 5000 | fail | accepted non-AniList link |
| identity | duplicate_accepted_links | all | 0 | 0 | 42060 | pass |  |
| identity | orphan_accepted_links | all | 0 | 0 | 42060 | pass | accepted links whose target title no longer exists |
| data | invalid_shadow_values | all | 0 | 0 | null | pass | shadow values that are not a valid integer/boolean for their field |
| identity | title_match_precision | sample | 99.0% | n/a | 0 | insufficient | needs the 200-title owner-reviewed sample; not computable from the shadow report |
| titles | display_title_of_linked | all | 100.0% | 22.3% | 2376 | fail |  |
| titles | native_title | top5k | 95.0% | 9.3% | 5000 | fail |  |
| facts | start_year_exact | all | 98.0% | 94.7% | 469 | fail |  |
| facts | format_mapped | all | 97.0% | 99.6% | 244 | pass |  |
| adult | becomes_non_adult | all | 0 | 0 | 476 | pass | newly adult (to list for review): 7; review list size: 19 |
| relations | not_measured | - |  | n/a | 0 | insufficient | >= 90% of today's SEQUEL/PREQUEL pairs among linked titles reproduced (not in the shadow report yet) |
| popularity | not_measured | - |  | n/a | 0 | insufficient | Spearman >= 0.7 on top 5k (Task 10) |
| tags | not_measured | - |  | n/a | 0 | insufficient | median top-5 tag overlap >= 60% (Task 11) |
| episodes | not_measured | - |  | n/a | 0 | insufficient | next airing within 24 h of the provider (Task 9, gate L1) |
| synopsis | not_measured | - |  | n/a | 0 | insufficient | own synopsis on >= 95% of top 5k (Task 12, gate L2) |
| images | not_measured | - |  | n/a | 0 | insufficient | licensed or Kuro artwork on 100% of visible titles (Task 13, gate L3) |

## Identity gate counts

```json
{
  "accepted_links": 2737,
  "proposed_links": 1165,
  "proposed_only_titles": 19,
  "orphan_accepted_links": 0,
  "duplicate_accepted_links": 0
}
```

## Adult

```json
{
  "newly_adult": 7,
  "review_size": 19,
  "becomes_non_adult": 0
}
```

## Disagreement samples (tier all)

### adult

| id | today | shadow |
|---|---|---|
| 104 | false | true |
| 131 | false | true |
| 132 | false | true |
| 150 | false | true |
| 185 | false | true |
| 216 | false | true |
| 275 | false | true |

### titles

| id | today | shadow |
|---|---|---|
| 13 | "SPY x FAMILY" | "Spy × Family" |
| 19 | "Omniscient Reader" | "Omniscient Reader's Viewpoint" |
| 26 | "Hunter x Hunter" | "Hunter × Hunter" |
| 76 | "JoJo's Bizarre Adventure: Part 7–Steel Ball Run" | "Steel Ball Run" |
| 85 | "Uzumaki: Spiral into Horror" | "Uzumaki" |
| 88 | "Three Days of Happiness" | "I Sold My Life for Ten Thousand Yen Per Year" |
| 89 | "Frieren: Beyond Journey’s End" | "Frieren" |
| 96 | "JoJo's Bizarre Adventure Part 6: Stone Ocean" | "Stone Ocean" |
| 118 | "Noragami: Stray God" | "Noragami" |
| 125 | "Ajin: Demi-Human" | "Ajin" |
| 127 | "JoJo’s Bizarre Adventure: Part 8—JoJolion" | "JoJolion" |
| 128 | "Mashle: Magic and Muscles" | "Mashle" |
| 133 | "Nisekoi: False Love" | "Nisekoi" |
| 136 | "GTO: Great Teacher Onizuka" | "Great Teacher Onizuka" |
| 156 | "Boruto: Naruto Next Generations" | "Boruto" |
| 164 | "Mushoku Tensei: Jobless Reincarnation" | "Mushoku Tensei" |
| 167 | "JoJo's Bizarre Adventure Part 1: Phantom Blood" | "Phantom Blood" |
| 168 | "Onani Master Kurosawa" | "Onanii Master Kurosawa" |
| 177 | "Jagaaan" | "Jagaaaaaan" |
| 179 | "Seraph of the End: Vampire Reign" | "Seraph of the End" |

### facts_format

| id | today | shadow |
|---|---|---|
| 95 | "ONE_SHOT" | "MANGA" |

### facts_status

| id | today | shadow |
|---|---|---|
| 14 | "RELEASING" | "HIATUS" |
| 19 | "RELEASING" | "HIATUS" |
| 26 | "RELEASING" | "HIATUS" |
| 89 | "RELEASING" | "HIATUS" |
| 99 | "RELEASING" | "HIATUS" |
| 140 | "RELEASING" | "HIATUS" |
| 186 | "RELEASING" | "FINISHED" |
| 213 | "RELEASING" | "HIATUS" |
| 220 | "RELEASING" | "FINISHED" |
| 225 | "FINISHED" | "RELEASING" |
| 251 | "RELEASING" | "HIATUS" |
| 260 | "RELEASING" | "HIATUS" |
| 268 | "RELEASING" | "HIATUS" |

### facts_start_year

| id | today | shadow |
|---|---|---|
| 143 | 2020 | 2025 |
| 147 | 2007 | 2006 |
| 167 | 1986 | 1987 |
| 223 | 2005 | 2006 |
| 226 | 2006 | 2005 |
| 236 | 2019 | 2018 |
| 267 | 1989 | 1988 |
| 270 | 2000 | 1999 |
| 288 | 2006 | 2012 |
| 302 | 2016 | 2017 |
| 332 | 1972 | 1989 |
| 342 | 1999 | 2001 |
| 353 | 2009 | 2012 |
| 416 | 2012 | 2014 |
| 419 | 2017 | 2018 |
| 438 | 2018 | 2021 |
| 481 | 2018 | 2019 |
| 495 | 2010 | 2018 |
| 501 | 2018 | 2020 |
| 502 | 2004 | 2003 |

