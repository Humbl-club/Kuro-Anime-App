#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import importlib
import json
import re
import sys
import urllib.error
import urllib.request
import unicodedata
from collections import Counter, defaultdict
from dataclasses import dataclass
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
RESEARCH_DIR = Path(__file__).resolve().parent
DEFAULT_REPORT_DIR = ROOT / "reports" / "streaming-availability-research"
DEFAULT_BENCHMARK_PATH = RESEARCH_DIR / "benchmark_manifest.json"
DEFAULT_PROVIDER_MAPPINGS_PATH = RESEARCH_DIR / "provider_mappings.json"
DEFAULT_SIMPLE_JUSTWATCH_REPO = Path("/tmp/kuro-source-spike/simple-justwatch-python-api")
DEFAULT_SELENIUM_REPO = Path("/tmp/kuro-source-spike-selenium")
DEFAULT_ANIME_STREAMING_REPO = Path("/tmp/kuro-source-spike/anime-streaming")
DEFAULT_SEARCH_COUNTRY = "US"
COUNTRIES = ["US", "CA", "GB", "DE", "AT", "CH"]
TITLE_MATCH_THRESHOLD = 0.95
STREAMING_MONETIZATION_TYPES = {"FLATRATE", "ADS", "FREE"}
MANUAL_REVIEW_COUNT = 8

COUNTRY_NAME_TO_CODE = {
    "australia": "AU",
    "austria": "AT",
    "belgium": "BE",
    "brunei": "BN",
    "canada": "CA",
    "germany": "DE",
    "india": "IN",
    "ireland": "IE",
    "japan": "JP",
    "luxembourg": "LU",
    "new zealand": "NZ",
    "north america": "US",
    "switzerland": "CH",
    "united kingdom": "GB",
    "uk": "GB",
    "us": "US",
    "united states": "US",
    "worldwide": "*",
}


@dataclass
class AdapterStatus:
    name: str
    available: bool
    notes: str


@dataclass
class MatchResult:
    status: str
    confidence: float
    node_id: str | None
    matched_title: str | None
    matched_year: int | None
    query_title: str
    notes: str


@dataclass
class JWPackage:
    name: str | None
    technical_name: str | None


@dataclass
class JWOffer:
    monetization_type: str | None
    presentation_type: str | None
    package: JWPackage
    url: str | None
    subtitle_languages: list[str]
    audio_languages: list[str]


@dataclass
class JWEntry:
    id: str
    title: str | None
    year: int | None


@dataclass
class SpikeConfig:
    simple_justwatch_repo: Path
    selenium_repo: Path
    anime_streaming_repo: Path
    search_country: str
    countries: list[str]


