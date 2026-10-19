-- МОДО: подключение ученических попыток к СУЩЕСТВУЮЩЕМУ Supabase.
-- Запустить ПОСЛЕ supabase-modo-teacher.sql. Существующие учителя/классы/назначения сохраняются.
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgcrypto;
ALTER TABLE public.modo_assignments ADD COLUMN IF NOT EXISTS access_code text;
ALTER TABLE public.modo_assignments ADD COLUMN IF NOT EXISTS active boolean NOT NULL DEFAULT true;
ALTER TABLE public.modo_results ALTER COLUMN student_id DROP NOT NULL;
ALTER TABLE public.modo_results ADD COLUMN IF NOT EXISTS student_name text;
ALTER TABLE public.modo_results ADD COLUMN IF NOT EXISTS elapsed_seconds integer NOT NULL DEFAULT 0;
ALTER TABLE public.modo_results ADD COLUMN IF NOT EXISTS attempt_token_hash text;
ALTER TABLE public.modo_results ADD COLUMN IF NOT EXISTS started_at timestamptz;
ALTER TABLE public.modo_results ADD COLUMN IF NOT EXISTS finished_at timestamptz;
-- Ensure legacy rows don't conflict with new anonymous attempts.
CREATE UNIQUE INDEX IF NOT EXISTS modo_assignments_access_code_idx ON public.modo_assignments(access_code);
CREATE OR REPLACE FUNCTION public.modo_new_access_code() RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $$
BEGIN
 IF NEW.access_code IS NULL THEN NEW.access_code := upper(substr(encode(gen_random_bytes(8),'hex'),1,8)); END IF;
 RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS modo_assignment_code_trigger ON public.modo_assignments;
