-- Training history in the person's account: one generic table for the records that follow a person to another phone.
-- Kinds (what the app syncs):
--   logged_set        a set the person did (reps or seconds, weight only when typed), `LoggedSet` in the app
--   completion        a planned session that was finished, `SessionCompletion`
--   technique_result  an analysis of a recorded clip: score, findings, per-rep numbers (no poses, no video)
--   set_summary       a set with the live coach: tempo, technique score, findings (no poses, no video)
--   step_goal         the daily step goal set by the trainer
--
-- NEVER here: video, poses, chat text, Apple Health data, check-ins (mood, stress, energy), feedback after a workout
-- (effort, pain) or the health history. Besides the app not sending them, the CHECK below refuses the keys that would
-- carry them, so a client bug cannot leak them by accident.
--
-- Every row belongs to one user and only that user can read or change it (RLS on auth.uid()). anon gets nothing.
-- Deleting the auth user deletes the rows (on delete cascade; the backend does that: DELETE /v1/account).

create table public.user_records (
  user_id uuid not null references auth.users (id) on delete cascade,
  kind text not null check (kind in ('logged_set', 'completion', 'technique_result', 'set_summary', 'step_goal')),
  -- the app's own id of the record (a UUID), so syncing the same record twice is an upsert, not a copy
  record_id text not null check (char_length(record_id) between 1 and 64),
  data jsonb not null
    check (
      jsonb_typeof(data) = 'object'
      and pg_column_size(data) <= 32768
      and not (data ?| array['joints', 'frames', 'poses', 'video', 'pain', 'perceivedExertion', 'note', 'mood',
                             'stress', 'energy', 'health', 'healthHistory', 'messages'])
    ),
  -- when the thing happened (a set, a session, an analysis), not when it was synced
  occurred_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, kind, record_id)
);

create index user_records_user_kind_time on public.user_records (user_id, kind, occurred_at desc);

create or replace function public.touch_user_record() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.updated_at = now();
  return new;
end $$;

create trigger user_records_touch before update on public.user_records
  for each row execute function public.touch_user_record();

alter table public.user_records enable row level security;

-- Supabase grants new tables to anon and authenticated by default: anon gets nothing, authenticated only what RLS covers.
revoke all on public.user_records from anon;
revoke truncate, references, trigger on public.user_records from authenticated;

create policy user_records_select_own on public.user_records for select to authenticated
  using ((select auth.uid()) = user_id);
create policy user_records_insert_own on public.user_records for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy user_records_update_own on public.user_records for update to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy user_records_delete_own on public.user_records for delete to authenticated
  using ((select auth.uid()) = user_id);
