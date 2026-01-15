// ============================================================================
// File: src/app/decisions/page.tsx
// Version: 20260114-01-fixed-columns+deterministic+bulletproof (+decision version)
// Project: Mercy Signal
// Purpose:
//   Render Production Decisions with deterministic ordering and optional explainability.
// Notes:
//   - Matches DB columns for current views:
//       v_production_decisions:            suggested_action_code, suggested_action_text
//       v_production_decisions_explain:    trend_24h_vs_7d, confidence, severity_label, status_reason_code
//   - Severity label is ALWAYS available (fallback derived from score when explain view is absent).
//   - Medium threshold = 80 (user chosen).
//   - Sorting is fully deterministic (final tie-breaker on signal_id).
//   - Shows active decision version (v_active_decision_logic_version) if present.
// ============================================================================

import React from "react";
import { createSupabaseServerClient } from "@/lib/supabase/server";

type ProductionStatus = "incident" | "investigate" | "watch" | "ok";
type SeverityLabel = "High" | "Medium" | "Low" | "None";
type TrendLabel = "worsening" | "stable" | "improving";
type ConfidenceLabel = "high" | "medium" | "low";

// Views
const EXPLAIN_VIEW = "v_production_decisions_explain";
const BASE_VIEW = "v_production_decisions";
const ACTIVE_VERSION_VIEW = "v_active_decision_logic_version";

// ============================================================================
// Raw row shape from Supabase/PostgREST
// (Optional columns exist only on v_production_decisions_explain)
// ============================================================================

type ProductionDecisionRow = {
  signal_id: string;

  prod_issues_24h: number;
  prod_issues_7d: number;
  last_prod_issue_at: string | null;
  minutes_since_last_prod_issue: number | null;

  production_status: ProductionStatus;
  severity_score_7d: number;

  // Locked suggested_action contract (always present in both views)
  suggested_action_code?: string | null;
  suggested_action_text?: string | null;

  // Explainability view columns
  trend_24h_vs_7d?: string | null; // worsening | stable | improving
  confidence?: string | null; // high | medium | low
  severity_label?: string | null; // High | Medium | Low | None
  status_reason_code?: string | null; // enum/domain code

  // Legacy (kept optional so UI never crashes if old views exist)
  status_reason?: string | null;
  action_hint?: string | null;
  trend_label?: string | null;
  confidence_label?: string | null;
  confidence_score?: number | null;
};

// Active decision version view row
type ActiveDecisionVersionRow = {
  decision_version_id: string | null;
  decision_version_description: string | null;
};

// ============================================================================
// Page
// ============================================================================

