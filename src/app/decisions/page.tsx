// ============================================================================
// File: src/app/decisions/page.tsx
// Version: 20260115-02-decision-version-header+safe-fetch
// Project: Mercy Signal
// Purpose:
//   Render Production Decisions with deterministic ordering + show decision version.
// Notes:
//   - Best-effort data fetching: never throws if a view/table is missing.
//   - Tries v_production_decisions_explain first, falls back to v_production_decisions.
//   - Shows decision versions in header:
//       Active logic version: v_ms_active_logic_version (preferred) OR ms_decision_logic_version where is_active=true
//       Latest snapshot: ms_deploy_snapshot.logic_version_id (latest by created_at/inserted_at if present)
//   - DB contract:
//       v_production_decisions:
//         signal_id, prod_issues_24h, prod_issues_7d, last_prod_issue_at,
//         minutes_since_last_prod_issue, severity_score_7d, production_status,
//         suggested_action_code, suggested_action_text
//       v_production_decisions_explain adds:
//         trend_24h_vs_7d, confidence, severity_label, status_reason_code
// ============================================================================

import React from "react";
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
  trend_24h_vs_7d: TrendLabel | null;
  confidence: ConfidenceLabel | null;
  severity_label: SeverityLabel | null;
  status_reason_code: string | null;
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
  // Higher = more urgent
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
  // Fallback-only heuristic (UI must always have a label even if explain view absent)
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
    order?: { column: string; ascending?: boolean; nullsFirst?: boolean };
    limit?: number;
    eq?: { column: string; value: string | number | boolean };
  }
): Promise<{ data: T[]; ok: boolean }> {
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
    if (error || !data) return { data: [], ok: false };
    return { data: data as T[], ok: true };
  } catch {
    return { data: [], ok: false };
  }
}

async function fetchDecisionRows(
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  supabase: any
): Promise<{ rows: DecisionRow[]; usingExplain: boolean }> {
  // Try explain view first
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
    return { rows: explain.data, usingExplain: true };
  }

  // Fallback to base view
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

  return { rows: base.data, usingExplain: false };
}

async function fetchActiveLogicVersion(
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  supabase: any
): Promise<string | null> {
  // Preferred: v_ms_active_logic_version
  const view = await trySelect<{ logic_version_id: string }>(
    supabase,
    "v_ms_active_logic_version",
    "logic_version_id",
    { limit: 1 }
  );
  if (view.ok && view.data[0]?.logic_version_id) return view.data[0].logic_version_id;

  // Fallback: ms_decision_logic_version where is_active=true
  const tbl = await trySelect<{ id: string }>(
    supabase,
    "ms_decision_logic_version",
    "id",
    { eq: { column: "is_active", value: true }, limit: 1 }
  );
  if (tbl.ok && tbl.data[0]?.id) return tbl.data[0].id;

  return null;
}

async function fetchLatestSnapshotLogicVersion(
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  supabase: any
): Promise<{ logicVersionId: string | null; snapshotAt: string | null }> {
  // We don’t know which timestamp column exists, so we try best-effort:
  // 1) order by created_at
  // 2) order by inserted_at
  // 3) no order (limit 1)
  const first = await trySelect<{ logic_version_id: string; created_at?: string | null }>(
    supabase,
    "ms_deploy_snapshot",
    "logic_version_id, created_at",
    { order: { column: "created_at", ascending: false }, limit: 1 }
  );
  if (first.ok && first.data[0]?.logic_version_id) {
    return {
      logicVersionId: first.data[0].logic_version_id ?? null,
      snapshotAt: (first.data[0] as any).created_at ?? null,
    };
  }

  const second = await trySelect<{ logic_version_id: string; inserted_at?: string | null }>(
    supabase,
    "ms_deploy_snapshot",
    "logic_version_id, inserted_at",
    { order: { column: "inserted_at", ascending: false }, limit: 1 }
  );
  if (second.ok && second.data[0]?.logic_version_id) {
    return {
      logicVersionId: second.data[0].logic_version_id ?? null,
      snapshotAt: (second.data[0] as any).inserted_at ?? null,
    };
  }

  const third = await trySelect<{ logic_version_id: string }>(
    supabase,
    "ms_deploy_snapshot",
    "logic_version_id",
    { limit: 1 }
  );
  if (third.ok && third.data[0]?.logic_version_id) {
    return { logicVersionId: third.data[0].logic_version_id ?? null, snapshotAt: null };
  }

  return { logicVersionId: null, snapshotAt: null };
}

