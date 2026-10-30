-- DB hardening from Supabase advisors (security + performance).
-- - community_profiles: security_invoker view over a narrow DEFINER source
--   so only id/display_name/avatar_url are exposed and RLS on profiles stays
--   own-only (Flutter can still read own is_admin / deletion_requested_at).
-- - Revoke is_admin() EXECUTE from anon/PUBLIC; admin policies stay TO authenticated.
-- - Wrap auth.uid() as (select auth.uid()) in flagged RLS policies.
-- - Indexes on layout_ratings(rater_id) and published_layouts(author_id).
-- - Merge published_layouts admin+own permissive policies into one per command.

BEGIN;

-- ---------------------------------------------------------------------------
-- 1) community_profiles: clear security_definer_view ERROR
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.community_profile_rows()
RETURNS TABLE (id uuid, display_name text, avatar_url text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT p.id, p.display_name, p.avatar_url
  FROM public.profiles p;
$$;

REVOKE ALL ON FUNCTION public.community_profile_rows() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.community_profile_rows() TO anon, authenticated, service_role;

COMMENT ON FUNCTION public.community_profile_rows() IS
  'Narrow DEFINER source for community_profiles: public identity columns only.';

DROP VIEW IF EXISTS public.community_profiles;
CREATE VIEW public.community_profiles
WITH (security_invoker = true)
AS
SELECT id, display_name, avatar_url
FROM public.community_profile_rows();

COMMENT ON VIEW public.community_profiles IS
  'Public Community identity only (id, display_name, avatar_url). '
  'security_invoker; reads via community_profile_rows() so profiles RLS stays own-only. '
  'Does not expose deletion_requested_at or is_admin.';

REVOKE ALL ON public.community_profiles FROM PUBLIC;
GRANT SELECT ON public.community_profiles TO anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2) is_admin(): revoke anon / PUBLIC execute (storefront only calls when signed in)
-- ---------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.is_admin() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.is_admin() FROM anon;
GRANT EXECUTE ON FUNCTION public.is_admin() TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3) auth_rls_initplan: recreate flagged policies with (select auth.uid())
-- ---------------------------------------------------------------------------

-- profiles
DROP POLICY IF EXISTS profiles_select_own ON public.profiles;
CREATE POLICY profiles_select_own ON public.profiles
  FOR SELECT
  TO public
  USING ((select auth.uid()) = id);

DROP POLICY IF EXISTS profiles_insert_own ON public.profiles;
CREATE POLICY profiles_insert_own ON public.profiles
  FOR INSERT
  TO public
  WITH CHECK ((select auth.uid()) = id);

DROP POLICY IF EXISTS profiles_update_own ON public.profiles;
CREATE POLICY profiles_update_own ON public.profiles
  FOR UPDATE
  TO public
  USING ((select auth.uid()) = id)
  WITH CHECK ((select auth.uid()) = id);

-- rooms
DROP POLICY IF EXISTS rooms_select_own ON public.rooms;
CREATE POLICY rooms_select_own ON public.rooms
  FOR SELECT
  TO public
  USING ((select auth.uid()) = user_id);

DROP POLICY IF EXISTS rooms_insert_own ON public.rooms;
CREATE POLICY rooms_insert_own ON public.rooms
  FOR INSERT
  TO public
  WITH CHECK ((select auth.uid()) = user_id);

DROP POLICY IF EXISTS rooms_update_own ON public.rooms;
CREATE POLICY rooms_update_own ON public.rooms
  FOR UPDATE
  TO public
  USING ((select auth.uid()) = user_id)
  WITH CHECK ((select auth.uid()) = user_id);

DROP POLICY IF EXISTS rooms_delete_own ON public.rooms;
CREATE POLICY rooms_delete_own ON public.rooms
  FOR DELETE
  TO public
  USING ((select auth.uid()) = user_id);

-- layout_ratings
DROP POLICY IF EXISTS layout_ratings_select_visible ON public.layout_ratings;
CREATE POLICY layout_ratings_select_visible ON public.layout_ratings
  FOR SELECT
  TO public
  USING (
    EXISTS (
      SELECT 1 FROM public.published_layouts pl
      WHERE pl.id = layout_ratings.layout_id
        AND (pl.hidden = false OR pl.author_id = (select auth.uid()))
    )
  );

