# Catalogue shadow report 2026-11-18-anime-first-shadow

Medium: anime. Generated: 2026-11-18T23:16:13.496Z.
This compares composed shadow values with the published columns as they were at that moment. It is local-shadow evidence, not a cutover decision and not proof of hosted behaviour.

Tier sizes: {"all":21890,"top1k":1000,"top5k":5000,"curated":564,"in_lists":34}

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
| identity | linked_share | in_lists | 100.0% | 38.2% | 34 | fail | accepted non-AniList link |
| identity | linked_share | curated | 100.0% | 6.2% | 564 | fail | accepted non-AniList link |
| identity | linked_share | top5k | 95.0% | 0.9% | 5000 | fail | accepted non-AniList link |
| identity | duplicate_accepted_links | all | 0 | 0 | 21890 | pass |  |
| identity | orphan_accepted_links | all | 0 | 0 | 21890 | pass | accepted links whose target title no longer exists |
| data | invalid_shadow_values | all | 0 | 0 | null | pass | shadow values that are not a valid integer/boolean for their field |
| identity | title_match_precision | sample | 99.0% | n/a | 0 | insufficient | needs the 200-title owner-reviewed sample; not computable from the shadow report |
| titles | display_title_of_linked | all | 100.0% | 100.0% | 46 | pass |  |
| titles | native_title | top5k | 95.0% | 0.9% | 5000 | fail |  |
| facts | start_year_exact | all | 98.0% | 100.0% | 43 | pass |  |
| facts | format_mapped | all | 97.0% | 100.0% | 13 | insufficient |  |
| facts | episodes_finished | all | 97.0% | 92.5% | 40 | fail |  |
| adult | becomes_non_adult | all | 0 | 0 | 31 | pass | newly adult (to list for review): 0; review list size: 0 |
| relations | not_measured | - |  | n/a | 0 | insufficient | >= 90% of today's SEQUEL/PREQUEL pairs among linked titles reproduced (not in the shadow report yet) |
| popularity | not_measured | - |  | n/a | 0 | insufficient | Spearman >= 0.7 on top 5k (Task 10) |
| tags | not_measured | - |  | n/a | 0 | insufficient | median top-5 tag overlap >= 60% (Task 11) |
| episodes | not_measured | - |  | n/a | 0 | insufficient | next airing within 24 h of the provider (Task 9, gate L1) |
| synopsis | not_measured | - |  | n/a | 0 | insufficient | own synopsis on >= 95% of top 5k (Task 12, gate L2) |
| images | not_measured | - |  | n/a | 0 | insufficient | licensed or Kuro artwork on 100% of visible titles (Task 13, gate L3) |

## Identity gate counts

```json
{
  "accepted_links": 59,
  "proposed_links": 37,
  "proposed_only_titles": 4,
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
| 2 | "Attack on Titan" | "Attack on Titan, season 1" |
| 3 | "Demon Slayer: Kimetsu no Yaiba" | "Demon Slayer: Kimetsu no Yaiba, season 1" |
| 5 | "JUJUTSU KAISEN" | "Jujutsu Kaisen, season 1" |
| 6 | "My Hero Academia" | "My Hero Academia, season 1" |
| 7 | "Hunter x Hunter (2011)" | "Hunter × Hunter" |
| 8 | "One-Punch Man" | "One-Punch Man, season 1" |
| 13 | "Sword Art Online" | "Sword Art Online, season 1" |
| 19 | "The Promised Neverland" | "The Promised Neverland, season 1" |
| 20 | "Attack on Titan Final Season" | "Attack on Titan: The Final Season" |
| 22 | "Mob Psycho 100" | "Mob Psycho 100, season 1" |
| 28 | "Re:ZERO -Starting Life in Another World-" | "Re:Zero, season 1" |
| 30 | "HAIKYU!!" | "Haikyu!!, season 1" |
| 91 | "Black Clover" | "Black Clover, season 1" |
| 92 | "Noragami" | "Noragami, season 1" |
| 94 | "Kaguya-sama: Love is War" | "Kaguya-sama: Love Is War, season 1" |
| 95 | "Dr. STONE" | "Dr. Stone, season 1" |
| 101 | "The Seven Deadly Sins" | "The Seven Deadly Sins, season 1" |
| 102 | "Vinland Saga" | "Vinland Saga, season 1" |
| 103 | "KONOSUBA -God's blessing on this wonderful world!" | "KonoSuba, season 1" |

### facts_episodes

| id | today | shadow |
|---|---|---|
| 21 | 22 | 47 |
| 29 | 24 | 26 |
| 108 | 366 | 406 |

