drop extension if exists "pg_net";


  create table "public"."signal_entries" (
    "id" uuid not null default gen_random_uuid(),
    "signal_id" uuid not null,
    "body" text not null,
    "source" text,
    "created_at" timestamp with time zone not null default now(),
    "created_by" uuid,
    "kind" text not null default 'note'::text,
    "severity" text,
    "area" text
      );


alter table "public"."signal_entries" enable row level security;


  create table "public"."signals" (
    "id" uuid not null default gen_random_uuid(),
    "title" text not null,
    "description" text,
    "created_at" timestamp with time zone not null default now(),
    "created_by" uuid
      );


alter table "public"."signals" enable row level security;

CREATE INDEX idx_entries_prod_issue_created ON public.signal_entries USING btree (signal_id, created_at DESC) WHERE (kind = ANY (ARRAY['risk'::text, 'observation'::text]));

CREATE INDEX idx_entries_signal_created ON public.signal_entries USING btree (signal_id, created_at DESC);

CREATE INDEX idx_entries_signal_kind_created ON public.signal_entries USING btree (signal_id, kind, created_at DESC);

CREATE INDEX idx_signal_entries_prod_only ON public.signal_entries USING btree (signal_id, created_at) WHERE (kind = ANY (ARRAY['risk'::text, 'observation'::text]));

CREATE INDEX idx_signal_entries_signal_created ON public.signal_entries USING btree (signal_id, created_at DESC);

CREATE INDEX signal_entries_created_at_signal_id_desc_idx ON public.signal_entries USING btree (created_at DESC, signal_id);

CREATE INDEX signal_entries_created_by_created_at_idx ON public.signal_entries USING btree (created_by, created_at DESC);

CREATE INDEX signal_entries_created_by_idx ON public.signal_entries USING btree (created_by);

CREATE UNIQUE INDEX signal_entries_pkey ON public.signal_entries USING btree (id);

CREATE INDEX signal_entries_prod_issue_created_at_idx ON public.signal_entries USING btree (created_at DESC) WHERE ((kind = ANY (ARRAY['production_issue'::text, 'incident'::text, 'outage'::text])) OR (severity = ANY (ARRAY['sev0'::text, 'sev1'::text, 'sev2'::text, 'p0'::text, 'p1'::text, 'p2'::text, 'critical'::text, 'high'::text])));

CREATE INDEX signal_entries_prod_partial_idx ON public.signal_entries USING btree (signal_id, created_at DESC) WHERE public.is_production_issue(kind, body);

CREATE INDEX signal_entries_production_issue_idx ON public.signal_entries USING btree (signal_id, created_at DESC) WHERE public.classify_production_issue(kind, body);

CREATE INDEX signal_entries_signal_created_at_idx ON public.signal_entries USING btree (signal_id, created_at DESC);

CREATE INDEX signal_entries_signal_created_idx ON public.signal_entries USING btree (signal_id, created_at DESC);

CREATE INDEX signal_entries_signal_id_created_at_desc_idx ON public.signal_entries USING btree (signal_id, created_at DESC);

CREATE INDEX signal_entries_signal_id_created_at_idx ON public.signal_entries USING btree (signal_id, created_at DESC);

CREATE INDEX signal_entries_signal_id_kind_created_at_desc_idx ON public.signal_entries USING btree (signal_id, kind, created_at DESC);

CREATE INDEX signal_entries_signal_id_kind_created_at_idx ON public.signal_entries USING btree (signal_id, kind, created_at DESC);

CREATE INDEX signal_entries_signal_id_kind_idx ON public.signal_entries USING btree (signal_id, kind);

CREATE INDEX signals_created_at_idx ON public.signals USING btree (created_at DESC);

CREATE INDEX signals_created_by_created_at_idx ON public.signals USING btree (created_by, created_at DESC);

CREATE UNIQUE INDEX signals_pkey ON public.signals USING btree (id);

alter table "public"."signal_entries" add constraint "signal_entries_pkey" PRIMARY KEY using index "signal_entries_pkey";

