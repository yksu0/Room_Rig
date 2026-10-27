-- Benchmark social: published layouts, ratings, admin flag, feed helpers.
-- Baselines are SQL-seeded only (clients cannot set is_admin_baseline = true).

alter table public.profiles
  add column if not exists is_admin boolean not null default false;

comment on column public.profiles.is_admin is
  'Web admin panel gate. Flip via SQL: UPDATE profiles SET is_admin = true WHERE id = …';

-- ---------------------------------------------------------------------------
-- published_layouts
-- ---------------------------------------------------------------------------
create table if not exists public.published_layouts (
  id uuid primary key default gen_random_uuid(),
  author_id uuid references public.profiles (id) on delete cascade,
  title text not null,
  layout jsonb not null,
  scores jsonb,
  tags text[] not null default '{}',
  is_admin_baseline boolean not null default false,
  featured_until timestamptz,
  published_at timestamptz not null default now(),
  hidden boolean not null default false,
  constraint published_layouts_author_baseline_chk check (
    (is_admin_baseline and author_id is null)
    or (not is_admin_baseline and author_id is not null)
  )
);

create index if not exists published_layouts_published_at_idx
  on public.published_layouts (published_at desc)
  where hidden = false;

create index if not exists published_layouts_baseline_idx
  on public.published_layouts (is_admin_baseline)
  where hidden = false and is_admin_baseline;

alter table public.published_layouts enable row level security;

grant select, insert, update, delete on table public.published_layouts
  to anon, authenticated, service_role;

-- Guest + signed-in browse of visible layouts.
drop policy if exists "published_layouts_select_visible" on public.published_layouts;
create policy "published_layouts_select_visible"
  on public.published_layouts for select
  using (
    hidden = false
    or author_id = auth.uid()
  );

-- Community publish: complete profile, never admin-baseline from client.
drop policy if exists "published_layouts_insert_own" on public.published_layouts;
create policy "published_layouts_insert_own"
  on public.published_layouts for insert
  with check (
    auth.uid() = author_id
    and is_admin_baseline = false
    and exists (
      select 1 from public.profiles p
      where p.id = auth.uid()
        and nullif(trim(p.display_name), '') is not null
        and nullif(trim(p.avatar_url), '') is not null
    )
  );

drop policy if exists "published_layouts_update_own" on public.published_layouts;
create policy "published_layouts_update_own"
  on public.published_layouts for update
  using (auth.uid() = author_id and is_admin_baseline = false)
  with check (
    auth.uid() = author_id
    and is_admin_baseline = false
  );

drop policy if exists "published_layouts_delete_own" on public.published_layouts;
create policy "published_layouts_delete_own"
  on public.published_layouts for delete
  using (auth.uid() = author_id and is_admin_baseline = false);

-- ---------------------------------------------------------------------------
-- layout_ratings
-- ---------------------------------------------------------------------------
create table if not exists public.layout_ratings (
  layout_id uuid not null references public.published_layouts (id) on delete cascade,
  rater_id uuid not null references public.profiles (id) on delete cascade,
  vote smallint not null check (vote in (-1, 1)),
  tags text[] not null default '{}',
  updated_at timestamptz not null default now(),
  primary key (layout_id, rater_id)
);

create index if not exists layout_ratings_layout_id_idx
  on public.layout_ratings (layout_id);

alter table public.layout_ratings enable row level security;

grant select, insert, update, delete on table public.layout_ratings
  to anon, authenticated, service_role;

drop policy if exists "layout_ratings_select_visible" on public.layout_ratings;
create policy "layout_ratings_select_visible"
  on public.layout_ratings for select
  using (
    exists (
      select 1 from public.published_layouts pl
      where pl.id = layout_id and (pl.hidden = false or pl.author_id = auth.uid())
    )
  );

drop policy if exists "layout_ratings_upsert_own" on public.layout_ratings;
create policy "layout_ratings_insert_own"
  on public.layout_ratings for insert
  with check (
    auth.uid() = rater_id
    and exists (
      select 1 from public.profiles p
      where p.id = auth.uid()
        and nullif(trim(p.display_name), '') is not null
        and nullif(trim(p.avatar_url), '') is not null
    )
    and exists (
      select 1 from public.published_layouts pl
      where pl.id = layout_id and pl.hidden = false
    )
  );

