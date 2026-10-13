-- Run in Supabase SQL Editor. This stores public lesson cards only.
create table if not exists public.lessons (
 id text primary key check (length(id) between 1 and 100),
 owner_id uuid not null references auth.users(id) on delete cascade,
 data jsonb not null check (jsonb_typeof(data)='object' and data->>'id'=id and length(data::text)<150000),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
alter table public.lessons enable row level security;
revoke all on public.lessons from anon;
grant select on public.lessons to anon, authenticated;
grant insert, update, delete on public.lessons to authenticated;
create policy "Everyone can read lessons" on public.lessons for select to anon, authenticated using (true);
create policy "Authenticated users create own lessons" on public.lessons for insert to authenticated with check (auth.uid()=owner_id);
create policy "Authors edit own lessons" on public.lessons for update to authenticated using (auth.uid()=owner_id) with check (auth.uid()=owner_id);
create policy "Authors delete own lessons" on public.lessons for delete to authenticated using (auth.uid()=owner_id);