class JustWatchGraphQLAdapter:
    def __init__(self, repo_path: Path, search_country: str) -> None:
        self.repo_path = repo_path
        self.search_country = search_country.upper()
        self.status = self._load()

    def _load(self) -> AdapterStatus:
        if not self.repo_path.exists():
            return AdapterStatus("simple-justwatch-python-api", False, f"Repo missing: {self.repo_path}")
        query_path = self.repo_path / "src" / "simplejustwatchapi" / "query.py"
        if not query_path.exists():
            return AdapterStatus("simple-justwatch-python-api", False, f"Missing upstream query definitions: {query_path}")
        return AdapterStatus(
            "simple-justwatch-python-api",
            True,
            "Loaded as source reference; runtime uses a local Python 3.9-compatible adapter against the same JustWatch GraphQL contract.",
        )

    def _post(self, payload: dict[str, Any]) -> dict[str, Any]:
        request = urllib.request.Request(
            "https://apis.justwatch.com/graphql",
            data=json.dumps(payload).encode("utf-8"),
            headers={"content-type": "application/json"},
            method="POST",
        )
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                return json.load(response)
        except urllib.error.HTTPError as exc:
            body = exc.read().decode("utf-8", errors="replace")
            raise RuntimeError(f"HTTP {exc.code}: {body}") from exc

    def search(self, title: str) -> list[JWEntry]:
        if not self.status.available:
            return []
        payload = {
            "operationName": "GetSearchTitles",
            "variables": {
                "first": 6,
                "searchTitlesFilter": {"searchQuery": title},
                "language": "en",
                "country": self.search_country,
            },
            "query": (
                "query GetSearchTitles("
                "$searchTitlesFilter: TitleFilter!,"
                "$country: Country!,"
                "$language: Language!,"
                "$first: Int!"
                ") {"
                "  popularTitles(country: $country, filter: $searchTitlesFilter, first: $first, sortBy: POPULAR, sortRandomSeed: 0) {"
                "    edges {"
                "      node {"
                "        id"
                "        content(country: $country, language: $language) {"
                "          title"
                "          originalReleaseYear"
                "        }"
                "      }"
                "    }"
                "  }"
                "}"
            ),
        }
        data = self._post(payload)
        results: list[JWEntry] = []
        for edge in data.get("data", {}).get("popularTitles", {}).get("edges", []):
            node = edge.get("node") or {}
            content = node.get("content") or {}
            if node.get("id"):
                results.append(
                    JWEntry(
                        id=node["id"],
                        title=content.get("title"),
                        year=to_year(content.get("originalReleaseYear")),
                    )
                )
        return results

    def offers_for_countries(self, node_id: str, countries: list[str]) -> dict[str, list[JWOffer]]:
        if not self.status.available:
            return {}
        country_entries = "".join(
            f" {country.upper()}: offers(country: {country.upper()}, platform: WEB, filter: $filter) {{"
            " monetizationType"
            " presentationType"
            " standardWebURL"
            " subtitleLanguages"
            " audioLanguages"
            " package { clearName technicalName }"
            " }"
            for country in countries
        )
        payload = {
            "operationName": "GetTitleOffers",
            "variables": {
                "nodeId": node_id,
                "filter": {"bestOnly": True},
            },
            "query": (
                "query GetTitleOffers("
                "$nodeId: ID!,"
                "$filter: OfferFilter!"
                ") {"
                "  node(id: $nodeId) {"
                "    ... on MovieOrShow {"
                f"{country_entries}"
                "    }"
                "  }"
                "}"
            ),
        }
        data = self._post(payload)
        node = data.get("data", {}).get("node") or {}
        parsed: dict[str, list[JWOffer]] = {}
        for country in countries:
            offers = []
            for offer in node.get(country.upper(), []) or []:
                package = offer.get("package") or {}
                offers.append(
                    JWOffer(
                        monetization_type=offer.get("monetizationType"),
                        presentation_type=offer.get("presentationType"),
                        package=JWPackage(
                            name=package.get("clearName"),
                            technical_name=package.get("technicalName"),
                        ),
                        url=offer.get("standardWebURL"),
                        subtitle_languages=[str(code).lower() for code in (offer.get("subtitleLanguages") or []) if code],
                        audio_languages=[str(code).lower() for code in (offer.get("audioLanguages") or []) if code],
                    )
                )
            parsed[country] = offers
        return parsed


class SeleniumJustWatchAdapter:
    def __init__(self, repo_path: Path) -> None:
        self.repo_path = repo_path
        self.status = self._check()

    def _check(self) -> AdapterStatus:
        if not self.repo_path.exists():
            return AdapterStatus("justwatch-selenium-api", False, f"Repo missing: {self.repo_path}")
        src_path = self.repo_path / "src"
        if str(src_path) not in sys.path:
            sys.path.insert(0, str(src_path))
        try:
            importlib.import_module("selenium")
            importlib.import_module("dotenv")
            importlib.import_module("loguru")
        except Exception as exc:
            return AdapterStatus(
                "justwatch-selenium-api",
                False,
                f"Dependencies unavailable in local Python env: {exc.__class__.__name__}: {exc}",
            )
        return AdapterStatus(
            "justwatch-selenium-api",
            False,
            "Adapter intentionally disabled for this spike: Selenium adds brittle provider-country scraping only and no title-level locale fields.",
        )


def normalize_text(value: str | None) -> str:
    if not value:
        return ""
    normalized = unicodedata.normalize("NFKC", value).lower()
    normalized = normalized.replace("×", "x")
    normalized = re.sub(r"\([^)]*\)$", "", normalized).strip()
    normalized = re.sub(r"[^a-z0-9]+", " ", normalized)
    return re.sub(r"\s+", " ", normalized).strip()


def normalize_provider(value: str | None) -> str:
    return normalize_text(value)


def to_year(raw: Any) -> int | None:
    if raw in (None, ""):
        return None
    try:
        return int(raw)
    except (TypeError, ValueError):
        return None


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text())


def load_provider_alias_map(path: Path) -> dict[str, str]:
    raw = load_json(path)
    alias_map: dict[str, str] = {}
    for slug, aliases in raw.items():
        alias_map[normalize_provider(slug)] = slug
        for alias in aliases:
            alias_map[normalize_provider(alias)] = slug
    return alias_map


def parse_markdown_link_label(value: str) -> str:
    match = re.search(r"\[([^\]]+)\]", value)
    if match:
        return match.group(1)
    return re.sub(r"<br>.*", "", value).strip()


def split_country_cell(value: str) -> list[str]:
    cleaned = re.sub(r"\[([^\]]+)\]\([^)]*\)", r"\1", value)
    cleaned = cleaned.replace("<br>", ",")
    cleaned = cleaned.replace(" and ", ",")
    parts = [part.strip() for part in cleaned.split(",")]
    return [part for part in parts if part]