CREATE TRIGGER modo_assignment_code_trigger BEFORE INSERT ON public.modo_assignments FOR EACH ROW EXECUTE FUNCTION public.modo_new_access_code();
UPDATE public.modo_assignments SET access_code=upper(substr(encode(gen_random_bytes(8),'hex'),1,8)) WHERE access_code IS NULL;
ALTER TABLE public.modo_assignments ALTER COLUMN access_code SET NOT NULL;
-- Answer key is stored on the database side, not supplied by the pupil.
CREATE OR REPLACE FUNCTION public.modo_answer_key() RETURNS integer[] LANGUAGE sql IMMUTABLE SET search_path='' AS $$ SELECT ARRAY[1,2,0,3,0,2,1,3,0,2,1,3]::integer[] $$;
REVOKE ALL ON FUNCTION public.modo_answer_key() FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.modo_join_work(p_code text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE a record; ids integer[];
BEGIN
 SELECT id,title,topic,active INTO a FROM public.modo_assignments WHERE access_code=upper(trim(p_code)) LIMIT 1;
 IF NOT FOUND OR NOT a.active THEN RAISE EXCEPTION 'Код работы не найден или работа закрыта'; END IF;
 SELECT array_agg(i ORDER BY i) INTO ids FROM generate_series(0,11) i WHERE a.topic=-1 OR i/3=a.topic;
 RETURN jsonb_build_object('roomTitle',a.title,'topicTitle',CASE WHEN a.topic=-1 THEN 'Все темы' ELSE 'Тема '||(a.topic+1)::text END,'questionIds',to_jsonb(ids),'durationSeconds',CASE WHEN a.topic=-1 THEN 600 ELSE 180 END);
END $$;
CREATE OR REPLACE FUNCTION public.modo_start_attempt(p_code text,p_name text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE a record; ids integer[]; tok text; rid uuid; started timestamptz; duration integer;
BEGIN
 IF char_length(trim(p_name)) NOT BETWEEN 2 AND 80 THEN RAISE EXCEPTION 'Введите имя (2–80 символов)'; END IF;
 SELECT id,title,topic,active INTO a FROM public.modo_assignments WHERE access_code=upper(trim(p_code)) LIMIT 1;
 IF NOT FOUND OR NOT a.active THEN RAISE EXCEPTION 'Код работы не найден или работа закрыта'; END IF;
 SELECT array_agg(i ORDER BY i) INTO ids FROM generate_series(0,11) i WHERE a.topic=-1 OR i/3=a.topic;
 tok:=encode(gen_random_bytes(32),'hex'); started:=now(); duration:=CASE WHEN a.topic=-1 THEN 600 ELSE 180 END;
 INSERT INTO public.modo_results(assignment_id,student_name,score,total,answers,attempt_token_hash,started_at,created_at)
 VALUES(a.id,trim(p_name),0,cardinality(ids),'{}'::jsonb,encode(sha256(decode(tok,'hex')),'hex'),started,started) RETURNING id INTO rid;
 RETURN jsonb_build_object('id',rid,'token',tok,'roomTitle',a.title,'questionIds',to_jsonb(ids),'durationSeconds',duration,'startedAt',extract(epoch FROM started)*1000,'deadline',extract(epoch FROM started+make_interval(secs=>duration))*1000,'topic',a.topic);
END $$;
CREATE OR REPLACE FUNCTION public.modo_finish_attempt(p_attempt uuid,p_token text,p_answers jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE r record; a record; ids integer[]; key integer[]; i integer; score_value integer:=0; cleaned jsonb:='[]'::jsonb; val jsonb; elapsed integer; answer_index integer;
BEGIN
 IF p_token IS NULL OR length(p_token)<>64 OR p_answers IS NULL OR jsonb_typeof(p_answers)<>'array' OR jsonb_array_length(p_answers)<>12 THEN RAISE EXCEPTION 'Некорректные данные попытки'; END IF;
 SELECT * INTO r FROM public.modo_results WHERE id=p_attempt FOR UPDATE;
 IF NOT FOUND OR r.attempt_token_hash IS NULL OR r.attempt_token_hash<>encode(sha256(decode(p_token,'hex')),'hex') THEN RAISE EXCEPTION 'Попытка не найдена'; END IF;
 IF r.finished_at IS NOT NULL THEN RETURN jsonb_build_object('saved',true,'score',r.score,'answers',r.answers); END IF;
 SELECT topic,active INTO a FROM public.modo_assignments WHERE id=r.assignment_id;
 IF NOT FOUND OR NOT a.active THEN RAISE EXCEPTION 'Работа закрыта'; END IF;
 SELECT array_agg(n ORDER BY n) INTO ids FROM generate_series(0,11) n WHERE a.topic=-1 OR n/3=a.topic;
 key:=public.modo_answer_key();
 FOR i IN 0..11 LOOP
   val:=p_answers->i;
   IF val IS NULL OR val='null'::jsonb THEN cleaned:=cleaned||'null'::jsonb;
   ELSIF jsonb_typeof(val)='number' AND val::text ~ '^[0-3]$' THEN
     answer_index:=(val::text)::integer;
     IF i=ANY(ids) AND answer_index=key[i+1] THEN score_value:=score_value+1; END IF;
     cleaned:=cleaned||jsonb_build_array(answer_index);
   ELSE RAISE EXCEPTION 'Недопустимый вариант ответа'; END IF;
 END LOOP;
 elapsed:=greatest(0,floor(extract(epoch FROM now()-r.started_at))::integer);
 IF elapsed>CASE WHEN a.topic=-1 THEN 660 ELSE 240 END THEN RAISE EXCEPTION 'Время работы истекло. Попросите учителя открыть новую попытку.'; END IF;
 UPDATE public.modo_results SET score=score_value,answers=cleaned,elapsed_seconds=elapsed,finished_at=now(),created_at=now() WHERE id=p_attempt;
 RETURN jsonb_build_object('saved',true,'score',score_value,'answers',cleaned);
END $$;
REVOKE ALL ON FUNCTION public.modo_join_work(text),public.modo_start_attempt(text,text),public.modo_finish_attempt(uuid,text,jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.modo_join_work(text),public.modo_start_attempt(text,text),public.modo_finish_attempt(uuid,text,jsonb) TO anon,authenticated;
-- Anonymous students have no direct access to tables; only constrained RPC operations.
REVOKE ALL ON public.modo_results FROM anon;
GRANT SELECT ON public.modo_results TO authenticated;
-- Do not allow a pupil to fetch results without teacher authorization.
DROP POLICY IF EXISTS modo_result_teacher_read ON public.modo_results;
CREATE POLICY modo_result_teacher_read ON public.modo_results FOR SELECT TO authenticated USING (EXISTS(SELECT 1 FROM public.modo_assignments a WHERE a.id=assignment_id AND a.teacher_id=(select auth.uid())) OR student_id=(select auth.uid()));
COMMIT;
