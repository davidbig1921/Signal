// ============================================================================
// File: src/app/decisions/[signal_id]/page.tsx
// Version: 20260116-02-decisions-drilldown-dark-contrast-fix
// Project: Mercy Signal
// Purpose:
//   Drill-down detail page for a single decision/signal.
// Notes:
//   - Best-effort fetching: never throws if view/table missing or RLS blocks.
//   - Loads decision row (prefer explain view) + evidence timeline from
//     v_signal_entries_enriched for this signal_id.
//   - If no rows accessible (common when not authenticated / RLS), shows
//     an explicit unauth banner + demo content.
//   - Dark layout compatible: all text/background/border classes use neutral-*.
// ============================================================================

import React from "react";
import Link from "next/link";
import { createSupabaseServerClient } from "@/lib/supabase/server";

type ProductionStatus = "incident" | "investigate" | "watch" | "ok";
type SeverityLabel = "High" | "Medium" | "Low" | "None";
type TrendLabel = "worsening" | "stable" | "improving";
type ConfidenceLabel = "high" | "medium" | "low";

type BaseDecisionRow = {
  signal_id: string;
  prod_issues_24h: number;
  prod_issues_7d: number;
  last_prod_issue_at: string | null;
  minutes_since_last_prod_issue: number | null;
  severity_score_7d: number;
  production_status: ProductionStatus;
  suggested_action_code: string | null;
  suggested_action_text: string | null;
};

type ExplainDecisionRow = BaseDecisionRow & {
  trend_24h_vs_7d?: TrendLabel | null;
  confidence?: ConfidenceLabel | null;
  severity_label?: SeverityLabel | null;
  status_reason_code?: string | null;
};

type DecisionRow = BaseDecisionRow | ExplainDecisionRow;

type EvidenceRow = {
  id: string;
  signal_id: string;
  body: string | null;
  source: string | null;
  created_at: string | null;
  created_by: string | null;
  kind: string | null;
  severity: string | null;
  area: string | null;
  is_production_issue: boolean | null;
  production_issue_score: number | null;
  production_issue_reason: string | null;
};

function isExplainRow(r: DecisionRow): r is ExplainDecisionRow {
  return (
    (r as ExplainDecisionRow).trend_24h_vs_7d !== undefined ||
    (r as ExplainDecisionRow).confidence !== undefined ||
    (r as ExplainDecisionRow).severity_label !== undefined ||
    (r as ExplainDecisionRow).status_reason_code !== undefined
  );
}

function safeNum(n: unknown, fallback = 0): number {
  return typeof n === "number" && Number.isFinite(n) ? n : fallback;
}

function deriveSeverityLabel(score: number): SeverityLabel {
  if (score >= 200) return "High";
  if (score >= 80) return "Medium";
  if (score > 0) return "Low";
  return "None";
}

function formatAgoMinutes(minutes: number | null): string {
  if (minutes == null || !Number.isFinite(minutes)) return "—";
  if (minutes < 60) return `${Math.floor(minutes)}m`;
  const h = Math.floor(minutes / 60);
  const m = Math.floor(minutes % 60);
  if (h < 24) return `${h}h ${m}m`;
  const d = Math.floor(h / 24);
  const hh = h % 24;
  return `${d}d ${hh}h`;
}

function pillClass(base: string) {
  return `inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium ring-1 ring-inset ${base}`;
}

function statusPill(status: ProductionStatus) {
  switch (status) {
    case "incident":
      return pillClass("bg-red-50 text-red-700 ring-red-200");
    case "investigate":
      return pillClass("bg-amber-50 text-amber-700 ring-amber-200");
    case "watch":
      return pillClass("bg-blue-50 text-blue-700 ring-blue-200");
    case "ok":
    default:
      return pillClass("bg-emerald-50 text-emerald-700 ring-emerald-200");
  }
}

function severityPill(label: SeverityLabel) {
  switch (label) {
    case "High":
      return pillClass("bg-red-50 text-red-700 ring-red-200");
    case "Medium":
      return pillClass("bg-amber-50 text-amber-700 ring-amber-200");
    case "Low":
      return pillClass("bg-blue-50 text-blue-700 ring-blue-200");
    case "None":
    default:
      return pillClass("bg-slate-50 text-slate-700 ring-slate-200");
  }
}

function trendPill(label: TrendLabel) {
  switch (label) {
    case "worsening":
      return pillClass("bg-red-50 text-red-700 ring-red-200");
    case "improving":
      return pillClass("bg-emerald-50 text-emerald-700 ring-emerald-200");
    case "stable":
    default:
      return pillClass("bg-slate-50 text-slate-700 ring-slate-200");
  }
}