def parse_country_codes(value: str) -> set[str]:
    codes: set[str] = set()
    for part in split_country_cell(value):
        code = COUNTRY_NAME_TO_CODE.get(normalize_text(part))
        if code:
            if code == "*":
                return {"*"}
            codes.add(code)
    return codes


def load_anime_streaming_hints(readme_path: Path, provider_aliases: dict[str, str]) -> list[dict[str, Any]]:
    if not readme_path.exists():
        return []
    lines = readme_path.read_text(encoding="utf-8").splitlines()
    in_table = False
    hints: list[dict[str, Any]] = []
    for line in lines:
        if line.startswith("## Anime Streaming Platform"):
            in_table = True
            continue
        if in_table and line.startswith("## "):
            break
        if not in_table or not line.startswith("|"):
            continue
        cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
        if len(cells) != 4:
            continue
        if cells[0].lower().startswith("streaming site") or set(cells[0]) == {"-"}:
            continue
        provider_name_raw = parse_markdown_link_label(cells[0])
        provider_slug_candidate = provider_aliases.get(normalize_provider(provider_name_raw))
        country_codes = parse_country_codes(cells[1])
        hints.append(
            {
                "provider_name_raw": provider_name_raw,
                "provider_slug_candidate": provider_slug_candidate,
                "country_codes": sorted(country_codes),
                "language": cells[2].strip(),
                "note": cells[3].strip(),
            }
        )
    return hints


def candidate_titles(entry: dict[str, Any]) -> list[str]:
    titles = []
    for key in ("title_english", "title_romaji"):
        value = entry.get(key)
        if value and value not in titles:
            titles.append(value)
    return titles


def choose_query_title(entry: dict[str, Any]) -> str:
    return entry.get("title_english") or entry.get("title_romaji") or f"{entry['media_type']} {entry['media_id']}"


def match_justwatch_entry(entry: dict[str, Any], results: list[Any]) -> MatchResult:
    names = candidate_titles(entry)
    normalized_names = {normalize_text(name): name for name in names if normalize_text(name)}
    expected_year = to_year(entry.get("year"))
    scored: list[tuple[float, Any, str]] = []
    for result in results:
        result_title = getattr(result, "title", None)
        normalized_result = normalize_text(result_title)
        if not normalized_result or normalized_result not in normalized_names:
            continue
        result_year = to_year(getattr(result, "year", None))
        confidence = 0.0
        if expected_year is not None and result_year == expected_year:
            confidence = 1.0
        elif expected_year is None or result_year is None:
            confidence = 0.97
        else:
            continue
        scored.append((confidence, result, normalized_names[normalized_result]))
    if not scored:
        return MatchResult(
            status="unresolved",
            confidence=0.0,
            node_id=None,
            matched_title=None,
            matched_year=None,
            query_title=choose_query_title(entry),
            notes="No deterministic exact-title match in JustWatch search results",
        )
    scored.sort(key=lambda item: item[0], reverse=True)
    top_confidence = scored[0][0]
    top_candidates = [item for item in scored if item[0] == top_confidence]
    if top_confidence < TITLE_MATCH_THRESHOLD:
        return MatchResult(
            status="unresolved",
            confidence=top_confidence,
            node_id=None,
            matched_title=None,
            matched_year=None,
            query_title=choose_query_title(entry),
            notes=f"Top deterministic match below threshold ({top_confidence:.2f})",
        )
    if len(top_candidates) > 1:
        titles = ", ".join(str(getattr(item[1], "title", "?")) for item in top_candidates[:3])
        return MatchResult(
            status="ambiguous",
            confidence=top_confidence,
            node_id=None,
            matched_title=None,
            matched_year=None,
            query_title=choose_query_title(entry),
            notes=f"Multiple exact-title candidates at same confidence: {titles}",
        )
    best = top_candidates[0][1]
    return MatchResult(
        status="matched",
        confidence=top_confidence,
        node_id=getattr(best, "id", None),
        matched_title=getattr(best, "title", None),
        matched_year=to_year(getattr(best, "year", None)),
        query_title=choose_query_title(entry),
        notes="Deterministic exact-title match accepted",
    )


def derive_language_note(audio_locales: list[str], subtitle_locales: list[str], original_language: str | None) -> str | None:
    notes: list[str] = []
    original = (original_language or "").lower()
    for locale, label in (("en", "EN"), ("de", "DE")):
        if locale in audio_locales:
            if original and original != locale:
                notes.append(f"{label} dub")
            else:
                notes.append(f"{label} audio")
        elif locale in subtitle_locales:
            notes.append(f"{label} subtitles")
    if not notes:
        return None
    return ", ".join(notes)


