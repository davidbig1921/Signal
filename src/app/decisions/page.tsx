// ============================================================================
// File: src/app/decisions/page.tsx
// Version: 20260115-09-decisions-page-client-link-wrapper-alive-feedback (fixed)
// Project: Mercy Signal
// Purpose:
//   Render Production Decisions with deterministic ordering + show decision versions.
// Notes:
//   - Server Component
//   - Tooltips use a client-only component via a wrapper (portal; no clipping)
//   - If no rows accessible (RLS / unauth), show demo card + explicit banner
//   - Cards are clickable to /decisions/[signal_id] with instant click feedback
// ============================================================================

import React from "react";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import TooltipId from "./TooltipId"; // ✅ wrapper (server-safe)
import DecisionCardLink from "./DecisionCardLink.client"; // ✅ alive click feedback

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

function isExplainRow(r: DecisionRow): r is ExplainDecisionRow {
  return (
    (r as ExplainDecisionRow).trend_24h_vs_7d !== undefined ||
    (r as ExplainDecisionRow).confidence !== undefined ||
    (r as ExplainDecisionRow).severity_label !== undefined ||
    (r as ExplainDecisionRow).status_reason_code !== undefined
  );
}

function statusRank(status: ProductionStatus): number {
  switch (status) {
    case "incident":
      return 4;
    case "investigate":
      return 3;
    case "watch":
      return 2;
    case "ok":
    default:
      return 1;
  }
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

function syncedPill(isSynced: boolean | null) {
  if (isSynced == null) return pillClass("bg-slate-50 text-slate-600 ring-slate-200");
  return isSynced
    ? pillClass("bg-emerald-50 text-emerald-700 ring-emerald-200")
    : pillClass("bg-amber-50 text-amber-700 ring-amber-200");
}

async function trySelect<T>(
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  supabase: any,
  tableOrView: string,
  select: string,
  opts?: {
    order?: { column: string; ascending?: boolean; nullsFirst?: boolean };
    limit?: number;
    eq?: { column: string; value: string | number | boolean };
  }
): Promise<{ data: T[]; ok: boolean; errorHint?: string }> {
  try {
    let q = supabase.from(tableOrView).select(select);

    if (opts?.eq) q = q.eq(opts.eq.column, opts.eq.value);
    if (opts?.order) {
      q = q.order(opts.order.column, {
        ascending: opts.order.ascending ?? false,
        nullsFirst: opts.order.nullsFirst,
      });
    }
    if (opts?.limit != null) q = q.limit(opts.limit);

    const { data, error } = await q;
    if (error || !data) return { data: [], ok: false, errorHint: error?.message ?? "query_failed" };
    return { data: data as T[], ok: true };
  } catch {
    return { data: [], ok: false, errorHint: "exception" };
  }
}

async function fetchDecisionRows(
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  supabase: any
): Promise<{ rows: DecisionRow[]; usingExplain: boolean; sourceName: string; accessHint: string }> {
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
    `
  );

  if (explain.ok && explain.data.length > 0) {
    return { rows: explain.data, usingExplain: true, sourceName: "v_production_decisions_explain", accessHint: "ok" };
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
    `
  );

  const hint =
    explain.ok || base.ok ? "no_rows" : `blocked_or_missing:${explain.errorHint ?? base.errorHint ?? "unknown"}`;

  return { rows: base.data, usingExplain: false, sourceName: "v_production_decisions", accessHint: hint };
}

async function fetchActiveLogicVersion(
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  supabase: any
): Promise<{ id: string | null; description: string | null; source: string }> {
  const v1 = await trySelect<{ logic_version_id: string; description?: string | null }>(
    supabase,
    "v_ms_active_logic_version",
    "logic_version_id, description",
    { limit: 1 }
  );
  if (v1.ok && v1.data[0]?.logic_version_id) {
    return {
      id: v1.data[0].logic_version_id ?? null,
      description: (v1.data[0] as any).description ?? null,
      source: "v_ms_active_logic_version",
    };
  }

  const v2 = await trySelect<{ decision_version_id: string; decision_version_description?: string | null }>(
    supabase,
    "v_active_decision_logic_version",
    "decision_version_id, decision_version_description",
    { limit: 1 }
  );
  if (v2.ok && v2.data[0]?.decision_version_id) {
    return {
      id: v2.data[0].decision_version_id ?? null,
      description: (v2.data[0] as any).decision_version_description ?? null,
      source: "v_active_decision_logic_version",
    };
  }

  const t = await trySelect<{ id: string; description?: string | null }>(
    supabase,
    "ms_decision_logic_version",
    "id, description",
    { eq: { column: "is_active", value: true }, limit: 1 }
  );
  if (t.ok && t.data[0]?.id) {
    return {
      id: t.data[0].id ?? null,
      description: (t.data[0] as any).description ?? null,
      source: "ms_decision_logic_version",
    };
  }

  return { id: null, description: null, source: "unknown" };
}

