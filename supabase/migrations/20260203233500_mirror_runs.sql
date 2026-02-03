begin;

-- Track mirror-images runs so schedules can be verified and failures diagnosed.
create table if not exists public.mirror_runs (
  id bigserial primary key,
  status text not null default 'running', -- running | success | error | skipped
  payload jsonb,
  results jsonb,
  message text,
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  duration_ms integer
);

create index if not exists idx_mirror_runs_started_at on public.mirror_runs (started_at desc);

commit;

