// ============================================================================
// File: src/app/decisions/page.tsx
// Version: 20260112-12
// Project: Mercy Signal
// Purpose:
//   Render Production Decisions with deterministic ordering and optional explainability.
// Notes:
//   - Severity label is ALWAYS available (fallback derived from score when explain view is absent).
//   - Trend/Confidence pills only render when usingExplain=true (because base view won’t have them).
// ============================================================================

import React from "react";
import { createSupabaseServerClient } from "@/lib/supabase/server";

type ProductionStatus = "incident" | "investigate" | "watch" | "ok";
type SeverityLabel = "High" | "Medium" | "Low" | "None";
type TrendLabel = "worsening" | "stable" | "improving";
type ConfidenceLabel = "high" | "medium" | "low";

// ============================================================================
// File: src/app/decisions/page.tsx
// Block: ProductionDecisionRow
// Version: 20260112-10
// Purpose:
//   Raw row shape from Supabase/PostgREST.
// Notes:
//   - Optional columns exist only on v_production_decisions_explain.
// ============================================================================

type ProductionDecisionRow = {
  signal_id: string;

  prod_issues_24h: number;
  prod_issues_7d: number;
  last_prod_issue_at: string | null;
  minutes_since_last_prod_issue: number | null;

  production_status: ProductionStatus;
  severity_score_7d: number;

  status_reason?: string | null;
  action_hint?: string | null;

  severity_level?: number | null;
  severity_label?: string | null;

  // Optional (only exists if the explain view includes them)
  trend_24h_vs_7d?: string | null; // worsening | stable | improving
  confidence?: string | null; // high | medium | low
};

// ============================================================================
// File: src/app/decisions/page.tsx
// Block: DecisionsPage
// Version: 20260112-12
// Purpose:
//   Server Component page export (MUST be default export).
// ============================================================================

export default async function DecisionsPage() {
  const supabase = createSupabaseServerClient();

  const selectRequired = `
    signal_id,
    prod_issues_24h,
    prod_issues_7d,
    last_prod_issue_at,
    minutes_since_last_prod_issue,
    severity_score_7d,
    production_status
  `;

  const selectWithExplain = `
    ${selectRequired},
    status_reason,
    action_hint,
    severity_level,
    severity_label,
    trend_24h_vs_7d,
    confidence
  `;

  // Try explain view first, fallback to base view.
  let data: any[] = [];
  let usingExplain = false;

  const r1 = await supabase.from("v_production_decisions_explain").select(selectWithExplain);

  if (r1.error) {
    const r2 = await supabase.from("v_production_decisions").select(selectRequired);
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

  // Normalize to strict, UI-ready rows
  const rows: NormalizedDecisionRow[] = (data as ProductionDecisionRow[]).map(normalizeDecisionRow);

  const sorted: NormalizedDecisionRow[] = [...rows].sort((a, b) => {
    const sr = statusRank(a.production_status) - statusRank(b.production_status);
    if (sr !== 0) return sr;
    if (a.prod_issues_24h !== b.prod_issues_24h) return b.prod_issues_24h - a.prod_issues_24h;
    if (a.prod_issues_7d !== b.prod_issues_7d) return b.prod_issues_7d - a.prod_issues_7d;

    const am = a.minutes_since_last_prod_issue;
    const bm = b.minutes_since_last_prod_issue;
    if (am == null && bm == null) return 0;
    if (am == null) return 1;
    if (bm == null) return -1;
    return am - bm;
  });

  return (
    <main className="min-h-screen bg-slate-50">
      <div className="mx-auto max-w-6xl px-6 py-10">
        <div className="flex items-end justify-between">
          <div>
            <h1 className="text-2xl font-semibold tracking-tight text-slate-900">
              Production Decisions
            </h1>
            <p className="mt-1 text-sm text-slate-600">
              View:{" "}
              <span className="font-mono text-slate-800">
                {usingExplain ? "v_production_decisions_explain" : "v_production_decisions"}
              </span>
            </p>
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

                        {/* Severity is ALWAYS shown (label is derived from score if explain view is absent) */}
                        <span
                          className={[
                            "inline-flex w-fit items-center rounded-full px-2.5 py-1 text-xs font-medium ring-1 ring-inset",
                            severityPillClasses(r.severity_label),
                          ].join(" ")}
                          title={`Severity score (7d): ${r.severity_score_7d}`}
                        >
                          {r.severity_label}
                        </span>

                        {/* Trend + Confidence only exist on explain view */}
                        {usingExplain ? (
                          <>
                            <span
                              className={[
                                "inline-flex w-fit items-center rounded-full px-2.5 py-1 text-xs font-medium ring-1 ring-inset",
                                trendPillClasses(r.trend_24h_vs_7d),
                              ].join(" ")}
                              title="Trend: 24h compared to 7d daily baseline"
                            >
                              {labelTrend(r.trend_24h_vs_7d)}
                            </span>

                            <span
                              className={[
                                "inline-flex w-fit items-center rounded-full px-2.5 py-1 text-xs font-medium ring-1 ring-inset",
                                confidencePillClasses(r.confidence),
                              ].join(" ")}
                              title="Confidence: based on 7d volume + incident status"
                            >
                              {labelConfidence(r.confidence)}
                            </span>
                          </>
                        ) : null}
                      </div>

                      {usingExplain ? (
                        <div className="mt-2 space-y-1 text-xs text-slate-600">
                          <div>
                            <span className="font-medium text-slate-700">Reason:</span>{" "}
                            {r.status_reason ?? "—"}
                          </div>
                          <div>
                            <span className="font-medium text-slate-700">Next:</span>{" "}
                            {r.action_hint ?? "—"}
                          </div>
                        </div>
                      ) : null}
                    </Td>

                    <Td className="text-right tabular-nums">{r.prod_issues_24h}</Td>
                    <Td className="text-right tabular-nums">{r.prod_issues_7d}</Td>
                    <Td className="whitespace-nowrap">{fmtDateTime(r.last_prod_issue_at)}</Td>
                    <Td className="whitespace-nowrap">{fmtRecency(r.minutes_since_last_prod_issue)}</Td>

                    {/* Severity column: score + label ALWAYS (label derived if needed) */}
                    <Td className="text-right tabular-nums">
                      <span className="font-medium">{r.severity_score_7d}</span>
                      <span className="ml-1 text-xs text-slate-500">({r.severity_label})</span>
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
              incident status.
            </div>
          ) : null}
        </div>
      </div>
    </main>
  );
}