export default async function DecisionsPage() {
  const supabase = createSupabaseServerClient();

  // Fetch active decision version (best-effort; do not fail page)
  const activeVersion = await fetchActiveDecisionVersion(supabase);

  const selectRequired = `
    signal_id,
    prod_issues_24h,
    prod_issues_7d,
    last_prod_issue_at,
    minutes_since_last_prod_issue,
    severity_score_7d,
    production_status,
    suggested_action_code,
    suggested_action_text
  `;

  // Explain view fields MUST match DB column names
  const selectWithExplain = `
    ${selectRequired},
    trend_24h_vs_7d,
    confidence,
    severity_label,
    status_reason_code
  `;

  // Try explain view first, fallback to base view.
  let data: any[] = [];
  let usingExplain = false;

  const r1 = await supabase.from(EXPLAIN_VIEW).select(selectWithExplain);

  if (r1.error) {
    const r2 = await supabase.from(BASE_VIEW).select(selectRequired);
    if (r2.error) {
      return (
        <main className="min-h-screen bg-slate-50">
          <div className="mx-auto max-w-4xl px-6 py-10">
            <div className="rounded-2xl border border-red-200 bg-red-50 p-6">
              <h1 className="text-xl font-semibold text-red-800">Production Decisions</h1>
              <pre className="mt-4 overflow-auto rounded-xl bg-white/60 p-4 text-xs text-red-800 ring-1 ring-red-200">
                {String(r2.error.message)}
              </pre>
            </div>
          </div>
        </main>
      );
    }
    data = r2.data ?? [];
    usingExplain = false;
  } else {
    data = r1.data ?? [];
    usingExplain = true;
  }

  const rows: NormalizedDecisionRow[] = (data as ProductionDecisionRow[]).map(normalizeDecisionRow);

  const sorted: NormalizedDecisionRow[] = [...rows].sort((a, b) => {
    const sr = statusRank(a.production_status) - statusRank(b.production_status);
    if (sr !== 0) return sr;

    if (a.prod_issues_24h !== b.prod_issues_24h) return b.prod_issues_24h - a.prod_issues_24h;
    if (a.prod_issues_7d !== b.prod_issues_7d) return b.prod_issues_7d - a.prod_issues_7d;

    const am = a.minutes_since_last_prod_issue;
    const bm = b.minutes_since_last_prod_issue;

    if (am == null && bm == null) {
      return (a.signal_id || "").localeCompare(b.signal_id || "");
    }
    if (am == null) return 1;
    if (bm == null) return -1;

    const recency = am - bm;
    if (recency !== 0) return recency;

    return (a.signal_id || "").localeCompare(b.signal_id || "");
  });

  return (
    <main className="min-h-screen bg-slate-50">
      <div className="mx-auto max-w-6xl px-6 py-10">
        <div className="flex flex-wrap items-end justify-between gap-4">
          <div>
            <h1 className="text-2xl font-semibold tracking-tight text-slate-900">
              Production Decisions
            </h1>
            <p className="mt-1 text-sm text-slate-600">
              View:{" "}
              <span className="font-mono text-slate-800">
                {usingExplain ? EXPLAIN_VIEW : BASE_VIEW}
              </span>
            </p>
          </div>

          <div className="flex items-center gap-2 text-sm text-slate-600">
            <span className="text-slate-500">Decision logic</span>
            <span className="rounded-full border border-slate-200 bg-white px-3 py-1 font-mono text-xs text-slate-800">
              {activeVersion?.decision_version_id ?? "unknown"}
            </span>
            {activeVersion?.decision_version_description ? (
              <span className="hidden max-w-[420px] truncate text-slate-500 sm:inline">
                {activeVersion.decision_version_description}
              </span>
            ) : null}
          </div>
        </div>

        <div className="mt-6 rounded-2xl border border-slate-200 bg-white shadow-sm">
          <div className="overflow-x-auto">
            <table className="min-w-full border-separate border-spacing-0">
              <thead>
                <tr className="text-left text-xs text-slate-500">
                  <Th>Status</Th>
                  <Th className="text-right">24h</Th>
                  <Th className="text-right">7d</Th>
                  <Th>Last issue</Th>
                  <Th>Recency</Th>
                  <Th className="text-right">Severity</Th>
                  <Th>Suggested</Th>
                  <Th>Signal</Th>
                </tr>
              </thead>

              <tbody>
                {sorted.map((r, idx) => (
                  <tr
                    key={r.signal_id || `row-${idx}`}
                    className="border-t border-slate-100 hover:bg-slate-50/60"
                  >
                    <Td>
                      <div className="flex flex-wrap items-center gap-2">
                        <span
                          className={[
                            "inline-flex w-fit items-center rounded-full px-2.5 py-1 text-xs font-medium ring-1 ring-inset",
                            pillClasses(r.production_status),
                          ].join(" ")}
                        >
                          {r.production_status}
                        </span>

                        <span
                          className={[
                            "inline-flex w-fit items-center rounded-full px-2.5 py-1 text-xs font-medium ring-1 ring-inset",
                            severityPillClasses(r.severity_label),
                          ].join(" ")}
                          title={`Severity score (7d): ${r.severity_score_7d}`}
                        >
                          {r.severity_label}
                        </span>

                        {usingExplain ? (
                          <>
                            <span
                              className={[
                                "inline-flex w-fit items-center rounded-full px-2.5 py-1 text-xs font-medium ring-1 ring-inset",
                                trendPillClasses(r.trend_label),
                              ].join(" ")}
                              title="Trend: 24h compared to 7d daily baseline"
                            >
                              {labelTrend(r.trend_label)}
                            </span>

                            <span
                              className={[
                                "inline-flex w-fit items-center rounded-full px-2.5 py-1 text-xs font-medium ring-1 ring-inset",
                                confidencePillClasses(r.confidence_label),
                              ].join(" ")}
                              title="Confidence"
                            >
                              {labelConfidence(r.confidence_label)}
                            </span>
                          </>
                        ) : null}
                      </div>

                      {usingExplain ? (
                        <div className="mt-2 space-y-1 text-xs text-slate-600">
                          <div>
                            <span className="font-medium text-slate-700">Reason:</span>{" "}
                            {r.status_reason_code ?? "—"}
                          </div>
                        </div>
                      ) : null}
                    </Td>

                    <Td className="text-right tabular-nums">{r.prod_issues_24h}</Td>
                    <Td className="text-right tabular-nums">{r.prod_issues_7d}</Td>
                    <Td className="whitespace-nowrap">{fmtDateTime(r.last_prod_issue_at)}</Td>
                    <Td className="whitespace-nowrap">
                      {fmtRecency(r.minutes_since_last_prod_issue)}
                    </Td>

                    <Td className="text-right tabular-nums">
                      <span className="font-medium">{r.severity_score_7d}</span>
                      <span className="ml-1 text-xs text-slate-500">({r.severity_label})</span>
                    </Td>

                    <Td>
                      <div className="space-y-1">
                        <div className="flex flex-wrap items-center gap-2">
                          <span className="rounded-full bg-slate-50 px-2.5 py-1 text-xs font-mono text-slate-700 ring-1 ring-slate-200">
                            {r.suggested_action_code ?? "—"}
                          </span>
                        </div>
                        <div className="text-xs text-slate-600">{r.suggested_action_text ?? "—"}</div>
                      </div>
                    </Td>

                    <Td>
                      <span className="font-mono text-xs text-slate-700">{shortId(r.signal_id)}</span>
                    </Td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          {usingExplain ? (
            <div className="border-t border-slate-200 px-5 py-3 text-xs text-slate-500">
              <span className="font-medium text-slate-700">Trend:</span> 24h vs 7d baseline (↑ worse,
              ↓ better, → flat).{" "}
              <span className="ml-2 font-medium text-slate-700">Confidence:</span> based on 7d volume +
              incident weighting.
            </div>
          ) : null}
        </div>
      </div>
    </main>
  );
}

// ============================================================================
// DB helpers (best-effort; never fail page)
// ============================================================================

async function fetchActiveDecisionVersion(
  supabase: ReturnType<typeof createSupabaseServerClient>
): Promise<ActiveDecisionVersionRow | null> {
  try {
    const r = await supabase
      .from(ACTIVE_VERSION_VIEW)
      .select("decision_version_id, decision_version_description")
      .maybeSingle();

    if (r.error) return null;
    if (!r.data) return null;

    return {
      decision_version_id:
        typeof r.data.decision_version_id === "string" && r.data.decision_version_id.trim()
          ? r.data.decision_version_id.trim()
          : null,
      decision_version_description:
        typeof r.data.decision_version_description === "string" &&
        r.data.decision_version_description.trim()
          ? r.data.decision_version_description.trim()
          : null,
    };
  } catch {
    return null;
  }
}

// ============================================================================
// Helpers
// ============================================================================

function statusRank(status: ProductionStatus): number {
  switch (status) {
    case "incident":
      return 1;
    case "investigate":
      return 2;
    case "watch":
      return 3;
    case "ok":
      return 4;
    default:
      return 999;
  }
}

function pillClasses(status: ProductionStatus): string {
  switch (status) {
    case "incident":
      return "bg-red-50 text-red-700 ring-red-200";
    case "investigate":
      return "bg-amber-50 text-amber-700 ring-amber-200";
    case "watch":
      return "bg-blue-50 text-blue-700 ring-blue-200";
    case "ok":
      return "bg-emerald-50 text-emerald-700 ring-emerald-200";
    default:
      return "bg-slate-50 text-slate-700 ring-slate-200";
  }
}

function severityPillClasses(label: SeverityLabel): string {
  switch (label) {
    case "High":
      return "bg-red-50 text-red-700 ring-red-200";
    case "Medium":
      return "bg-amber-50 text-amber-700 ring-amber-200";
    case "Low":
      return "bg-yellow-50 text-yellow-800 ring-yellow-200";
    default:
      return "bg-slate-50 text-slate-700 ring-slate-200";
  }
}

function trendPillClasses(trend: TrendLabel | null): string {
  switch (trend) {
    case "worsening":
      return "bg-red-50 text-red-700 ring-red-200";
    case "improving":
      return "bg-emerald-50 text-emerald-700 ring-emerald-200";
    case "stable":
      return "bg-slate-50 text-slate-700 ring-slate-200";
    default:
      return "bg-slate-50 text-slate-700 ring-slate-200";
  }
}

function confidencePillClasses(conf: ConfidenceLabel | null): string {
  switch (conf) {
    case "high":
      return "bg-emerald-50 text-emerald-700 ring-emerald-200";
    case "medium":
      return "bg-amber-50 text-amber-700 ring-amber-200";
    case "low":
      return "bg-slate-50 text-slate-700 ring-slate-200";
    default:
      return "bg-slate-50 text-slate-700 ring-slate-200";
  }
}

function labelTrend(trend: TrendLabel | null): string {
  if (trend === "worsening") return "↑ Trend";
  if (trend === "improving") return "↓ Trend";
  if (trend === "stable") return "→ Trend";
  return "Trend";
}

function labelConfidence(conf: ConfidenceLabel | null): string {
  if (conf === "high") return "High conf";
  if (conf === "medium") return "Med conf";
  if (conf === "low") return "Low conf";
  return "Conf";
}

function fmtDateTime(iso: string | null): string {
  if (!iso) return "—";
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return "—";
  return new Intl.DateTimeFormat(undefined, {
    year: "numeric",
    month: "short",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
  }).format(d);
}

function fmtRecency(minutes: number | null): string {
  if (minutes == null || !Number.isFinite(minutes)) return "—";
  const m = Math.max(0, Math.floor(minutes));
  if (m < 60) return `${m}m ago`;
  const h = Math.floor(m / 60);
  if (h < 24) return `${h}h ago`;
  const d = Math.floor(h / 24);
  return `${d}d ago`;
}

function shortId(id: string): string {
  if (!id) return "—";
  if (id.length <= 16) return id;
  return `${id.slice(0, 8)}…${id.slice(-6)}`;
}

function tinyHash(input: string): string {
  let h = 2166136261;
  for (let i = 0; i < input.length; i++) {
    h ^= input.charCodeAt(i);
    h = Math.imul(h, 16777619);
  }
  return (h >>> 0).toString(16);
}

// ============================================================================
// Normalization
// ============================================================================

type NormalizedDecisionRow = {
  signal_id: string;
  prod_issues_24h: number;
  prod_issues_7d: number;
  last_prod_issue_at: string | null;
  minutes_since_last_prod_issue: number | null;

  production_status: ProductionStatus;
  severity_score_7d: number;

  suggested_action_code: string | null;
  suggested_action_text: string | null;

  status_reason_code: string | null;

  severity_label: SeverityLabel;

  trend_label: TrendLabel | null;
  confidence_label: ConfidenceLabel | null;
};

function toNumberOrNull(v: unknown): number | null {
  if (typeof v === "number" && Number.isFinite(v)) return v;
  if (typeof v === "string") {
    const t = v.trim();
    if (!t) return null;
    const n = Number(t);
    return Number.isFinite(n) ? n : null;
  }
  return null;
}

function toIntOrZero(v: unknown): number {
  const n = toNumberOrNull(v);
  return n == null ? 0 : Math.trunc(n);
}

function toStringOrNull(v: unknown): string | null {
  if (typeof v !== "string") return null;
  const t = v.trim();
  return t.length ? t : null;
}

function asSeverityLabel(v: unknown): SeverityLabel {
  return v === "High" || v === "Medium" || v === "Low" || v === "None" ? v : "None";
}

function deriveSeverityLabelFromScore(score: number): SeverityLabel {
  if (score >= 200) return "High";
  if (score >= 80) return "Medium";
  if (score >= 1) return "Low";
  return "None";
}

function asProductionStatus(v: unknown): ProductionStatus {
  return v === "incident" || v === "investigate" || v === "watch" || v === "ok" ? v : "ok";
}

function asTrend(v: unknown): TrendLabel | null {
  return v === "worsening" || v === "stable" || v === "improving" ? v : null;
}

function asConfidence(v: unknown): ConfidenceLabel | null {
  return v === "high" || v === "medium" || v === "low" ? v : null;
}

function normalizeDecisionRow(row: any): NormalizedDecisionRow {
  const rawId =
    typeof row?.signal_id === "string" && row.signal_id.trim() ? row.signal_id.trim() : "";

  const signal_id = rawId || `missing:${tinyHash(JSON.stringify(row ?? {}))}`;

  const severity_score_7d = toIntOrZero(row?.severity_score_7d);

  // Prefer explain's severity_label; fallback derived from score
  const rawLabel = asSeverityLabel(row?.severity_label);
  const severity_label =
    rawLabel !== "None" ? rawLabel : deriveSeverityLabelFromScore(severity_score_7d);

  // Prefer explain columns; allow legacy fields if user is on older view
  const trendRaw =
    row?.trend_24h_vs_7d != null ? row.trend_24h_vs_7d : row?.trend_label != null ? row.trend_label : null;

  const confRaw =
    row?.confidence != null ? row.confidence : row?.confidence_label != null ? row.confidence_label : null;

  return {
    signal_id,
    prod_issues_24h: toIntOrZero(row?.prod_issues_24h),
    prod_issues_7d: toIntOrZero(row?.prod_issues_7d),
    last_prod_issue_at:
      typeof row?.last_prod_issue_at === "string" && row.last_prod_issue_at.trim()
        ? row.last_prod_issue_at.trim()
        : null,
    minutes_since_last_prod_issue: toNumberOrNull(row?.minutes_since_last_prod_issue),

    production_status: asProductionStatus(row?.production_status),
    severity_score_7d,

    suggested_action_code: toStringOrNull(row?.suggested_action_code),
    suggested_action_text: toStringOrNull(row?.suggested_action_text),

    status_reason_code: toStringOrNull(row?.status_reason_code) ?? toStringOrNull(row?.status_reason),

    severity_label,

    trend_label: asTrend(trendRaw),
    confidence_label: asConfidence(confRaw),
  };
}

function Th({ children, className = "" }: { children: React.ReactNode; className?: string }) {
  return (
    <th
      className={[
        "sticky top-0 z-10 border-b border-slate-200 bg-white/90 px-5 py-3 font-medium backdrop-blur",
        className,
      ].join(" ")}
    >
      {children}
    </th>
  );
}

function Td({ children, className = "" }: { children: React.ReactNode; className?: string }) {
  return <td className={["px-5 py-4 text-sm text-slate-800", className].join(" ")}>{children}</td>;
}
