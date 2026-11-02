-- 20261102100000_contact_messages.sql
-- PREPARED, NOT DEPLOYED (2026-11-02, contact form). Deploying needs explicit owner approval.
--
-- Owner decision 2026-11-02: no phone number in the Impressum; the second fast contact channel
-- (§ 5 Abs. 1 Nr. 2 DDG) is a contact form on the legal website (web/legal/kontakt.html) and in
-- the app (Profile > Contact us). Both post to the Edge Function `contact-submit`, which validates,
-- rate-limits and stores the message here with the SERVICE ROLE.
--
--   * public.contact_messages: RLS enabled with NO policies and every table privilege revoked
--     from anon/authenticated: clients can neither read nor write it (service role only).
--   * user_id comes ONLY from a verified JWT in the Edge Function; ON DELETE SET NULL, so account
--     deletion unlinks the message (it stays until the 12-month purge; privacy policy §4.15/§8).
--   * purge_contact_messages_v1(): deletes rows older than 12 months; service role / cron only.
--   * pg_cron job 'contact-messages-retention' runs it daily (re-runnable: unscheduled first).
--
-- Rollback (after export, if wanted):
--   select cron.unschedule('contact-messages-retention');
--   drop function if exists public.purge_contact_messages_v1();
--   drop table if exists public.contact_messages;

begin;

set local lock_timeout = '3s';

create table if not exists public.contact_messages (
  id          uuid primary key default gen_random_uuid(),
  created_at  timestamptz not null default now(),
  source      text not null check (source in ('web', 'app')),
  topic       text not null check (topic in ('general', 'support', 'privacy', 'legal_notice', 'report_content', 'other')),
  email       text not null check (
                char_length(email) <= 254
                and email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'
              ),
  name        text null check (name is null or char_length(name) <= 120),
  message     text not null check (char_length(message) between 1 and 4000),
  user_id     uuid null references auth.users (id) on delete set null,
  app_version text null check (app_version is null or char_length(app_version) <= 40),
  locale      text null check (locale is null or char_length(locale) <= 10),
  status      text not null default 'new' check (status in ('new', 'handled'))
);

comment on table public.contact_messages is
  'Contact form / in-app contact messages (20261102100000). Written only by the contact-submit Edge Function with the service role; no client policies. Purged after 12 months by purge_contact_messages_v1().';

create index if not exists contact_messages_created_at_idx on public.contact_messages (created_at);
create index if not exists contact_messages_user_id_idx on public.contact_messages (user_id) where user_id is not null;

alter table public.contact_messages enable row level security;
-- No policies on purpose: anon/authenticated get nothing even if a grant reappears.
revoke all on table public.contact_messages from public, anon, authenticated;
grant select, insert, update, delete on table public.contact_messages to service_role;

create or replace function public.purge_contact_messages_v1()
returns integer
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  _deleted integer;
begin
  delete from public.contact_messages
  where created_at < now() - interval '12 months';
  get diagnostics _deleted = row_count;
  return _deleted;
end;
$$;

comment on function public.purge_contact_messages_v1() is
  'Deletes contact_messages older than 12 months (privacy policy retention). Service role / pg_cron only.';

revoke all on function public.purge_contact_messages_v1() from public, anon, authenticated;
grant execute on function public.purge_contact_messages_v1() to service_role;

-- Daily retention job; unschedule-then-schedule keeps a re-run idempotent (one job, latest command).
do $$
begin
  if exists (select 1 from cron.job where jobname = 'contact-messages-retention') then
    perform cron.unschedule('contact-messages-retention');
  end if;
  perform cron.schedule('contact-messages-retention', '50 4 * * *', 'select public.purge_contact_messages_v1();');
end $$;

commit;