async function fetchLatestSnapshotLogicVersion(
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  supabase: any
): Promise<{ logicVersionId: string | null; snapshotAt: string | null; source: string }> {
  const a = await trySelect<{ logic_version_id: string; created_at?: string | null }>(
    supabase,
    "ms_deploy_snapshot",
    "logic_version_id, created_at",
    { order: { column: "created_at", ascending: false }, limit: 1 }
  );
  if (a.ok && a.data[0]?.logic_version_id) {
    return {
      logicVersionId: a.data[0].logic_version_id ?? null,
      snapshotAt: (a.data[0] as any).created_at ?? null,
      source: "ms_deploy_snapshot.created_at",
    };
  }

  const b = await trySelect<{ logic_version_id: string; inserted_at?: string | null }>(
    supabase,
    "ms_deploy_snapshot",
    "logic_version_id, inserted_at",
    { order: { column: "inserted_at", ascending: false }, limit: 1 }
  );
  if (b.ok && b.data[0]?.logic_version_id) {
    return {
      logicVersionId: b.data[0].logic_version_id ?? null,
      snapshotAt: (b.data[0] as any).inserted_at ?? null,
      source: "ms_deploy_snapshot.inserted_at",
    };
  }

  const c = await trySelect<{ logic_version_id: string }>(
    supabase,
    "ms_deploy_snapshot",
    "logic_version_id",
    { limit: 1 }
  );
  if (c.ok && c.data[0]?.logic_version_id) {
    return { logicVersionId: c.data[0].logic_version_id ?? null, snapshotAt: null, source: "ms_deploy_snapshot" };
  }

  return { logicVersionId: null, snapshotAt: null, source: "unknown" };
}

function sortRows(rows: DecisionRow[]): DecisionRow[] {
  return [...rows].sort((a, b) => {
    const sr = statusRank(b.production_status) - statusRank(a.production_status);
    if (sr !== 0) return sr;

    const sev = safeNum(b.severity_score_7d) - safeNum(a.severity_score_7d);
    if (sev !== 0) return sev;

    const i24 = safeNum(b.prod_issues_24h) - safeNum(a.prod_issues_24h);
    if (i24 !== 0) return i24;

    const i7 = safeNum(b.prod_issues_7d) - safeNum(a.prod_issues_7d);
    if (i7 !== 0) return i7;

    const ra = a.minutes_since_last_prod_issue ?? Number.POSITIVE_INFINITY;
    const rb = b.minutes_since_last_prod_issue ?? Number.POSITIVE_INFINITY;
    if (ra !== rb) return ra - rb;

    return a.signal_id.localeCompare(b.signal_id);
  });
}

// ----------------------------------------------------------------------------
// Demo mode
// ----------------------------------------------------------------------------
function demoRow(): ExplainDecisionRow {
  return {
    signal_id: "demo-signal-00000000-0000-0000-0000-000000000000",
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
    status_reason_code: "DEMO_ROW_NO_AUTH",
  };
}

