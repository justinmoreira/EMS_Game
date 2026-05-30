set check_function_bodies = off;

CREATE OR REPLACE FUNCTION public.activate_match_on_guest_join()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$BEGIN IF NEW.guest_id IS NOT NULL AND OLD.guest_id IS NULL AND NEW.status = 'waiting' THEN NEW.status := 'active'; END IF; RETURN NEW; END;$function$
;

CREATE TRIGGER trg_activate_match_on_guest_join BEFORE UPDATE ON public.matches FOR EACH ROW EXECUTE FUNCTION public.activate_match_on_guest_join();