// ============================================================================
// Helpers (pure UI helpers)
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

// Shorter, scan-friendly labels
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

// ============================================================================
// File: src/app/decisions/page.tsx
// Block: normalizeDecisionRow
// Version: 20260112-05
// Purpose:
//   Normalize a raw row (PostgREST) into a safe, UI-ready shape.
// Notes:
//   - Severity label is derived from score when missing (Medium threshold = 80).
// ============================================================================

type NormalizedDecisionRow = {
  signal_id: string;
  prod_issues_24h: number;
  prod_issues_7d: number;
  last_prod_issue_at: string | null;
  minutes_since_last_prod_issue: number | null;

  production_status: ProductionStatus;
  severity_score_7d: number;

  status_reason: string | null;
  action_hint: string | null;

  severity_level: number | null;
  severity_label: SeverityLabel;

  trend_24h_vs_7d: TrendLabel | null;
  confidence: ConfidenceLabel | null;
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
  return v === "High" || v === "Medium" || v === "Low" ? v : "None";
}

function deriveSeverityLabelFromScore(score: number): SeverityLabel {
  // Medium threshold chosen by user: 80
  // High is intentionally higher to preserve 3-band meaning
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
  const signal_id =
    typeof row?.signal_id === "string" && row.signal_id.trim() ? row.signal_id.trim() : "";

  const severity_score_7d = toIntOrZero(row?.severity_score_7d);
  const rawLabel = asSeverityLabel(row?.severity_label);
  const severity_label = rawLabel !== "None" ? rawLabel : deriveSeverityLabelFromScore(severity_score_7d);

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

    status_reason: toStringOrNull(row?.status_reason),
    action_hint: toStringOrNull(row?.action_hint),

    severity_level: toNumberOrNull(row?.severity_level),
    severity_label,

    trend_24h_vs_7d: asTrend(row?.trend_24h_vs_7d),
    confidence: asConfidence(row?.confidence),
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