def summarize_offer_note(offer: Any, derived_note: str | None) -> str:
    parts: list[str] = []
    if derived_note:
        parts.append(derived_note)
    if getattr(offer, "presentation_type", None):
        parts.append(f"presentation={offer.presentation_type}")
    if getattr(offer, "monetization_type", None):
        parts.append(f"monetization={offer.monetization_type}")
    return "; ".join(parts)


def provider_slug_candidate(offer: Any, provider_aliases: dict[str, str]) -> str | None:
    package = getattr(offer, "package", None)
    candidates = [
        getattr(package, "name", None),
        getattr(package, "technical_name", None),
    ]
    for candidate in candidates:
        slug = provider_aliases.get(normalize_provider(candidate))
        if slug:
            return slug
    return None


def title_level_rows_for_entry(
    entry: dict[str, Any],
    offers_by_country: dict[str, list[Any]],
    provider_aliases: dict[str, str],
) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    original_language = entry.get("original_language")
    for country_code, offers in offers_by_country.items():
        for offer in offers:
            if getattr(offer, "monetization_type", None) not in STREAMING_MONETIZATION_TYPES:
                continue
            audio_locales = sorted({str(code).lower() for code in (getattr(offer, "audio_languages", None) or []) if code})
            subtitle_locales = sorted({str(code).lower() for code in (getattr(offer, "subtitle_languages", None) or []) if code})
            derived_note = derive_language_note(audio_locales, subtitle_locales, original_language)
            evidence_level = "title_level_verified" if (audio_locales or subtitle_locales) else "provider_country_only"
            if audio_locales:
                language_hint_type = "audio"
            elif subtitle_locales:
                language_hint_type = "subtitle"
            else:
                language_hint_type = "unknown"
            package = getattr(offer, "package", None)
            rows.append(
                {
                    "media_type": entry["media_type"],
                    "media_id": entry["media_id"],
                    "source_name": "simple-justwatch-python-api",
                    "source_match_confidence": 1.0,
                    "provider_name_raw": getattr(package, "name", None),
                    "provider_slug_candidate": provider_slug_candidate(offer, provider_aliases),
                    "country_code": country_code.upper(),
                    "link_url": getattr(offer, "url", None),
                    "audio_locales": audio_locales,
                    "subtitle_locales": subtitle_locales,
                    "language_hint_type": language_hint_type,
                    "evidence_level": evidence_level,
                    "notes": summarize_offer_note(offer, derived_note),
                }
            )
    if not rows:
        rows.append(
            {
                "media_type": entry["media_type"],
                "media_id": entry["media_id"],
                "source_name": "simple-justwatch-python-api",
                "source_match_confidence": 1.0,
                "provider_name_raw": None,
                "provider_slug_candidate": None,
                "country_code": None,
                "link_url": None,
                "audio_locales": [],
                "subtitle_locales": [],
                "language_hint_type": "unknown",
                "evidence_level": "no_signal",
                "notes": "Matched JustWatch title but found no streaming FLATRATE/ADS/FREE offers in configured countries",
            }
        )
    return rows