drop policy if exists "layout_ratings_update_own" on public.layout_ratings;
create policy "layout_ratings_update_own"
  on public.layout_ratings for update
  using (auth.uid() = rater_id)
  with check (auth.uid() = rater_id);

drop policy if exists "layout_ratings_delete_own" on public.layout_ratings;
create policy "layout_ratings_delete_own"
  on public.layout_ratings for delete
  using (auth.uid() = rater_id);

-- ---------------------------------------------------------------------------
-- Stats + monthly featured helpers
-- ---------------------------------------------------------------------------
create or replace view public.layout_rating_stats
with (security_invoker = true)
as
select
  pl.id as layout_id,
  coalesce(sum(case when lr.vote = 1 then 1 else 0 end), 0)::int as up_count,
  coalesce(sum(case when lr.vote = -1 then 1 else 0 end), 0)::int as down_count,
  coalesce(sum(lr.vote), 0)::int as net_score
from public.published_layouts pl
left join public.layout_ratings lr on lr.layout_id = pl.id
group by pl.id;

grant select on public.layout_rating_stats to anon, authenticated, service_role;

-- Top 3 non-baseline community layouts by net score that received any vote
-- in the previous calendar month (empty until there is rating activity).
create or replace view public.monthly_featured_layouts
with (security_invoker = true)
as
select pl.*
from public.published_layouts pl
join public.layout_rating_stats s on s.layout_id = pl.id
where pl.hidden = false
  and pl.is_admin_baseline = false
  and exists (
    select 1 from public.layout_ratings lr
    where lr.layout_id = pl.id
      and lr.updated_at >= date_trunc('month', now() - interval '1 month')
      and lr.updated_at < date_trunc('month', now())
  )
order by s.net_score desc, pl.published_at desc
limit 3;

grant select on public.monthly_featured_layouts to anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Seed admin baselines (author_id null). Idempotent by title.
-- ---------------------------------------------------------------------------
insert into public.published_layouts (title, layout, scores, tags, is_admin_baseline, author_id)
select
  'Baseline: Gaming Setup',
  '{
    "name": "Gaming Setup",
    "presetName": "gamingSetup",
    "gridCols": 6,
    "gridRows": 8,
    "furniture": [
      {"id":"desk","name":"Gaming Desk","iconName":"desk","category":"ergonomics","gridX":1,"gridY":1,"width":1,"height":1,"yawDegrees":0,"airflowImpact":0,"lightingImpact":-0.1,"ergonomicsImpact":0.6,"cost":5500},
      {"id":"chair","name":"Gaming Chair","iconName":"chair","category":"ergonomics","gridX":1,"gridY":2,"width":1,"height":1,"yawDegrees":180,"airflowImpact":-0.2,"lightingImpact":0,"ergonomicsImpact":0.8,"cost":5500},
      {"id":"pc","name":"PC Tower","iconName":"pc","category":"airflow","gridX":1.2,"gridY":1,"width":1,"height":1,"yawDegrees":0,"airflowImpact":-0.4,"lightingImpact":0.1,"ergonomicsImpact":0,"cost":55000},
      {"id":"monitor","name":"Gaming Monitor","iconName":"monitor","category":"ergonomics","gridX":2.2,"gridY":1,"width":1,"height":1,"yawDegrees":0,"airflowImpact":0,"lightingImpact":0,"ergonomicsImpact":0.7,"cost":6500},
      {"id":"lamp","name":"RGB Desk Lamp","iconName":"lamp","category":"lighting","gridX":3.2,"gridY":1,"width":1,"height":1,"yawDegrees":0,"airflowImpact":0,"lightingImpact":0.45,"ergonomicsImpact":0,"cost":1200},
      {"id":"bed","name":"Bed","iconName":"bed","category":"neutral","gridX":3,"gridY":4,"width":1,"height":1,"yawDegrees":0,"airflowImpact":-0.3,"lightingImpact":0,"ergonomicsImpact":-0.2,"cost":12000},
      {"id":"ac","name":"AC Unit","iconName":"ac","category":"airflow","gridX":4.5,"gridY":0,"width":1,"height":1,"yawDegrees":0,"airflowImpact":0.9,"lightingImpact":0,"ergonomicsImpact":0,"cost":25000},
      {"id":"window","name":"Window","iconName":"window","category":"lighting","gridX":2,"gridY":0,"width":1,"height":1,"yawDegrees":0,"airflowImpact":0.5,"lightingImpact":0.8,"ergonomicsImpact":0,"cost":8000},
      {"id":"door","name":"Entry Door","iconName":"door","category":"neutral","gridX":0,"gridY":6,"width":1,"height":1,"yawDegrees":0,"airflowImpact":0.35,"lightingImpact":0,"ergonomicsImpact":0.2,"cost":4500},
      {"id":"fan","name":"Stand Fan","iconName":"fan","category":"airflow","gridX":4,"gridY":2,"width":1,"height":1,"yawDegrees":0,"airflowImpact":0.55,"lightingImpact":0,"ergonomicsImpact":0,"cost":1500}
    ]
  }'::jsonb,
  '{"overall":72,"airflow":70,"lighting":68,"ergonomics":74,"spatial":65}'::jsonb,
  array['baseline','gaming'],
  true,
  null