alter table "public"."signals" add constraint "signals_pkey" PRIMARY KEY using index "signals_pkey";

alter table "public"."signal_entries" add constraint "signal_entries_area_check" CHECK (((area IS NULL) OR (area = ANY (ARRAY['line'::text, 'machine'::text, 'qc'::text, 'material'::text, 'staffing'::text, 'logistics'::text, 'other'::text])))) not valid;

alter table "public"."signal_entries" validate constraint "signal_entries_area_check";

alter table "public"."signal_entries" add constraint "signal_entries_created_by_fkey" FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL not valid;

alter table "public"."signal_entries" validate constraint "signal_entries_created_by_fkey";

alter table "public"."signal_entries" add constraint "signal_entries_kind_check" CHECK ((kind = ANY (ARRAY['note'::text, 'observation'::text, 'risk'::text, 'action'::text, 'question'::text]))) not valid;

alter table "public"."signal_entries" validate constraint "signal_entries_kind_check";

alter table "public"."signal_entries" add constraint "signal_entries_severity_check" CHECK (((severity IS NULL) OR (severity = ANY (ARRAY['low'::text, 'medium'::text, 'high'::text, 'critical'::text])))) not valid;

alter table "public"."signal_entries" validate constraint "signal_entries_severity_check";

alter table "public"."signal_entries" add constraint "signal_entries_signal_id_fkey" FOREIGN KEY (signal_id) REFERENCES public.signals(id) ON DELETE CASCADE not valid;

alter table "public"."signal_entries" validate constraint "signal_entries_signal_id_fkey";

alter table "public"."signals" add constraint "signals_created_by_fkey" FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL not valid;

alter table "public"."signals" validate constraint "signals_created_by_fkey";

set check_function_bodies = off;

