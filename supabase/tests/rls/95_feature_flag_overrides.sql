-- Administrator-managed Release cohort: self-read only, no client writes.
-- @requires table public.feature_flags
\set ON_ERROR_STOP on
begin;
select tests.make_user(96), tests.make_user(97);
insert into public.feature_flags(flag_name,enabled,rollout_percentage) values
 ('release_cohort_test',false,0) on conflict do nothing;
insert into public.feature_flag_overrides(user_id,flag_name,enabled) values
 (tests.uid(96),'release_cohort_test',true), (tests.uid(97),'release_cohort_test',false);
select tests.as_user(tests.uid(96));
select tests.eq('owner reads only own cohort',tests.rowcount('select * from public.feature_flag_overrides'),1::bigint);
select tests.ok('owner sees assigned decision',(select enabled from public.feature_flag_overrides));
select tests.denied('client cannot insert cohort','insert into public.feature_flag_overrides values (auth.uid(), ''series_home_native_v1'', true)');
select tests.denied('client cannot update cohort','update public.feature_flag_overrides set enabled=false');
select tests.denied('client cannot delete cohort','delete from public.feature_flag_overrides');
select tests.as_anon();
select tests.denied('anonymous cannot read private cohort','select * from public.feature_flag_overrides');
select tests.reset();
delete from auth.users where id=tests.uid(96);
select tests.eq('account deletion cascades cohort',(select count(*) from public.feature_flag_overrides where user_id=tests.uid(96)),0::bigint);
select tests.eq('global rollout unchanged',(select rollout_percentage from public.feature_flags where flag_name='release_cohort_test'),0);
rollback;
