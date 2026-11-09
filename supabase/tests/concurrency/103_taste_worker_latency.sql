-- Worker skips a locked queue row; a requeue cannot be lost behind its processed stamp.
-- @requires extension dblink
-- @requires table public.taste_profile_recompute_queue
-- @requires function public.drain_taste_recompute_queue()
\set ON_ERROR_STOP on
\o /dev/null
select tests.make_user(103);
select tests.make_user(104);
select tests.make_user(105);
select tests.make_user(106);
select tests.make_user(107);
select tests.make_user(108);
delete from public.taste_profile_recompute_queue;
insert into public.taste_profile_recompute_queue(user_id,requested_at,processed_at)
 select tests.uid(i),now()-interval '1 hour'+i*interval '1 second',null from generate_series(103,108) i;
create or replace function public.recompute_user_taste_profile(p_user_id uuid) returns void
language plpgsql security definer set search_path=public,extensions as $$begin return;end $$;
select tests.actor_open('held_queue', :'conn') as held_pid \gset
select tests.actor_exec('held_queue','begin');
select tests.actor_exec('held_queue',format('select user_id::text from public.taste_profile_recompute_queue where user_id=%L for update',tests.uid(103)));
set statement_timeout='2s';
select public.drain_taste_recompute_queue();
reset statement_timeout;
select tests.eq('worker skipped the locked oldest row and processed five other rows',
 (select count(*) from public.taste_profile_recompute_queue where processed_at is not null),5::bigint);
select tests.ok('locked row is still pending',
 (select processed_at is null from public.taste_profile_recompute_queue where user_id=tests.uid(103)));
select tests.actor_exec('held_queue','commit');
select public.drain_taste_recompute_queue();
select tests.eq('released row is processed on the next drain',
 (select count(*) from public.taste_profile_recompute_queue where processed_at is null),0::bigint);

-- Hold a drained transaction while a concurrent signal requests fresh work.
update public.taste_profile_recompute_queue set processed_at=null where user_id=tests.uid(103);
select tests.actor_exec('held_queue','begin');
select tests.actor_exec('held_queue','select public.drain_taste_recompute_queue()');
select tests.actor_open('new_signal', :'conn') as signal_pid \gset
select tests.actor_send('new_signal',format('update public.taste_profile_recompute_queue set processed_at=null,requested_at=clock_timestamp() where user_id=%L returning user_id::text',tests.uid(103)));
select tests.wait_lock_wait(:signal_pid) as waited \gset
select tests.ok('new signal waits for the claimed queue row',:held_pid=any(pg_blocking_pids(:signal_pid)));
select tests.actor_exec('held_queue','commit');
select tests.actor_result('new_signal');
select tests.ok('new signal survives the prior processed stamp',
 (select processed_at is null from public.taste_profile_recompute_queue where user_id=tests.uid(103)));
select tests.actor_close('held_queue');
select tests.actor_close('new_signal');