function sortRows(rows: DecisionRow[]): DecisionRow[] {
  // Deterministic: status desc, severity desc, 24h desc, 7d desc, recency asc, signal_id asc
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

function shortId(id: string | null): string {
  if (!id) return "unknown";
  // Keep readable but stable
  return id.length > 12 ? `${id.slice(0, 8)}…${id.slice(-4)}` : id;
}

function ProductionDecisionCard({ row, usingExplain }: { row: DecisionRow; usingExplain: boolean }) {
  const score = safeNum(row.severity_score_7d);
  const explain = isExplainRow(row) ? row : null;
  const severityLabel: SeverityLabel =
    explain?.severity_label ?? deriveSeverityLabel(score);

  return (
    <div className="rounded-2xl border border-slate-200 bg-white p-4 shadow-sm">
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

          <div className="mt-2 text-sm text-slate-600">
            <span className="font-mono text-slate-800">{row.signal_id}</span>
          </div>
        </div>

        <div className="text-right text-sm text-slate-600">
          <div>
            <span className="font-medium text-slate-800">{safeNum(row.prod_issues_24h)}</span> /24h
          </div>
          <div>
            <span className="font-medium text-slate-800">{safeNum(row.prod_issues_7d)}</span> /7d
          </div>
        </div>
      </div>

      <div className="mt-3 grid grid-cols-2 gap-3 text-sm">
        <div className="rounded-xl bg-slate-50 p-3">
          <div className="text-slate-500">Severity score (7d)</div>
          <div className="mt-1 text-lg font-semibold text-slate-900">{score}</div>
        </div>
        <div className="rounded-xl bg-slate-50 p-3">
          <div className="text-slate-500">Last prod issue</div>
          <div className="mt-1 font-semibold text-slate-900">
            {formatAgoMinutes(row.minutes_since_last_prod_issue)}
          </div>
        </div>
      </div>

      <div className="mt-3 rounded-xl border border-slate-200 bg-white p-3">
        <div className="text-xs text-slate-500">Suggested action</div>
        <div className="mt-1 text-sm font-medium text-slate-900">
          {row.suggested_action_text ?? "—"}
        </div>
        {row.suggested_action_code ? (
          <div className="mt-1 text-xs text-slate-500">
            code: <span className="font-mono">{row.suggested_action_code}</span>
          </div>
        ) : null}
      </div>

      {usingExplain && explain?.status_reason_code ? (
        <div className="mt-3 text-xs text-slate-500">
          reason: <span className="font-mono">{explain.status_reason_code}</span>
        </div>
      ) : null}
    </div>
  );
}

export default async function DecisionsPage() {
  const supabase = await createSupabaseServerClient();

  // Fetch decisions (best-effort)
  const { rows: rawRows, usingExplain } = await fetchDecisionRows(supabase);
  const rows = sortRows(rawRows);

  // Fetch decision version info (best-effort)
  const activeLogicVersionId = await fetchActiveLogicVersion(supabase);
  const latestSnapshot = await fetchLatestSnapshotLogicVersion(supabase);

  return (
    <div className="mx-auto w-full max-w-6xl px-4 py-8">
      <div className="flex flex-col gap-2 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight text-slate-900">
            Production Decisions
          </h1>

          <div className="mt-1 text-sm text-slate-600">
            Decision logic:{" "}
            <span className="font-medium text-slate-900">
              Active {shortId(activeLogicVersionId)}
            </span>
            {" · "}
            <span className="font-medium text-slate-900">
              Snapshot {shortId(latestSnapshot.logicVersionId)}
            </span>
            {latestSnapshot.snapshotAt ? (
              <span className="text-slate-500"> (at {latestSnapshot.snapshotAt})</span>
            ) : null}
          </div>

          <div className="mt-1 text-xs text-slate-500">
            Data source: {usingExplain ? "v_production_decisions_explain" : "v_production_decisions"}{" "}
            (best-effort fallback)
          </div>
        </div>

        <div className="text-xs text-slate-500">
          Rows: <span className="font-medium text-slate-700">{rows.length}</span>
        </div>
      </div>

      <div className="mt-6 grid grid-cols-1 gap-4 lg:grid-cols-2">
        {rows.length === 0 ? (
          <div className="rounded-2xl border border-slate-200 bg-white p-6 text-sm text-slate-600">
            No decision rows returned. (If this is unexpected, verify RLS/auth cookies and that the views
            exist in the current schema.)
          </div>
        ) : (
          rows.map((r) => (
            <ProductionDecisionCard key={r.signal_id} row={r} usingExplain={usingExplain} />
          ))
        )}
      </div>
    </div>
  );
}