where not exists (
  select 1 from public.published_layouts where title = 'Baseline: Gaming Setup' and is_admin_baseline
);

insert into public.published_layouts (title, layout, scores, tags, is_admin_baseline, author_id)
select
  'Baseline: Home Office',
  '{
    "name": "Home Office",
    "presetName": "homeOffice",
    "gridCols": 6,
    "gridRows": 8,
    "furniture": [
      {"id":"desk","name":"Standing Desk","iconName":"desk","category":"ergonomics","gridX":0,"gridY":1,"width":1,"height":1,"yawDegrees":0,"airflowImpact":0,"lightingImpact":0.1,"ergonomicsImpact":0.9,"cost":10000},
      {"id":"chair","name":"Ergonomic Chair","iconName":"chair","category":"ergonomics","gridX":0,"gridY":2,"width":1,"height":1,"yawDegrees":180,"airflowImpact":0,"lightingImpact":0,"ergonomicsImpact":0.9,"cost":8000},
      {"id":"monitor","name":"Monitor","iconName":"monitor","category":"ergonomics","gridX":0.5,"gridY":1,"width":1,"height":1,"yawDegrees":0,"airflowImpact":0,"lightingImpact":0,"ergonomicsImpact":0.7,"cost":5500},
      {"id":"lamp","name":"Desk Lamp","iconName":"lamp","category":"lighting","gridX":1.5,"gridY":1,"width":1,"height":1,"yawDegrees":0,"airflowImpact":0,"lightingImpact":0.6,"ergonomicsImpact":0,"cost":800},
      {"id":"window","name":"Large Window","iconName":"window","category":"lighting","gridX":3,"gridY":0,"width":1,"height":1,"yawDegrees":0,"airflowImpact":0.7,"lightingImpact":0.9,"ergonomicsImpact":0,"cost":8000},
      {"id":"door","name":"Office Door","iconName":"door","category":"neutral","gridX":0,"gridY":6,"width":1,"height":1,"yawDegrees":0,"airflowImpact":0.3,"lightingImpact":0,"ergonomicsImpact":0.25,"cost":4500},
      {"id":"plant","name":"Plant","iconName":"plant","category":"airflow","gridX":5,"gridY":2,"width":1,"height":1,"yawDegrees":0,"airflowImpact":0.3,"lightingImpact":0,"ergonomicsImpact":0.2,"cost":350},
      {"id":"sofa","name":"Sofa","iconName":"sofa","category":"neutral","gridX":1,"gridY":5,"width":1,"height":1,"yawDegrees":0,"airflowImpact":-0.3,"lightingImpact":0,"ergonomicsImpact":0.2,"cost":15000}
    ]
  }'::jsonb,
  '{"overall":78,"airflow":72,"lighting":80,"ergonomics":85,"spatial":70}'::jsonb,
  array['baseline','office'],
  true,
  null
where not exists (
  select 1 from public.published_layouts where title = 'Baseline: Home Office' and is_admin_baseline
);
