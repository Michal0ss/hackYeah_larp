-- Accounts: the minimum a person needs to move to another phone. Name, the onboarding answers that are NOT health
-- data, and the training plan. The e-mail lives in auth.users (Supabase Auth, Google sign-in) and is not copied here.
--
-- NEVER put health data in these tables: no injuries, conditions, screening answers, check-ins, sleep, heart rate.
-- That stays on the phone (HealthHistory) or in Apple Health. Besides the app not sending it, the CHECK constraints below
-- refuse the keys that would carry it, so a client bug cannot leak it by accident.
--
-- Not synced on purpose, because they say something about health even without a diagnosis:
--   UserProfile.avoid      free text "czego unikać" (may describe an injury)
--   UserProfile.avoidTags  movements left out, derived from the injuries answers
--   UserProfile.easyStart  set when the screening suggests caution
--   TrainingPlan.notices   how the plan came to be (one of them reveals that the free text was typed)
--
-- Every row belongs to one user and only that user can read or change it (RLS, policies on auth.uid()). anon gets
-- nothing. Deleting the auth user deletes their rows (on delete cascade); deleting the auth user needs the service
-- role, so the app asks the backend to do it (a later endpoint), it cannot do it from the phone.

create table public.profiles (
  user_id uuid primary key references auth.users (id) on delete cascade,
  first_name text not null default '' check (char_length(first_name) <= 100),
  last_name text not null default '' check (char_length(last_name) <= 100),
  -- goal, level, daysPerWeek, sessionMinutes, equipment, gear (UserProfile minus the health-derived fields)
  onboarding jsonb not null default '{}'::jsonb
    check (
      jsonb_typeof(onboarding) = 'object'
      and pg_column_size(onboarding) <= 8192
      and not (onboarding ?| array['health', 'healthHistory', 'injuries', 'conditions', 'answers', 'avoid', 'avoidTags', 'easyStart'])
    ),
  -- what the person agreed to and when (accountability under GDPR); the text of the policy lives in the repo/app
  terms_accepted_at timestamptz,
  policy_version text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.training_plans (
  user_id uuid primary key references auth.users (id) on delete cascade,
  -- TrainingPlan as the app encodes it, without `notices`
  plan jsonb not null
    check (
      jsonb_typeof(plan) = 'object'
      and pg_column_size(plan) <= 262144
      and not (plan ? 'notices')
    ),
  schema_version int not null default 1,
  updated_at timestamptz not null default now()
);

create or replace function public.set_updated_at() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.updated_at = now();
  return new;
end $$;

create trigger profiles_set_updated_at before update on public.profiles
  for each row execute function public.set_updated_at();
create trigger training_plans_set_updated_at before update on public.training_plans
  for each row execute function public.set_updated_at();

alter table public.profiles enable row level security;
alter table public.training_plans enable row level security;

-- Supabase grants new tables to anon and authenticated by default; anon must get nothing here.
revoke all on public.profiles, public.training_plans from anon;

create policy profiles_select_own on public.profiles for select to authenticated
  using ((select auth.uid()) = user_id);
create policy profiles_insert_own on public.profiles for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy profiles_update_own on public.profiles for update to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy profiles_delete_own on public.profiles for delete to authenticated
  using ((select auth.uid()) = user_id);

create policy training_plans_select_own on public.training_plans for select to authenticated
  using ((select auth.uid()) = user_id);
create policy training_plans_insert_own on public.training_plans for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy training_plans_update_own on public.training_plans for update to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy training_plans_delete_own on public.training_plans for delete to authenticated
  using ((select auth.uid()) = user_id);
