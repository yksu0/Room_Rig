-- Room Rig storefront admin RLS
-- Status: reviewed locally; NOT applied (awaiting npx supabase db push --linked).
-- Context (2026-10-29): live DB already blocks clients from writing profiles.is_admin.
-- Source of truth for admin: public.profiles.is_admin (NOT auth JWT app_metadata).
-- This migration only adds public.is_admin() + admin policies on published_layouts.

BEGIN;

-- Trusted server-side check used by the Next admin UI via supabase.rpc('is_admin').
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(
    (SELECT p.is_admin FROM public.profiles p WHERE p.id = auth.uid()),
    false
  );
$$;

REVOKE ALL ON FUNCTION public.is_admin() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_admin() TO anon, authenticated;

COMMENT ON FUNCTION public.is_admin() IS
  'Returns profiles.is_admin for auth.uid(). SECURITY DEFINER; profiles.is_admin is not client-writable.';

-- Admins can SELECT all layouts including hidden (Community moderation).
DROP POLICY IF EXISTS published_layouts_select_admin ON public.published_layouts;
CREATE POLICY published_layouts_select_admin ON public.published_layouts
  FOR SELECT
  TO authenticated
  USING (public.is_admin());

-- Admins can INSERT baselines (author_id NULL + is_admin_baseline true) and other rows.
DROP POLICY IF EXISTS published_layouts_insert_admin ON public.published_layouts;
CREATE POLICY published_layouts_insert_admin ON public.published_layouts
  FOR INSERT
  TO authenticated
  WITH CHECK (public.is_admin());

-- Admins can UPDATE any layout (hide/unhide, featured_until, baseline edits).
DROP POLICY IF EXISTS published_layouts_update_admin ON public.published_layouts;
CREATE POLICY published_layouts_update_admin ON public.published_layouts
  FOR UPDATE
  TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

-- Admins can DELETE baselines / moderated posts.
DROP POLICY IF EXISTS published_layouts_delete_admin ON public.published_layouts;
CREATE POLICY published_layouts_delete_admin ON public.published_layouts
  FOR DELETE
  TO authenticated
  USING (public.is_admin());

COMMIT;