function ProductionDecisionCard({ row, usingExplain }: { row: DecisionRow; usingExplain: boolean }) {
  const score = safeNum(row.severity_score_7d);
  const explain = isExplainRow(row) ? row : null;
  const severityLabel: SeverityLabel = explain?.severity_label ?? deriveSeverityLabel(score);

  return (
    <div className="rounded-2xl border border-neutral-800 bg-neutral-900 p-4 shadow-sm">
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <div className="flex flex-wrap items-center gap-2">
            <span className={statusPill(row.production_status)}>{row.production_status}</span>
            <span className={severityPill(severityLabel)}>{severityLabel}</span>

            {usingExplain && explain?.trend_24h_vs_7d ? (
              <span className={trendPill(explain.trend_24h_vs_7d)}>{explain.trend_24h_vs_7d}</span>
            ) : null}

            {usingExplain && explain?.confidence ? (
              <span className={confidencePill(explain.confidence)}>{explain.confidence}</span>
            ) : null}
          </div>

          <div className="mt-2 text-sm text-neutral-300">
            <span className="font-mono text-neutral-200">{row.signal_id}</span>
          </div>
        </div>

        <div className="text-right text-sm text-neutral-300">
          <div>
            <span className="font-medium text-neutral-100">{safeNum(row.prod_issues_24h)}</span> /24h
          </div>
          <div>
            <span className="font-medium text-neutral-100">{safeNum(row.prod_issues_7d)}</span> /7d
          </div>
        </div>
      </div>

      <div className="mt-3 grid grid-cols-2 gap-3 text-sm">
        <div className="rounded-xl bg-neutral-800 p-3">
          <div className="text-neutral-400">Severity score (7d)</div>
          <div className="mt-1 text-lg font-semibold text-neutral-100">{score}</div>
        </div>
        <div className="rounded-xl bg-neutral-800 p-3">
          <div className="text-neutral-400">Last prod issue</div>
          <div className="mt-1 font-semibold text-neutral-100">{formatAgoMinutes(row.minutes_since_last_prod_issue)}</div>
        </div>
      </div>

      <div className="mt-3 rounded-xl border border-neutral-800 bg-neutral-950/30 p-3">
        <div className="text-xs text-neutral-400">Suggested action</div>
        <div className="mt-1 text-sm font-medium text-neutral-100">{row.suggested_action_text ?? "—"}</div>
        {row.suggested_action_code ? (
          <div className="mt-1 text-xs text-neutral-400">
            code: <span className="font-mono text-neutral-200">{row.suggested_action_code}</span>
          </div>
        ) : null}
      </div>

      {usingExplain && explain?.status_reason_code ? (
        <div className="mt-3 text-xs text-neutral-400">
          reason: <span className="font-mono text-neutral-200">{explain.status_reason_code}</span>
        </div>
      ) : null}
    </div>
  );
}

export default async function DecisionsPage() {
  const supabase = await createSupabaseServerClient();

  const { rows: rawRows, usingExplain, sourceName, accessHint } = await fetchDecisionRows(supabase);
  const rows = sortRows(rawRows);

  const active = await fetchActiveLogicVersion(supabase);
  const snap = await fetchLatestSnapshotLogicVersion(supabase);
  const isSynced = active.id && snap.logicVersionId ? active.id === snap.logicVersionId : null;

  const showDemo = rows.length === 0;
  const finalRows = showDemo ? [demoRow()] : rows;

  const authBanner = showDemo
    ? {
        title: "Live data requires authentication",
        body:
          "You’re seeing a demo card because the DB views are RLS-protected (auth.uid()). This is expected until we wire the ecosystem auth later.",
        meta: `hint: ${accessHint}`,
      }
    : null;

  return (
    <div className="mx-auto w-full max-w-6xl px-4 py-8 text-neutral-100">
      <div className="flex flex-col gap-2 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight text-neutral-100">Production Decisions</h1>

          <div className="mt-2 flex flex-wrap items-center gap-2 text-sm text-neutral-300">
            <span className="text-neutral-400">Decision logic:</span>

            <span className="inline-flex items-center" title={active.description ?? undefined}>
              <TooltipId label="Active" id={active.id} />
            </span>

            <span className="text-neutral-500">·</span>

            <span className="inline-flex items-center gap-2">
              <TooltipId label="Snapshot" id={snap.logicVersionId} />
              {snap.snapshotAt ? (
                <span className="text-xs text-neutral-400" title={snap.snapshotAt}>
                  ({snap.snapshotAt})
                </span>
              ) : null}
            </span>

            <span className={syncedPill(isSynced)}>{isSynced == null ? "unknown" : isSynced ? "synced" : "drift"}</span>
          </div>

          <div className="mt-1 text-xs text-neutral-400">
            Active source: <span className="font-mono text-neutral-200">{active.source}</span> · Snapshot source:{" "}
            <span className="font-mono text-neutral-200">{snap.source}</span>
          </div>

          <div className="mt-1 text-xs text-neutral-400">
            Data source: <span className="font-mono text-neutral-200">{sourceName}</span>
          </div>
        </div>

        <div className="text-xs text-neutral-400">
          Rows: <span className="font-medium text-neutral-200">{finalRows.length}</span>
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

      <div className="mt-6 grid grid-cols-1 gap-4 lg:grid-cols-2">
        {finalRows.map((r) => (
          <DecisionCardLink key={r.signal_id} href={`/decisions/${r.signal_id}`}>
            <ProductionDecisionCard row={r} usingExplain={usingExplain || showDemo} />
          </DecisionCardLink>
        ))}
      </div>
    </div>
  );
}