DROP POLICY IF EXISTS layout_ratings_insert_own ON public.layout_ratings;
CREATE POLICY layout_ratings_insert_own ON public.layout_ratings
  FOR INSERT
  TO public
  WITH CHECK (
    (select auth.uid()) = rater_id
    AND EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = (select auth.uid())
        AND nullif(trim(p.display_name), '') IS NOT NULL
        AND nullif(trim(p.avatar_url), '') IS NOT NULL
    )
    AND EXISTS (
      SELECT 1 FROM public.published_layouts pl
      WHERE pl.id = layout_ratings.layout_id
        AND pl.hidden = false
    )
  );

DROP POLICY IF EXISTS layout_ratings_update_own ON public.layout_ratings;
CREATE POLICY layout_ratings_update_own ON public.layout_ratings
  FOR UPDATE
  TO public
  USING ((select auth.uid()) = rater_id)
  WITH CHECK ((select auth.uid()) = rater_id);

DROP POLICY IF EXISTS layout_ratings_delete_own ON public.layout_ratings;
CREATE POLICY layout_ratings_delete_own ON public.layout_ratings
  FOR DELETE
  TO public
  USING ((select auth.uid()) = rater_id);

-- ---------------------------------------------------------------------------
-- 4) published_layouts: merge admin+own into one policy per command (safe OR)
--    + initplan wrap. Anon keeps SELECT of non-hidden only.
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS published_layouts_select_admin ON public.published_layouts;
DROP POLICY IF EXISTS published_layouts_select_visible ON public.published_layouts;
DROP POLICY IF EXISTS published_layouts_insert_admin ON public.published_layouts;
DROP POLICY IF EXISTS published_layouts_insert_own ON public.published_layouts;
DROP POLICY IF EXISTS published_layouts_update_admin ON public.published_layouts;
DROP POLICY IF EXISTS published_layouts_update_own ON public.published_layouts;
DROP POLICY IF EXISTS published_layouts_delete_admin ON public.published_layouts;
DROP POLICY IF EXISTS published_layouts_delete_own ON public.published_layouts;

CREATE POLICY published_layouts_select_anon ON public.published_layouts
  FOR SELECT
  TO anon
  USING (hidden = false);

CREATE POLICY published_layouts_select ON public.published_layouts
  FOR SELECT
  TO authenticated
  USING (
    hidden = false
    OR author_id = (select auth.uid())
    OR public.is_admin()
  );

CREATE POLICY published_layouts_insert ON public.published_layouts
  FOR INSERT
  TO authenticated
  WITH CHECK (
    public.is_admin()
    OR (
      (select auth.uid()) = author_id
      AND is_admin_baseline = false
      AND EXISTS (
        SELECT 1 FROM public.profiles p
        WHERE p.id = (select auth.uid())
          AND nullif(trim(p.display_name), '') IS NOT NULL
          AND nullif(trim(p.avatar_url), '') IS NOT NULL
      )
    )
  );

CREATE POLICY published_layouts_update ON public.published_layouts
  FOR UPDATE
  TO authenticated
  USING (
    public.is_admin()
    OR ((select auth.uid()) = author_id AND is_admin_baseline = false)
  )
  WITH CHECK (
    public.is_admin()
    OR ((select auth.uid()) = author_id AND is_admin_baseline = false)
  );

CREATE POLICY published_layouts_delete ON public.published_layouts
  FOR DELETE
  TO authenticated
  USING (
    public.is_admin()
    OR ((select auth.uid()) = author_id AND is_admin_baseline = false)
  );

-- ---------------------------------------------------------------------------
-- 5) Missing FK indexes
-- ---------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS layout_ratings_rater_id_idx
  ON public.layout_ratings (rater_id);

CREATE INDEX IF NOT EXISTS published_layouts_author_id_idx
  ON public.published_layouts (author_id);

COMMIT;
