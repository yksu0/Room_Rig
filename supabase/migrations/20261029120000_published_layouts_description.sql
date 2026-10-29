-- Community posts: optional caption/description on published layouts.
alter table public.published_layouts
  add column if not exists description text;

comment on column public.published_layouts.description is
  'Optional post caption shown under the title in Community feed.';
