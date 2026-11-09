---
paths:
  - "supabase/**"
  - "scripts/**"
---

# Kuro backend adapter

Apply the backend, authorization, concurrency and data-hygiene sections of root
`AGENTS.md`; resolve all applicable routes in `agents/routes.yaml` before editing.
New SQL is prepared locally. Deployment, history repair, upstream mutations and
production fixtures require their own authorization; command examples grant none.
Verify actual clients, handler/RPC contracts, effective grants and latest migrations.
Use focused offline/local checks and state their fixture/replay limitations.
