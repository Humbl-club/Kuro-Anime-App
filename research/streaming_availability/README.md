# Free Streaming Availability Research Spike

This directory contains a research-only spike for testing whether free GitHub sources can support Kuro's streaming metadata requirements.

Scope:
- No production DB writes
- No UI wiring
- No changes to `provider_availability` tables or RPCs
- High-precision only; weak coverage is acceptable, false confidence is not

Inputs:
- `benchmark_manifest.json` — fixed 50-title benchmark from Kuro's public catalog (`25 anime`, `25 manga`)
- `provider_mappings.json` — research-only provider alias map to Kuro `streaming_services.slug` candidates
- Upstream repos cloned locally:
  - `/tmp/kuro-source-spike/simple-justwatch-python-api`
  - `/tmp/kuro-source-spike-selenium`
  - `/tmp/kuro-source-spike/anime-streaming`

Run:

```bash
python3 /Applications/Kuro/research/streaming_availability/free_streaming_availability_spike.py
```

Smoke run:

```bash
python3 /Applications/Kuro/research/streaming_availability/free_streaming_availability_spike.py --limit 6
```

Outputs:
- `/Applications/Kuro/reports/streaming-availability-research/title_by_title.json`
- `/Applications/Kuro/reports/streaming-availability-research/provider_country_aggregate.csv`
- `/Applications/Kuro/reports/streaming-availability-research/precision_review.md`
- `/Applications/Kuro/reports/streaming-availability-research/unresolved_mismatches.md`

Source handling rules:
- `simple-justwatch-python-api` is the only title-level source in this spike.
- `justwatch-selenium-api` is adapter-scoped but treated as optional and may stay unavailable if Selenium dependencies are missing.
- `anime-streaming` is parsed only as service-region hint data and is never treated as title-level truth.
