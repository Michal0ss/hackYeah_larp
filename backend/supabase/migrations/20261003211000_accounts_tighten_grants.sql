-- Supabase gives `authenticated` every privilege on new tables in public by default. RLS covers select/insert/update/
-- delete, but not TRUNCATE (it skips row-level security). PostgREST does not expose TRUNCATE, so the app cannot run it,
-- still: take away what is not needed (defense in depth). Applied to the `forma` project right after `accounts`.
revoke truncate, references, trigger on public.profiles, public.training_plans from authenticated;
