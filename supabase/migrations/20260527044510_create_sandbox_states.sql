
  create table "public"."sandbox_states" (
    "user_id" uuid not null,
    "slot_id" text not null,
    "name" text not null default ''::text,
    "state_json" jsonb not null,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now(),
    "gamemode" text not null default 'sandbox'::text
      );


alter table "public"."sandbox_states" enable row level security;

CREATE UNIQUE INDEX sandbox_states_pkey ON public.sandbox_states USING btree (user_id, slot_id);

CREATE INDEX sandbox_states_user_mode_idx ON public.sandbox_states USING btree (user_id, gamemode);

alter table "public"."sandbox_states" add constraint "sandbox_states_pkey" PRIMARY KEY using index "sandbox_states_pkey";

alter table "public"."sandbox_states" add constraint "sandbox_states_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE not valid;

alter table "public"."sandbox_states" validate constraint "sandbox_states_user_id_fkey";

grant delete on table "public"."sandbox_states" to "anon";

grant insert on table "public"."sandbox_states" to "anon";

grant references on table "public"."sandbox_states" to "anon";

grant select on table "public"."sandbox_states" to "anon";

grant trigger on table "public"."sandbox_states" to "anon";

grant truncate on table "public"."sandbox_states" to "anon";

grant update on table "public"."sandbox_states" to "anon";

grant delete on table "public"."sandbox_states" to "authenticated";

grant insert on table "public"."sandbox_states" to "authenticated";

grant references on table "public"."sandbox_states" to "authenticated";

grant select on table "public"."sandbox_states" to "authenticated";

grant trigger on table "public"."sandbox_states" to "authenticated";

grant truncate on table "public"."sandbox_states" to "authenticated";

grant update on table "public"."sandbox_states" to "authenticated";

grant delete on table "public"."sandbox_states" to "service_role";

grant insert on table "public"."sandbox_states" to "service_role";

grant references on table "public"."sandbox_states" to "service_role";

grant select on table "public"."sandbox_states" to "service_role";

grant trigger on table "public"."sandbox_states" to "service_role";

grant truncate on table "public"."sandbox_states" to "service_role";

grant update on table "public"."sandbox_states" to "service_role";


  create policy "Users can delete own sandbox states"
  on "public"."sandbox_states"
  as permissive
  for delete
  to public
using ((auth.uid() = user_id));



  create policy "Users can insert own sandbox states"
  on "public"."sandbox_states"
  as permissive
  for insert
  to public
with check ((auth.uid() = user_id));



  create policy "Users can read own sandbox states"
  on "public"."sandbox_states"
  as permissive
  for select
  to public
using ((auth.uid() = user_id));



  create policy "Users can update own sandbox states"
  on "public"."sandbox_states"
  as permissive
  for update
  to public
using ((auth.uid() = user_id));


CREATE TRIGGER on_sandbox_states_updated BEFORE UPDATE ON public.sandbox_states FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();


