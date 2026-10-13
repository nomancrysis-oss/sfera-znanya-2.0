-- RUN ONCE in Supabase SQL Editor, after supabase-setup.sql.
-- Do not run this with an admin UUID until the email/password user exists.
BEGIN;
CREATE TABLE IF NOT EXISTS public.site_admins (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.site_admins ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.site_admins FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.site_admins TO authenticated;
DROP POLICY IF EXISTS "Admins can read own membership" ON public.site_admins;
CREATE POLICY "Admins can read own membership" ON public.site_admins
  FOR SELECT TO authenticated USING (user_id = (SELECT auth.uid()));

-- RLS helper checks membership server-side, never trusts browser-side roles.
CREATE OR REPLACE FUNCTION public.is_site_admin()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = '' AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.site_admins
    WHERE user_id = (SELECT auth.uid())
  );
$$;
REVOKE ALL ON FUNCTION public.is_site_admin() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_site_admin() TO authenticated;

-- Replace author-only deletion policy with author-or-admin deletion.
DROP POLICY IF EXISTS "Authors delete own lessons" ON public.lessons;
DROP POLICY IF EXISTS "Authors or admins delete lessons" ON public.lessons;
CREATE POLICY "Authors or admins delete lessons" ON public.lessons
  FOR DELETE TO authenticated
  USING (owner_id = (SELECT auth.uid()) OR (SELECT public.is_site_admin()));
COMMIT;

-- AFTER creating an email/password account in Authentication > Users,
-- find its UUID and run this SEPARATELY in SQL Editor:
-- INSERT INTO public.site_admins(user_id)
-- VALUES ('REPLACE_WITH_REAL_AUTH_USER_UUID')
-- ON CONFLICT (user_id) DO NOTHING;
-- Do NOT insert the anonymous account UUID; use your permanent email account.
