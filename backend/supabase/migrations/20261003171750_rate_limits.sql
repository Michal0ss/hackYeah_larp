-- Shared rate limiting across backend instances (Vercel has several). Fixed time window, one
-- atomic upsert-and-read function so two concurrent requests can't both slip through. Only
-- service_role can reach this (RLS on, no policies; anon/authenticated explicitly revoked).
create table public.rate_limits (
  bucket text not null, client_key text not null, window_start timestamptz not null,
  hits int not null default 0, primary key (bucket, client_key, window_start));
alter table public.rate_limits enable row level security;  -- bez polityk: tylko service_role

create or replace function public.rate_limit_hit(p_bucket text, p_client text, p_limit int, p_window_seconds int)
returns table(allowed boolean, retry_after int) language plpgsql security definer set search_path = public as $$
declare ws timestamptz := to_timestamp(floor(extract(epoch from now()) / p_window_seconds) * p_window_seconds); h int;
begin
  insert into rate_limits(bucket, client_key, window_start, hits) values (p_bucket, p_client, ws, 1)
  on conflict (bucket, client_key, window_start) do update set hits = rate_limits.hits + 1
  returning hits into h;
  if random() < 0.02 then delete from rate_limits where window_start < now() - interval '1 hour'; end if;
  return query select h <= p_limit,
    greatest(1, ceil(extract(epoch from (ws + make_interval(secs => p_window_seconds) - now())))::int);
end $$;

revoke all on function public.rate_limit_hit(text, text, int, int) from public, anon, authenticated;
grant execute on function public.rate_limit_hit(text, text, int, int) to service_role;