CREATE OR REPLACE FUNCTION public._ms_norm(txt text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select lower(coalesce(txt, ''));
$function$
;

CREATE OR REPLACE FUNCTION public.classify_production_issue(p_kind text, p_body text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select
    p_kind in ('risk', 'observation')
    and (
      p_body ilike '%production%'
      or p_body ilike '%slow%'
      or p_body ilike '%delay%'
      or p_body ilike '%outage%'
      or p_body ilike '%failure%'
      or p_body ilike '%blocked%'
      or p_body ilike '%incident%'
    );
$function$
;

CREATE OR REPLACE FUNCTION public.is_production_issue(e public.signal_entries)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  select
    (
      public._ms_norm(e.kind) in ('production_issue', 'incident', 'outage')
    )
    or
    (
      public._ms_norm(e.severity) in ('sev0','sev1','sev2','p0','p1','p2','critical','high')
    )
    or
    (
      public._ms_norm(e.source) like '%pagerduty%'
      or public._ms_norm(e.source) like '%alert%'
      or public._ms_norm(e.source) like '%monitor%'
      or public._ms_norm(e.source) like '%sentry%'
      or public._ms_norm(e.source) like '%datadog%'
      or public._ms_norm(e.source) like '%new relic%'
    )
    or
    (
      public._ms_norm(e.body) like '%outage%'
      or public._ms_norm(e.body) like '%downtime%'
      or public._ms_norm(e.body) like '%incident%'
      or public._ms_norm(e.body) like '%sev1%'
      or public._ms_norm(e.body) like '%sev2%'
      or public._ms_norm(e.body) like '%p0%'
      or public._ms_norm(e.body) like '%p1%'
      or public._ms_norm(e.body) like '%error rate%'
      or public._ms_norm(e.body) like '%500%'
      or public._ms_norm(e.body) like '%latency%'
      or public._ms_norm(e.body) like '%degraded%'
      or public._ms_norm(e.body) like '%failed%'
      or public._ms_norm(e.body) like '%timeout%'
      or public._ms_norm(e.body) like '%unavailable%'
    );
$function$
;

CREATE OR REPLACE FUNCTION public.is_production_issue(p_kind text, p_body text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select
    p_kind in ('risk', 'observation')
    and p_body ~* '(slow|delay|blocked|failure|error|downtime|production)';
$function$
;

CREATE OR REPLACE FUNCTION public.prod_tags(p_kind text, p_body text)
 RETURNS text[]
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select array_remove(array[
    case when p_kind in ('risk','observation') then 'signal_kind' end,
    case when p_body ilike '%production%' then 'production' end,
    case when p_body ilike '%slow%' or p_body ilike '%latency%' then 'slow' end,
    case when p_body ilike '%downtime%' or p_body ilike '%outage%' then 'outage' end,
    case when p_body ilike '%blocked%' or p_body ilike '%stuck%' then 'blocked' end,
    case when p_body ilike '%defect%' or p_body ilike '%bug%' then 'bug' end,
    case when p_body ilike '%quality%' or p_body ilike '%scrap%' or p_body ilike '%rework%' then 'quality' end,
    case when p_body ilike '%machine%' or p_body ilike '%equipment%' then 'equipment' end
  ], null);
$function$
;

CREATE OR REPLACE FUNCTION public.production_decision(p_count_24h integer, p_count_7d integer, p_minutes_since_last integer)
 RETURNS TABLE(severity text, severity_score integer, recommended_action text)
 LANGUAGE sql
 IMMUTABLE
AS $function$
  with score as (
    select
      -- score components (tune later)
      (least(p_count_24h, 20) * 5)  -- heavy weight recent
    + (least(p_count_7d, 50) * 1)   -- lighter weight week
    + (case
        when p_minutes_since_last is null then 0
        when p_minutes_since_last <= 60 then 25
        when p_minutes_since_last <= 180 then 15
        when p_minutes_since_last <= 1440 then 5
        else 0
      end) as s
  )
  select
    case
      when s >= 60 then 'critical'
      when s >= 35 then 'high'
      when s >= 15 then 'medium'
      else 'low'
    end as severity,
    s as severity_score,
    case
      when s >= 60 then 'Escalate now: assign owner, open incident, stop-the-line if needed.'
      when s >= 35 then 'Investigate today: identify bottleneck/root cause, set corrective action.'
      when s >= 15 then 'Monitor: collect more evidence, confirm scope, prepare mitigation.'
      else 'No action: track normally.'
    end as recommended_action
  from score;
$function$
;

CREATE OR REPLACE FUNCTION public.production_issue_reason(e public.signal_entries)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  select
    case
      when public._ms_norm(e.kind) in ('production_issue','incident','outage') then 'kind'
      when public._ms_norm(e.severity) in ('sev0','sev1','sev2','p0','p1','p2','critical','high') then 'severity'
      when public._ms_norm(e.source) like '%pagerduty%' then 'source:pagerduty'
      when public._ms_norm(e.source) like '%sentry%' then 'source:sentry'
      when public._ms_norm(e.source) like '%datadog%' then 'source:datadog'
      when public._ms_norm(e.body) like '%outage%' or public._ms_norm(e.body) like '%downtime%' then 'body:outage'
      when public._ms_norm(e.body) like '%error rate%' or public._ms_norm(e.body) like '%500%' then 'body:error'
      when public._ms_norm(e.body) like '%latency%' or public._ms_norm(e.body) like '%timeout%' then 'body:latency'
      when public.is_production_issue(e) then 'body:other'
      else null
    end;
$function$
;

CREATE OR REPLACE FUNCTION public.production_issue_score(e public.signal_entries)
 RETURNS integer
 LANGUAGE sql
 STABLE
AS $function$
  select
    (case when public._ms_norm(e.kind) in ('production_issue','incident','outage') then 50 else 0 end)
  + (case when public._ms_norm(e.severity) in ('sev0','p0','critical') then 40
          when public._ms_norm(e.severity) in ('sev1','p1','high') then 25
          when public._ms_norm(e.severity) in ('sev2','p2','medium') then 15
          else 0 end)
  + (case when public._ms_norm(e.source) like '%pagerduty%' then 20
          when public._ms_norm(e.source) like '%sentry%' or public._ms_norm(e.source) like '%datadog%' or public._ms_norm(e.source) like '%new relic%' then 10
          when public._ms_norm(e.source) like '%alert%' or public._ms_norm(e.source) like '%monitor%' then 8
          else 0 end)
  + (case when public._ms_norm(e.body) like '%outage%' or public._ms_norm(e.body) like '%downtime%' then 20 else 0 end)
  + (case when public._ms_norm(e.body) like '%error rate%' or public._ms_norm(e.body) like '%500%' then 12 else 0 end)
  + (case when public._ms_norm(e.body) like '%latency%' or public._ms_norm(e.body) like '%timeout%' then 8 else 0 end)
  + (case when public._ms_norm(e.body) like '%degraded%' or public._ms_norm(e.body) like '%unavailable%' then 8 else 0 end);
$function$
;

CREATE OR REPLACE FUNCTION public.production_recommendation(_has_critical_2h boolean, _risks_24h integer, _minutes_since_last_entry integer, _primary_area text)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
select
  case
    when coalesce(_has_critical_2h,false) then 'Escalate now (critical in last 2h)'
    when coalesce(_risks_24h,0) >= 3 then 'Open containment action (3+ risks in 24h)'
    when coalesce(_minutes_since_last_entry,999999) >= 2880 then 'Request update (no entries in 48h)'
    when _primary_area = 'machine' then 'Check maintenance and downtime logs'
    when _primary_area = 'material' then 'Quarantine batch + notify procurement'
    when _primary_area = 'qc' then 'Increase sampling + verify QC criteria'
    else 'Collect more observations (add who/where/when)'
  end;
$function$
;

create or replace view "public"."signal_entries_enriched" as  SELECT id,
    signal_id,
    body,
    source,
    created_at,
    created_by,
    kind,
    severity,
    area,
    public.is_production_issue(kind, body) AS is_production_issue
   FROM public.signal_entries se;


create or replace view "public"."v_signal_entries_enriched" as  SELECT id,
    signal_id,
    body,
    source,
    kind,
    severity,
    area,
    created_at,
    created_by,
    public.is_production_issue(e.*) AS is_production_issue,
    public.production_issue_score(e.*) AS production_issue_score,
    public.production_issue_reason(e.*) AS production_issue_reason
   FROM public.signal_entries e;


create or replace view "public"."production_decision_by_signal" as  WITH prod AS (
         SELECT signal_entries_enriched.signal_id,
            count(*) FILTER (WHERE signal_entries_enriched.is_production_issue) AS prod_count_total,
            count(*) FILTER (WHERE (signal_entries_enriched.is_production_issue AND (signal_entries_enriched.created_at >= (now() - '7 days'::interval)))) AS prod_count_7d,
            (EXTRACT(epoch FROM (now() - max(signal_entries_enriched.created_at) FILTER (WHERE signal_entries_enriched.is_production_issue))) / 60.0) AS minutes_since_last_prod_issue
           FROM public.signal_entries_enriched
          GROUP BY signal_entries_enriched.signal_id
        )
 SELECT signal_id,
    prod_count_total,
    prod_count_7d,
    minutes_since_last_prod_issue,
    (((COALESCE(prod_count_7d, (0)::bigint) * 2))::numeric - COALESCE(LEAST((minutes_since_last_prod_issue / 60.0), (24)::numeric), (0)::numeric)) AS severity_score
   FROM prod;


create or replace view "public"."v_production_decisions" as  WITH prod AS (
         SELECT e.signal_id,
            e.created_at,
            e.production_issue_score
           FROM public.v_signal_entries_enriched e
          WHERE (e.is_production_issue = true)
        ), agg AS (
         SELECT s.id AS signal_id,
            count(*) FILTER (WHERE (p.created_at >= (now() - '24:00:00'::interval))) AS prod_issues_24h,
            count(*) FILTER (WHERE (p.created_at >= (now() - '7 days'::interval))) AS prod_issues_7d,
            max(p.created_at) AS last_prod_issue_at,
            COALESCE(sum(p.production_issue_score) FILTER (WHERE (p.created_at >= (now() - '7 days'::interval))), (0)::bigint) AS severity_score_7d
           FROM (public.signals s
             LEFT JOIN prod p ON ((p.signal_id = s.id)))
          GROUP BY s.id
        )
 SELECT signal_id,
    prod_issues_24h,
    prod_issues_7d,
    last_prod_issue_at,
        CASE
            WHEN (last_prod_issue_at IS NULL) THEN NULL::numeric
            ELSE (EXTRACT(epoch FROM (now() - last_prod_issue_at)) / (60)::numeric)
        END AS minutes_since_last_prod_issue,
    severity_score_7d,
        CASE
            WHEN (prod_issues_24h > 0) THEN 'incident'::text
            WHEN (severity_score_7d >= 80) THEN 'investigate'::text
            WHEN (severity_score_7d >= 30) THEN 'watch'::text
            ELSE 'ok'::text
        END AS production_status
   FROM agg a;


grant delete on table "public"."signal_entries" to "anon";

grant insert on table "public"."signal_entries" to "anon";

grant references on table "public"."signal_entries" to "anon";

grant select on table "public"."signal_entries" to "anon";

grant trigger on table "public"."signal_entries" to "anon";

grant truncate on table "public"."signal_entries" to "anon";

grant update on table "public"."signal_entries" to "anon";

grant delete on table "public"."signal_entries" to "authenticated";

grant insert on table "public"."signal_entries" to "authenticated";

grant references on table "public"."signal_entries" to "authenticated";

grant select on table "public"."signal_entries" to "authenticated";

grant trigger on table "public"."signal_entries" to "authenticated";

grant truncate on table "public"."signal_entries" to "authenticated";

grant update on table "public"."signal_entries" to "authenticated";

grant delete on table "public"."signal_entries" to "service_role";

grant insert on table "public"."signal_entries" to "service_role";

grant references on table "public"."signal_entries" to "service_role";

grant select on table "public"."signal_entries" to "service_role";

grant trigger on table "public"."signal_entries" to "service_role";

grant truncate on table "public"."signal_entries" to "service_role";

grant update on table "public"."signal_entries" to "service_role";

grant delete on table "public"."signals" to "anon";

grant insert on table "public"."signals" to "anon";

grant references on table "public"."signals" to "anon";

grant select on table "public"."signals" to "anon";

grant trigger on table "public"."signals" to "anon";

grant truncate on table "public"."signals" to "anon";

grant update on table "public"."signals" to "anon";

grant delete on table "public"."signals" to "authenticated";

grant insert on table "public"."signals" to "authenticated";

grant references on table "public"."signals" to "authenticated";

grant select on table "public"."signals" to "authenticated";

grant trigger on table "public"."signals" to "authenticated";

grant truncate on table "public"."signals" to "authenticated";

grant update on table "public"."signals" to "authenticated";

grant delete on table "public"."signals" to "service_role";

grant insert on table "public"."signals" to "service_role";

grant references on table "public"."signals" to "service_role";

grant select on table "public"."signals" to "service_role";

grant trigger on table "public"."signals" to "service_role";

grant truncate on table "public"."signals" to "service_role";

grant update on table "public"."signals" to "service_role";


  create policy "Authenticated users can insert signal entries"
  on "public"."signal_entries"
  as permissive
  for insert
  to authenticated
with check ((auth.uid() = created_by));



  create policy "Users can delete own signal entries"
  on "public"."signal_entries"
  as permissive
  for delete
  to authenticated
using ((created_by = auth.uid()));



  create policy "Users can read own signal entries"
  on "public"."signal_entries"
  as permissive
  for select
  to authenticated
using ((created_by = auth.uid()));



  create policy "Authenticated users can insert signals"
  on "public"."signals"
  as permissive
  for insert
  to authenticated
with check ((auth.uid() = created_by));



  create policy "Users can read own signals"
  on "public"."signals"
  as permissive
  for select
  to authenticated
using ((created_by = auth.uid()));



