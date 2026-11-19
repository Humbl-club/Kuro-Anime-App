# Catalogue shadow report 2026-11-18-manga-first-shadow

Medium: manga. Generated: 2026-11-18T23:16:17.242Z.
This compares composed shadow values with the published columns as they were at that moment. It is local-shadow evidence, not a cutover decision and not proof of hosted behaviour.

Tier sizes: {"all":42029,"top1k":1000,"top5k":5000,"curated":429,"in_lists":12}

## Gate summary

| group | status |
|---|---|
| identity | fail |
| data | pass |
| titles | fail |
| facts | insufficient |
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
| identity | linked_share | in_lists | 100.0% | 83.3% | 12 | insufficient | accepted non-AniList link |
| identity | linked_share | curated | 100.0% | 11.0% | 429 | fail | accepted non-AniList link |
| identity | linked_share | top5k | 85.0% | 1.0% | 5000 | fail | accepted non-AniList link |
| identity | duplicate_accepted_links | all | 0 | 0 | 42029 | pass |  |
| identity | orphan_accepted_links | all | 0 | 0 | 42029 | pass | accepted links whose target title no longer exists |
| data | invalid_shadow_values | all | 0 | 0 | null | pass | shadow values that are not a valid integer/boolean for their field |
| identity | title_match_precision | sample | 99.0% | n/a | 0 | insufficient | needs the 200-title owner-reviewed sample; not computable from the shadow report |
| titles | display_title_of_linked | all | 100.0% | 100.0% | 50 | pass |  |
| titles | native_title | top5k | 95.0% | 1.0% | 5000 | fail |  |
| facts | start_year_exact | all | 98.0% | 100.0% | 48 | pass |  |
| facts | format_mapped | all | 97.0% | 100.0% | 10 | insufficient |  |
| adult | becomes_non_adult | all | 0 | 0 | 46 | pass | newly adult (to list for review): 0; review list size: 0 |
| relations | not_measured | - |  | n/a | 0 | insufficient | >= 90% of today's SEQUEL/PREQUEL pairs among linked titles reproduced (not in the shadow report yet) |
| popularity | not_measured | - |  | n/a | 0 | insufficient | Spearman >= 0.7 on top 5k (Task 10) |
| tags | not_measured | - |  | n/a | 0 | insufficient | median top-5 tag overlap >= 60% (Task 11) |
| episodes | not_measured | - |  | n/a | 0 | insufficient | next airing within 24 h of the provider (Task 9, gate L1) |
| synopsis | not_measured | - |  | n/a | 0 | insufficient | own synopsis on >= 95% of top 5k (Task 12, gate L2) |
| images | not_measured | - |  | n/a | 0 | insufficient | licensed or Kuro artwork on 100% of visible titles (Task 13, gate L3) |

## Identity gate counts

```json
{
  "accepted_links": 60,
  "proposed_links": 40,
  "proposed_only_titles": 0,
  "orphan_accepted_links": 0,
  "duplicate_accepted_links": 0
}
```

## Adult

```json
{
  "newly_adult": 0,
  "review_size": 0,
  "becomes_non_adult": 0
}
```

## Disagreement samples (tier all)

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