function confidencePill(label: ConfidenceLabel) {
  switch (label) {
    case "high":
      return pillClass("bg-emerald-50 text-emerald-700 ring-emerald-200");
    case "medium":
      return pillClass("bg-amber-50 text-amber-700 ring-amber-200");
    case "low":
    default:
      return pillClass("bg-slate-50 text-slate-700 ring-slate-200");
  }
}

async function trySelect<T>(
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  supabase: any,
  tableOrView: string,
  select: string,
  opts?: {
    order?: { column: string; ascending?: boolean };
    limit?: number;
    eq?: { column: string; value: string | number | boolean };
  }
): Promise<{ data: T[]; ok: boolean; errorHint?: string }> {
  try {
    let q = supabase.from(tableOrView).select(select);
    if (opts?.eq) q = q.eq(opts.eq.column, opts.eq.value);
    if (opts?.order) q = q.order(opts.order.column, { ascending: opts.order.ascending ?? false });
    if (opts?.limit != null) q = q.limit(opts.limit);

    const { data, error } = await q;
    if (error || !data) return { data: [], ok: false, errorHint: error?.message ?? "query_failed" };
    return { data: data as T[], ok: true };
  } catch {
    return { data: [], ok: false, errorHint: "exception" };
  }
}

async function fetchDecisionForSignal(
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  supabase: any,
  signalId: string
): Promise<{
  row: DecisionRow | null;
  usingExplain: boolean;
  sourceName: string;
  accessHint: string;
}> {
  const explain = await trySelect<ExplainDecisionRow>(
    supabase,
    "v_production_decisions_explain",
    `
      signal_id,
      prod_issues_24h,
      prod_issues_7d,
      last_prod_issue_at,
      minutes_since_last_prod_issue,
      severity_score_7d,
      production_status,
      suggested_action_code,
      suggested_action_text,
      trend_24h_vs_7d,
      confidence,
      severity_label,
      status_reason_code
    `,
    { eq: { column: "signal_id", value: signalId }, limit: 1 }
  );

  if (explain.ok && explain.data[0]) {
    return {
      row: explain.data[0],
      usingExplain: true,
      sourceName: "v_production_decisions_explain",
      accessHint: "ok",
    };
  }

  const base = await trySelect<BaseDecisionRow>(
    supabase,
    "v_production_decisions",
    `
      signal_id,
      prod_issues_24h,
      prod_issues_7d,
      last_prod_issue_at,
      minutes_since_last_prod_issue,
      severity_score_7d,
      production_status,
      suggested_action_code,
      suggested_action_text
    `,
    { eq: { column: "signal_id", value: signalId }, limit: 1 }
  );

  const hint =
    explain.ok || base.ok ? "no_rows" : `blocked_or_missing:${explain.errorHint ?? base.errorHint ?? "unknown"}`;

  return {
    row: base.data[0] ?? null,
    usingExplain: false,
    sourceName: "v_production_decisions",
    accessHint: hint,
  };
}

async function fetchEvidence(
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  supabase: any,
  signalId: string
): Promise<{ rows: EvidenceRow[]; ok: boolean; accessHint: string }> {
  const res = await trySelect<EvidenceRow>(
    supabase,
    "v_signal_entries_enriched",
    `
      id,
      signal_id,
      body,
      source,
      created_at,
      created_by,
      kind,
      severity,
      area,
      is_production_issue,
      production_issue_score,
      production_issue_reason
    `,
    { eq: { column: "signal_id", value: signalId }, order: { column: "created_at", ascending: false }, limit: 50 }
  );

  if (res.ok) return { rows: res.data, ok: true, accessHint: "ok" };
  return { rows: [], ok: false, accessHint: res.errorHint ?? "blocked_or_missing" };
}

function demoDecision(signalId: string): ExplainDecisionRow {
  return {
    signal_id: signalId,
    prod_issues_24h: 2,
    prod_issues_7d: 9,
    last_prod_issue_at: null,
    minutes_since_last_prod_issue: 25,
    severity_score_7d: 245,
    production_status: "incident",
    suggested_action_code: "page_oncall",
    suggested_action_text: "Page on-call. Start incident response. Confirm impact and scope.",
    trend_24h_vs_7d: "worsening",
    confidence: "high",
    severity_label: "High",
    status_reason_code: "DEMO_NO_AUTH",
  };
}