def attach_anime_streaming_hints(
    base_rows: list[dict[str, Any]],
    hints: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    hint_index: dict[tuple[str, str], list[dict[str, Any]]] = defaultdict(list)
    for hint in hints:
        slug = hint.get("provider_slug_candidate")
        if not slug:
            continue
        countries = hint.get("country_codes") or []
        if not countries:
            continue
        if "*" in countries:
            for code in COUNTRIES:
                hint_index[(slug, code)].append(hint)
        else:
            for code in countries:
                hint_index[(slug, code)].append(hint)
    rows = list(base_rows)
    for row in base_rows:
        if row["evidence_level"] == "no_signal":
            continue
        key = (row.get("provider_slug_candidate"), row.get("country_code"))
        for hint in hint_index.get(key, []):
            note_parts = []
            if hint.get("language"):
                note_parts.append(hint["language"])
            if hint.get("note"):
                note_parts.append(hint["note"])
            rows.append(
                {
                    "media_type": row["media_type"],
                    "media_id": row["media_id"],
                    "source_name": "anime-streaming",
                    "source_match_confidence": 1.0,
                    "provider_name_raw": hint.get("provider_name_raw"),
                    "provider_slug_candidate": row.get("provider_slug_candidate"),
                    "country_code": row.get("country_code"),
                    "link_url": None,
                    "audio_locales": [],
                    "subtitle_locales": [],
                    "language_hint_type": "manual_service_hint",
                    "evidence_level": "service_region_hint",
                    "notes": " | ".join(part for part in note_parts if part),
                }
            )
    return rows


def aggregate_provider_country(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    grouped: dict[tuple[Any, ...], dict[str, Any]] = {}
    for row in rows:
        if not row.get("provider_name_raw") or not row.get("country_code"):
            continue
        key = (
            row.get("provider_slug_candidate"),
            row.get("provider_name_raw"),
            row.get("country_code"),
            row.get("evidence_level"),
        )
        bucket = grouped.setdefault(
            key,
            {
                "provider_slug_candidate": row.get("provider_slug_candidate"),
                "provider_name_raw": row.get("provider_name_raw"),
                "country_code": row.get("country_code"),
                "evidence_level": row.get("evidence_level"),
                "title_count": 0,
                "source_names": set(),
            },
        )
        bucket["title_count"] += 1
        bucket["source_names"].add(row.get("source_name"))
    result = []
    for bucket in grouped.values():
        result.append(
            {
                **bucket,
                "source_names": ", ".join(sorted(bucket["source_names"])),
            }
        )
    result.sort(key=lambda item: (item["provider_slug_candidate"] or "zzz", item["country_code"], item["evidence_level"]))
    return result


def compute_source_metrics(
    title_records: list[dict[str, Any]],
    adapter_statuses: list[AdapterStatus],
    config: SpikeConfig,
) -> dict[str, Any]:
    metrics: dict[str, Any] = {}
    status_map = {status.name: status for status in adapter_statuses}
    justwatch_records = [record for record in title_records if "simple_justwatch" in record["source_runs"]]
    total = len(justwatch_records)
    matched = sum(1 for record in justwatch_records if record["source_runs"]["simple_justwatch"]["match_status"] == "matched")
    unresolved = sum(1 for record in justwatch_records if record["source_runs"]["simple_justwatch"]["match_status"] in {"unresolved", "ambiguous", "error"})
    provider_titles = sum(
        1 for record in justwatch_records
        if any(
            row["source_name"] == "simple-justwatch-python-api" and row["evidence_level"] in {"title_level_verified", "provider_country_only"}
            for row in record["rows"]
        )
    )
    language_titles = sum(
        1 for record in justwatch_records
        if any(
            row["source_name"] == "simple-justwatch-python-api" and row["evidence_level"] == "title_level_verified"
            for row in record["rows"]
        )
    )
    metrics["simple-justwatch-python-api"] = {
        "status": "available" if status_map["simple-justwatch-python-api"].available else "unavailable",
        "notes": status_map["simple-justwatch-python-api"].notes,
        "title_match_success_rate": round(matched / total, 3) if total else None,
        "provider_country_coverage": round(provider_titles / total, 3) if total else None,
        "title_level_language_evidence_rate": round(language_titles / total, 3) if total else None,
        "contradiction_rate": None,
        "unusable_or_noisy_rate": round(unresolved / total, 3) if total else None,
    }
    anime_hint_titles = sum(
        1 for record in title_records
        if any(row["source_name"] == "anime-streaming" for row in record["rows"])
    )
    metrics["anime-streaming"] = {
        "status": "available" if config.anime_streaming_repo.exists() else "unavailable",
        "notes": "Manual service-region hints only; never treated as title-level truth.",
        "title_match_success_rate": None,
        "provider_country_coverage": round(anime_hint_titles / total, 3) if total else None,
        "title_level_language_evidence_rate": 0.0,
        "contradiction_rate": None,
        "unusable_or_noisy_rate": None,
    }
    selenium_status = status_map["justwatch-selenium-api"]
    metrics["justwatch-selenium-api"] = {
        "status": "available" if selenium_status.available else "unavailable",
        "notes": selenium_status.notes,
        "title_match_success_rate": None,
        "provider_country_coverage": None,
        "title_level_language_evidence_rate": None,
        "contradiction_rate": None,
        "unusable_or_noisy_rate": None,
    }
    return metrics


def build_manual_review_set(title_records: list[dict[str, Any]]) -> dict[str, list[dict[str, Any]]]:
    positives: list[dict[str, Any]] = []
    suspicious: list[dict[str, Any]] = []
    for record in title_records:
        justwatch = record["source_runs"].get("simple_justwatch")
        if justwatch and justwatch["match_status"] == "matched":
            locale_rows = [
                row for row in record["rows"]
                if row["source_name"] == "simple-justwatch-python-api" and row["evidence_level"] == "title_level_verified"
            ]
            if locale_rows:
                positives.append(
                    {
                        "media_type": record["benchmark"]["media_type"],
                        "media_id": record["benchmark"]["media_id"],
                        "title": choose_query_title(record["benchmark"]),
                        "match_confidence": justwatch["match_confidence"],
                        "examples": locale_rows[:2],
                    }
                )
        if justwatch and justwatch["match_status"] != "matched":
            suspicious.append(
                {
                    "media_type": record["benchmark"]["media_type"],
                    "media_id": record["benchmark"]["media_id"],
                    "title": choose_query_title(record["benchmark"]),
                    "reason": justwatch["notes"],
                }
            )
        elif any(row["source_name"] == "simple-justwatch-python-api" and row["provider_slug_candidate"] is None for row in record["rows"]):
            suspicious.append(
                {
                    "media_type": record["benchmark"]["media_type"],
                    "media_id": record["benchmark"]["media_id"],
                    "title": choose_query_title(record["benchmark"]),
                    "reason": "At least one JustWatch provider name did not map to a Kuro provider slug candidate",
                }
            )
    positives.sort(key=lambda item: item["match_confidence"], reverse=True)
    return {
        "highest_confidence_positive_cases": positives[:MANUAL_REVIEW_COUNT],
        "suspicious_mismatches": suspicious[:MANUAL_REVIEW_COUNT],
    }


def write_csv(path: Path, rows: list[dict[str, Any]]) -> None:
    if not rows:
        path.write_text("provider_slug_candidate,provider_name_raw,country_code,evidence_level,title_count,source_names\n")
        return
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)


def write_markdown_reports(
    report_dir: Path,
    metrics: dict[str, Any],
    manual_review: dict[str, list[dict[str, Any]]],
    title_records: list[dict[str, Any]],
    adapter_statuses: list[AdapterStatus],
    config: SpikeConfig,
) -> None:
    precision_path = report_dir / "precision_review.md"
    unresolved_path = report_dir / "unresolved_mismatches.md"
    by_media_type = Counter(record["benchmark"]["media_type"] for record in title_records)
    matched = sum(1 for record in title_records if record["source_runs"]["simple_justwatch"]["match_status"] == "matched")
    justwatch_by_type: dict[str, dict[str, int]] = {}
    for media_type in ("ANIME", "MANGA"):
        subset = [record for record in title_records if record["benchmark"]["media_type"] == media_type]
        justwatch_by_type[media_type] = {
            "total": len(subset),
            "matched": sum(1 for record in subset if record["source_runs"]["simple_justwatch"]["match_status"] == "matched"),
            "locale_titles": sum(
                1 for record in subset
                if any(
                    row["source_name"] == "simple-justwatch-python-api" and row["evidence_level"] == "title_level_verified"
                    for row in record["rows"]
                )
            ),
        }
    lines = [
        "# Free Streaming Availability Research Spike",
        "",
        f"- Benchmark titles: {len(title_records)} ({by_media_type['ANIME']} anime, {by_media_type['MANGA']} manga)",
        f"- Search country: {config.search_country}",
        f"- Configured countries: {', '.join(config.countries)}",
        f"- Deterministic title-match threshold: {TITLE_MATCH_THRESHOLD:.2f}",
        f"- JustWatch exact-match successes: {matched}/{len(title_records)}",
        "",
        "## Anime vs manga split",
        "",
        "| Media type | Titles | Deterministic JustWatch matches | Titles with title-level locale evidence |",
        "| --- | --- | --- | --- |",
        f"| Anime | {justwatch_by_type['ANIME']['total']} | {justwatch_by_type['ANIME']['matched']} | {justwatch_by_type['ANIME']['locale_titles']} |",
        f"| Manga | {justwatch_by_type['MANGA']['total']} | {justwatch_by_type['MANGA']['matched']} | {justwatch_by_type['MANGA']['locale_titles']} |",
        "",
        "## Source scorecard",
        "",
        "| Source | Status | Match success | Provider-country coverage | Title-level locale evidence | Contradiction rate | Unusable/noisy rate | Notes |",
        "| --- | --- | --- | --- | --- | --- | --- | --- |",
    ]
    for source_name, data in metrics.items():
        lines.append(
            "| {source} | {status} | {match} | {coverage} | {locale} | {contradiction} | {noise} | {notes} |".format(
                source=source_name,
                status=data["status"],
                match=data["title_match_success_rate"] if data["title_match_success_rate"] is not None else "n/a",
                coverage=data["provider_country_coverage"] if data["provider_country_coverage"] is not None else "n/a",
                locale=data["title_level_language_evidence_rate"] if data["title_level_language_evidence_rate"] is not None else "n/a",
                contradiction=data["contradiction_rate"] if data["contradiction_rate"] is not None else "n/a",
                noise=data["unusable_or_noisy_rate"] if data["unusable_or_noisy_rate"] is not None else "n/a",
                notes=data["notes"].replace("|", "/"),
            )
        )
    lines.extend([
        "",
        "## Manual review set",
        "",
        "### Highest-confidence positive cases",
    ])
    for item in manual_review["highest_confidence_positive_cases"]:
        examples = "; ".join(
            f"{row['provider_name_raw']} {row['country_code']} ({row['notes'] or 'no locale note'})"
            for row in item["examples"]
        )
        lines.append(f"- {item['media_type']} {item['media_id']} — {item['title']} [{item['match_confidence']:.2f}] :: {examples}")
    lines.extend(["", "### Suspicious / unresolved cases"])
    for item in manual_review["suspicious_mismatches"]:
        lines.append(f"- {item['media_type']} {item['media_id']} — {item['title']} :: {item['reason']}")
    lines.extend([
        "",
        "## Decision gate",
        "",
        "- Proceed only if title matching remains deterministic and manual review confirms the positives.",
        "- Do not productionize EN/DE dub copy from these free sources unless the title-level audio evidence is directly present.",
        "- Current expectation: anime may produce useful provider/country plus some locale signals; manga likely remains a rejection path.",
    ])
    precision_path.write_text("\n".join(lines) + "\n")

    unresolved_lines = [
        "# Unresolved / Mismatch Report",
        "",
        "## Adapter status",
        "",
    ]
    for status in adapter_statuses:
        unresolved_lines.append(f"- {status.name}: {'available' if status.available else 'unavailable'} — {status.notes}")
    unresolved_lines.extend(["", "## Title-level issues", ""])
    for record in title_records:
        justwatch = record["source_runs"].get("simple_justwatch")
        if not justwatch:
            continue
        if justwatch["match_status"] != "matched":
            unresolved_lines.append(
                f"- {record['benchmark']['media_type']} {record['benchmark']['media_id']} — {choose_query_title(record['benchmark'])}: {justwatch['match_status']} ({justwatch['notes']})"
            )
            continue
        if any(row["source_name"] == "simple-justwatch-python-api" and row["evidence_level"] == "no_signal" for row in record["rows"]):
            unresolved_lines.append(
                f"- {record['benchmark']['media_type']} {record['benchmark']['media_id']} — {choose_query_title(record['benchmark'])}: matched JustWatch title, but no FLATRATE/ADS/FREE offers in configured countries"
            )
        if any(row["source_name"] == "simple-justwatch-python-api" and row["provider_slug_candidate"] is None for row in record["rows"]):
            unresolved_lines.append(
                f"- {record['benchmark']['media_type']} {record['benchmark']['media_id']} — {choose_query_title(record['benchmark'])}: unmapped provider names present in JustWatch offers"
            )
    unresolved_path.write_text("\n".join(unresolved_lines) + "\n")


def run_spike(
    benchmark_entries: list[dict[str, Any]],
    report_dir: Path,
    provider_aliases: dict[str, str],
    config: SpikeConfig,
) -> dict[str, Any]:
    report_dir.mkdir(parents=True, exist_ok=True)
    justwatch = JustWatchGraphQLAdapter(config.simple_justwatch_repo, config.search_country)
    selenium = SeleniumJustWatchAdapter(config.selenium_repo)
    anime_streaming_hints = load_anime_streaming_hints(config.anime_streaming_repo / "README.md", provider_aliases)
    title_records: list[dict[str, Any]] = []

    for index, entry in enumerate(benchmark_entries, start=1):
        query_title = choose_query_title(entry)
        print(f"[{index:02d}/{len(benchmark_entries)}] {entry['media_type']} {entry['media_id']} :: {query_title}")
        source_runs: dict[str, Any] = {
            "justwatch_selenium": {
                "status": "unavailable",
                "notes": selenium.status.notes,
            }
        }
        rows: list[dict[str, Any]] = []
        if justwatch.status.available:
            try:
                results = justwatch.search(query_title)
                match = match_justwatch_entry(entry, results)
            except Exception as exc:
                match = MatchResult(
                    status="error",
                    confidence=0.0,
                    node_id=None,
                    matched_title=None,
                    matched_year=None,
                    query_title=query_title,
                    notes=f"JustWatch search failed: {exc.__class__.__name__}: {exc}",
                )
            source_runs["simple_justwatch"] = {
                "status": "available",
                "query_title": match.query_title,
                "match_status": match.status,
                "match_confidence": match.confidence,
                "matched_node_id": match.node_id,
                "matched_title": match.matched_title,
                "matched_year": match.matched_year,
                "notes": match.notes,
            }
            if match.status == "matched" and match.node_id:
                try:
                    offers = justwatch.offers_for_countries(match.node_id, config.countries)
                    rows = title_level_rows_for_entry(entry, offers, provider_aliases)
                except Exception as exc:
                    rows = [
                        {
                            "media_type": entry["media_type"],
                            "media_id": entry["media_id"],
                            "source_name": "simple-justwatch-python-api",
                            "source_match_confidence": match.confidence,
                            "provider_name_raw": None,
                            "provider_slug_candidate": None,
                            "country_code": None,
                            "link_url": None,
                            "audio_locales": [],
                            "subtitle_locales": [],
                            "language_hint_type": "unknown",
                            "evidence_level": "no_signal",
                            "notes": f"JustWatch offers lookup failed: {exc.__class__.__name__}: {exc}",
                        }
                    ]
            else:
                rows = [
                    {
                        "media_type": entry["media_type"],
                        "media_id": entry["media_id"],
                        "source_name": "simple-justwatch-python-api",
                        "source_match_confidence": match.confidence,
                        "provider_name_raw": None,
                        "provider_slug_candidate": None,
                        "country_code": None,
                        "link_url": None,
                        "audio_locales": [],
                        "subtitle_locales": [],
                        "language_hint_type": "unknown",
                        "evidence_level": "no_signal",
                        "notes": match.notes,
                    }
                ]
        else:
            source_runs["simple_justwatch"] = {
                "status": "unavailable",
                "query_title": query_title,
                "match_status": "error",
                "match_confidence": 0.0,
                "matched_title": None,
                "matched_year": None,
                "notes": justwatch.status.notes,
            }
            rows = [
                {
                    "media_type": entry["media_type"],
                    "media_id": entry["media_id"],
                    "source_name": "simple-justwatch-python-api",
                    "source_match_confidence": 0.0,
                    "provider_name_raw": None,
                    "provider_slug_candidate": None,
                    "country_code": None,
                    "link_url": None,
                    "audio_locales": [],
                    "subtitle_locales": [],
                    "language_hint_type": "unknown",
                    "evidence_level": "no_signal",
                    "notes": justwatch.status.notes,
                }
            ]

        if entry["media_type"] == "ANIME":
            rows = attach_anime_streaming_hints(rows, anime_streaming_hints)
        title_records.append(
            {
                "benchmark": entry,
                "source_runs": source_runs,
                "rows": rows,
            }
        )

    metrics = compute_source_metrics(title_records, [justwatch.status, selenium.status], config)
    manual_review = build_manual_review_set(title_records)
    aggregate_rows = aggregate_provider_country([row for record in title_records for row in record["rows"]])

    (report_dir / "title_by_title.json").write_text(
        json.dumps(
            {
                "benchmark_size": len(benchmark_entries),
                "search_country": config.search_country,
                "countries": config.countries,
                "match_threshold": TITLE_MATCH_THRESHOLD,
                "adapter_statuses": [status.__dict__ for status in [justwatch.status, selenium.status]],
                "source_metrics": metrics,
                "manual_review": manual_review,
                "titles": title_records,
            },
            indent=2,
            ensure_ascii=True,
        ) + "\n"
    )
    write_csv(report_dir / "provider_country_aggregate.csv", aggregate_rows)
    write_markdown_reports(report_dir, metrics, manual_review, title_records, [justwatch.status, selenium.status], config)

    return {
        "adapter_statuses": [status.__dict__ for status in [justwatch.status, selenium.status]],
        "source_metrics": metrics,
        "manual_review": manual_review,
        "title_count": len(title_records),
        "report_dir": str(report_dir),
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run a research-only spike for free streaming availability sources.")
    parser.add_argument("--benchmark", type=Path, default=DEFAULT_BENCHMARK_PATH)
    parser.add_argument("--provider-mappings", type=Path, default=DEFAULT_PROVIDER_MAPPINGS_PATH)
    parser.add_argument("--report-dir", type=Path, default=DEFAULT_REPORT_DIR)
    parser.add_argument("--simple-justwatch-repo", type=Path, default=DEFAULT_SIMPLE_JUSTWATCH_REPO)
    parser.add_argument("--selenium-repo", type=Path, default=DEFAULT_SELENIUM_REPO)
    parser.add_argument("--anime-streaming-repo", type=Path, default=DEFAULT_ANIME_STREAMING_REPO)
    parser.add_argument("--search-country", default=DEFAULT_SEARCH_COUNTRY)
    parser.add_argument("--limit", type=int, default=None, help="Optional cap on total benchmark rows for smoke runs")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    benchmark = load_json(args.benchmark)
    entries = benchmark["entries"]
    if args.limit is not None:
        entries = entries[: args.limit]
    provider_aliases = load_provider_alias_map(args.provider_mappings)
    config = SpikeConfig(
        simple_justwatch_repo=args.simple_justwatch_repo,
        selenium_repo=args.selenium_repo,
        anime_streaming_repo=args.anime_streaming_repo,
        search_country=args.search_country.upper(),
        countries=COUNTRIES,
    )
    summary = run_spike(entries, args.report_dir, provider_aliases, config)
    print(json.dumps(summary, indent=2, ensure_ascii=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
