Kuro Knowledge Directory
========================

Purpose
- One-stop, LLM-friendly knowledge base for the entire app: architecture, code map, backend schema/edge functions, dataflows, and production tasks.
- Updated continuously whenever code changes. See update rules in PART-02.

How To Use (LLMs and humans)
- Need overall context? Read PART-01 Master Overview first.
- Need paths and rules? Read PART-02 Codebase Map & Rules (includes quick TODO summary).
- Need database/schema/functions/schedules/storage? Read PART-03 Backend Data & Infra.
- Need iOS app architecture: models/views/services? Read PART-04 App Architecture.
- Need end-to-end dataflow/API specifics? Read PART-05 API & Dataflow.
- Need a comprehensive production checklist? Read PART-06 Production TODO.

Parts
- PART-01 Master Overview → PART-01_MASTER_OVERVIEW.md
- PART-02 Codebase Map & Rules (includes quick TODO) → PART-02_CODEBASE_MAP_AND_RULES.md
- PART-03 Backend Data & Infra → PART-03_BACKEND_DATA_INFRA.md
- PART-04 App Architecture → PART-04_APP_ARCHITECTURE.md
- PART-05 API & Dataflow → PART-05_API_AND_DATAFLOW.md
- PART-06 Production TODO → PART-06_PRODUCTION_TODO.md
- PART-07 Functionality Deep Dives → PART-07_FUNCTIONALITY_DEEP_DIVES.md

Appendices (Deep Indexes)
- PART-00 File Map (exhaustive paths, counts) → PART-00_FILE_MAP.md
- APPENDIX Symbol Index (per-file types/functions anchors) → APPENDIX_SYMBOL_INDEX.md
- APPENDIX Query Inventory (client queries with filters/orders) → APPENDIX_QUERY_INVENTORY.md
- APPENDIX Edge Functions (payloads, behavior, touched tables) → APPENDIX_EDGE_FUNCTIONS.md
- APPENDIX Code Metrics (line counts) → APPENDIX_CODE_METRICS.md
- APPENDIX SQL Table Definitions (columns) → APPENDIX_SQL_TABLE_DEFS.md
- APPENDIX View ↔ Service Links → APPENDIX_VIEW_SERVICE_LINKS.md
- APPENDIX Dependency Graph & Boundaries → APPENDIX_DEPENDENCY_GRAPH.md
- APPENDIX Responsibilities & Gotchas → APPENDIX_RESPONSIBILITIES_GOTCHAS.md
- APPENDIX Database State (live metrics) → APPENDIX_DB_STATE.md

Project Reference
- Supabase project: https://bkdifromsqxkndnllmdj.supabase.co
- App config reads keys from Info.plist/env and falls back if absent: Kuro/Services/SupabaseService.swift:55, Kuro/Services/AppConfig.swift:1