function demoEvidence(signalId: string): EvidenceRow[] {
  return [
    {
      id: "demo-1",
      signal_id: signalId,
      created_at: new Date().toISOString(),
      created_by: null,
      source: "demo",
      kind: "incident",
      severity: "high",
      area: "prod",
      body: "Spike in 5xx errors after deploy; customers report checkout failures.",
      is_production_issue: true,
      production_issue_score: 90,
      production_issue_reason: "Keyword match: error/5xx + prod area",
    },
    {
      id: "demo-2",
      signal_id: signalId,
      created_at: new Date(Date.now() - 1000 * 60 * 35).toISOString(),
      created_by: null,
      source: "demo",
      kind: "observation",
      severity: "medium",
      area: "api",
      body: "Latency increased in /payments endpoint; p95 doubled vs baseline.",
      is_production_issue: true,
      production_issue_score: 55,
      production_issue_reason: "Heuristic: latency + payments + api",
    },
    {
      id: "demo-3",
      signal_id: signalId,
      created_at: new Date(Date.now() - 1000 * 60 * 90).toISOString(),
      created_by: null,
      source: "demo",
      kind: "note",
      severity: "low",
      area: "deploy",
      body: "Deploy 2026.01.15.1 rolled out to 100% at 10:02.",
      is_production_issue: false,
      production_issue_score: 0,
      production_issue_reason: "Not classified as production issue",
    },
  ];
}

function formatTs(ts: string | null) {
  if (!ts) return "—";
  const d = new Date(ts);
  if (Number.isNaN(d.getTime())) return ts;
  return d.toLocaleString();
}

function EvidenceBadge({ label }: { label: string }) {
  return <span className={pillClass("bg-neutral-800 text-neutral-200 ring-neutral-700")}>{label}</span>;
}

