-- Run in the EXISTING Supabase project's SQL Editor.
-- Independent objects; does not modify public.sfera_items or existing lessons.
BEGIN;
CREATE TABLE IF NOT EXISTS public.modo_teachers (
 user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS public.modo_classes (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 teacher_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
 title text NOT NULL CHECK (char_length(title) BETWEEN 2 AND 100),
 created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE (id,teacher_id)
);
CREATE TABLE IF NOT EXISTS public.modo_assignments (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 class_id uuid NOT NULL,
 teacher_id uuid NOT NULL,
 title text NOT NULL CHECK (char_length(title) BETWEEN 2 AND 120),
 topic integer NOT NULL DEFAULT -1 CHECK(topic BETWEEN -1 AND 3),
 created_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(class_id,teacher_id) REFERENCES public.modo_classes(id,teacher_id) ON DELETE CASCADE
);
CREATE TABLE IF NOT EXISTS public.modo_results (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 assignment_id uuid NOT NULL REFERENCES public.modo_assignments(id) ON DELETE CASCADE,
 student_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
 score integer NOT NULL CHECK(score BETWEEN 0 AND 12),
 total integer NOT NULL CHECK(total BETWEEN 1 AND 12),
 answers jsonb NOT NULL DEFAULT '{}'::jsonb,
 created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(assignment_id,student_id)
);
ALTER TABLE public.modo_teachers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.modo_classes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.modo_assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.modo_results ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.modo_teachers,public.modo_classes,public.modo_assignments,public.modo_results FROM anon;
GRANT SELECT ON public.modo_teachers TO authenticated;
GRANT SELECT,INSERT,UPDATE,DELETE ON public.modo_classes,public.modo_assignments TO authenticated;
GRANT SELECT ON public.modo_results TO authenticated;
DROP POLICY IF EXISTS modo_teacher_self ON public.modo_teachers;
CREATE POLICY modo_teacher_self ON public.modo_teachers FOR SELECT TO authenticated USING (user_id=(select auth.uid()));
DROP POLICY IF EXISTS modo_class_owner ON public.modo_classes;
CREATE POLICY modo_class_owner ON public.modo_classes FOR ALL TO authenticated USING (teacher_id=(select auth.uid()) AND EXISTS(SELECT 1 FROM public.modo_teachers t WHERE t.user_id=(select auth.uid()))) WITH CHECK (teacher_id=(select auth.uid()) AND EXISTS(SELECT 1 FROM public.modo_teachers t WHERE t.user_id=(select auth.uid())));
DROP POLICY IF EXISTS modo_assignment_owner ON public.modo_assignments;
CREATE POLICY modo_assignment_owner ON public.modo_assignments FOR ALL TO authenticated USING (teacher_id=(select auth.uid()) AND EXISTS(SELECT 1 FROM public.modo_teachers t WHERE t.user_id=(select auth.uid()))) WITH CHECK (teacher_id=(select auth.uid()) AND EXISTS(SELECT 1 FROM public.modo_teachers t WHERE t.user_id=(select auth.uid())));
DROP POLICY IF EXISTS modo_result_teacher_read ON public.modo_results;
CREATE POLICY modo_result_teacher_read ON public.modo_results FOR SELECT TO authenticated USING (EXISTS(SELECT 1 FROM public.modo_assignments a WHERE a.id=assignment_id AND a.teacher_id=(select auth.uid())) OR student_id=(select auth.uid()));
COMMIT;
-- IMPORTANT: create an email/password account via Supabase Authentication > Users.
-- Then separately authorize the teacher using their real UUID:
-- INSERT INTO public.modo_teachers(user_id) VALUES ('YOUR_AUTH_USER_UUID') ON CONFLICT DO NOTHING;
-- No anonymous result writes are allowed. Student assignment submission is NOT activated in this stage.