export default async function DecisionDetailPage({
  params,
}: {
  params: Promise<{ signal_id: string }>;
}) {
  const { signal_id } = await params;
  const supabase = await createSupabaseServerClient();

  const decision = await fetchDecisionForSignal(supabase, signal_id);
  const evidence = await fetchEvidence(supabase, signal_id);

  const showDemo = !decision.row && evidence.rows.length === 0;

  const row: DecisionRow = showDemo ? demoDecision(signal_id) : (decision.row as DecisionRow);
  const usingExplain = showDemo ? true : decision.usingExplain;
  const explain = isExplainRow(row) ? row : null;

  const score = safeNum(row.severity_score_7d);
  const severityLabel: SeverityLabel = explain?.severity_label ?? deriveSeverityLabel(score);

  const finalEvidence = showDemo ? demoEvidence(signal_id) : evidence.rows;

  const authBanner = showDemo
    ? {
        title: "Live data requires authentication",
        body:
          "You’re seeing demo content because the DB views are RLS-protected (auth.uid.). This is expected until we wire ecosystem auth later.",
        meta: `decision_hint: ${decision.accessHint} · evidence_hint: ${evidence.accessHint}`,
      }
    : null;

  return (
    <div className="mx-auto w-full max-w-6xl px-4 py-8 text-neutral-100">
      <div className="flex items-center justify-between gap-3">
        <div className="flex items-center gap-3">
          <Link
            href="/decisions"
            className="rounded-xl border border-neutral-700 bg-neutral-900 px-3 py-2 text-sm text-neutral-100 hover:bg-neutral-800"
          >
            ← Back
          </Link>

          <div>
            <h1 className="text-2xl font-semibold tracking-tight text-neutral-100">Decision Detail</h1>
            <div className="mt-1 text-xs text-neutral-400">
              signal_id: <span className="font-mono text-neutral-200">{signal_id}</span>
              {" · "}
              source: <span className="font-mono text-neutral-200">{decision.sourceName}</span>
              {" · "}
              evidence: <span className="font-mono text-neutral-200">v_signal_entries_enriched</span>
            </div>
          </div>
        </div>

        <div className="text-xs text-neutral-400">
          Evidence: <span className="font-medium text-neutral-200">{finalEvidence.length}</span>
          {showDemo ? (
            <span className="ml-2 rounded-full bg-neutral-800 px-2 py-0.5 text-[11px] text-neutral-200 ring-1 ring-neutral-700">
              demo
            </span>
          ) : null}
        </div>
      </div>

      {authBanner ? (
        <div className="mt-4 rounded-2xl border border-amber-300/30 bg-amber-200/10 p-4 text-sm text-amber-100">
          <div className="font-semibold">{authBanner.title}</div>
          <div className="mt-1 text-amber-100/90">{authBanner.body}</div>
          <div className="mt-2 text-xs text-amber-100/80">
            <span className="font-mono">{authBanner.meta}</span>
          </div>
        </div>
      ) : null}

      {/* Summary */}
      <div className="mt-6 rounded-2xl border border-neutral-800 bg-neutral-900 p-5 shadow-sm">
        <div className="flex flex-wrap items-center gap-2">
          <span className={statusPill(row.production_status)}>{row.production_status}</span>
          <span className={severityPill(severityLabel)}>{severityLabel}</span>

          {usingExplain && explain?.trend_24h_vs_7d ? (
            <span className={trendPill(explain.trend_24h_vs_7d)}>{explain.trend_24h_vs_7d}</span>
          ) : null}

          {usingExplain && explain?.confidence ? (
            <span className={confidencePill(explain.confidence)}>{explain.confidence}</span>
          ) : null}

          {usingExplain && explain?.status_reason_code ? (
            <span className="ml-2 text-xs text-neutral-400">
              reason_code: <span className="font-mono text-neutral-200">{explain.status_reason_code}</span>
            </span>
          ) : null}
        </div>

        <div className="mt-4 grid grid-cols-1 gap-3 sm:grid-cols-4">
          <div className="rounded-xl bg-neutral-800 p-3">
            <div className="text-xs text-neutral-400">Issues (24h)</div>
            <div className="mt-1 text-lg font-semibold text-neutral-100">{safeNum(row.prod_issues_24h)}</div>
          </div>

          <div className="rounded-xl bg-neutral-800 p-3">
            <div className="text-xs text-neutral-400">Issues (7d)</div>
            <div className="mt-1 text-lg font-semibold text-neutral-100">{safeNum(row.prod_issues_7d)}</div>
          </div>

          <div className="rounded-xl bg-neutral-800 p-3">
            <div className="text-xs text-neutral-400">Severity score (7d)</div>
            <div className="mt-1 text-lg font-semibold text-neutral-100">{score}</div>
          </div>

          <div className="rounded-xl bg-neutral-800 p-3">
            <div className="text-xs text-neutral-400">Last prod issue</div>
            <div className="mt-1 text-lg font-semibold text-neutral-100">
              {formatAgoMinutes(row.minutes_since_last_prod_issue)}
            </div>
          </div>
        </div>

        <div className="mt-4 rounded-xl border border-neutral-800 bg-neutral-950/30 p-3">
          <div className="text-xs text-neutral-400">Suggested action</div>
          <div className="mt-1 text-sm font-medium text-neutral-100">{row.suggested_action_text ?? "—"}</div>
          {row.suggested_action_code ? (
            <div className="mt-1 text-xs text-neutral-400">
              code: <span className="font-mono text-neutral-200">{row.suggested_action_code}</span>
            </div>
          ) : null}
        </div>
      </div>

      {/* Evidence */}
      <div className="mt-6">
        <div className="flex items-end justify-between">
          <h2 className="text-lg font-semibold text-neutral-100">Evidence timeline</h2>
          <div className="text-xs text-neutral-400">Newest first</div>
        </div>

        <div className="mt-3 space-y-3">
          {finalEvidence.length === 0 ? (
            <div className="rounded-2xl border border-neutral-800 bg-neutral-900 p-6 text-sm text-neutral-300">
              No evidence rows returned for this signal.
            </div>
          ) : (
            finalEvidence.map((e) => (
              <div key={e.id} className="rounded-2xl border border-neutral-800 bg-neutral-900 p-4 shadow-sm">
                <div className="flex flex-wrap items-center justify-between gap-2">
                  <div className="flex flex-wrap items-center gap-2">
                    {e.kind ? <EvidenceBadge label={`kind:${e.kind}`} /> : null}
                    {e.area ? <EvidenceBadge label={`area:${e.area}`} /> : null}
                    {e.severity ? <EvidenceBadge label={`sev:${e.severity}`} /> : null}
                    {e.is_production_issue ? (
                      <span className={pillClass("bg-red-50 text-red-700 ring-red-200")}>prod_issue</span>
                    ) : (
                      <span className={pillClass("bg-slate-50 text-slate-700 ring-slate-200")}>not_prod</span>
                    )}
                    {typeof e.production_issue_score === "number" ? (
                      <EvidenceBadge label={`score:${e.production_issue_score}`} />
                    ) : null}
                  </div>

                  <div className="text-xs text-neutral-400">
                    <span className="font-mono">{formatTs(e.created_at)}</span>
                  </div>
                </div>

                {e.body ? (
                  <div className="mt-3 whitespace-pre-wrap text-sm text-neutral-200">{e.body}</div>
                ) : (
                  <div className="mt-3 text-sm text-neutral-400">—</div>
                )}

                <div className="mt-3 grid grid-cols-1 gap-2 text-xs text-neutral-400 sm:grid-cols-2">
                  <div>
                    source: <span className="font-mono text-neutral-200">{e.source ?? "—"}</span>
                  </div>
                  <div>
                    reason: <span className="font-mono text-neutral-200">{e.production_issue_reason ?? "—"}</span>
                  </div>
                </div>

                <div className="mt-2 text-[11px] text-neutral-500">
                  id: <span className="font-mono">{e.id}</span>
                </div>
              </div>
            ))
          )}
        </div>
      </div>
    </div>
  );
}
