"use client";

import React from "react";
import { createPortal } from "react-dom";

export type TooltipIdProps = { label: string; id: string | null };

function shortId(id: string | null): string {
  if (!id) return "unknown";
  return id.length > 12 ? `${id.slice(0, 8)}…${id.slice(-4)}` : id;
}

function clamp(n: number, min: number, max: number) {
  return Math.max(min, Math.min(max, n));
}

/**
 * Tooltip that:
 * - never shifts layout (portal)
 * - never clips (document.body)
 * - positions from anchor rect
 * - click-to-copy (so it feels alive)
 */
export default function TooltipIdClient({ label, id }: TooltipIdProps) {
  const [open, setOpen] = React.useState(false);
  const [copied, setCopied] = React.useState(false);
  const [pos, setPos] = React.useState<{ top: number; left: number } | null>(null);
  const ref = React.useRef<HTMLSpanElement | null>(null);
  const timerRef = React.useRef<number | null>(null);

  const compute = React.useCallback(() => {
    const el = ref.current;
    if (!el) return;
    const r = el.getBoundingClientRect();

    // anchor center, clamp to viewport
    const left = clamp(r.left + r.width / 2, 12, window.innerWidth - 12);
    const top = clamp(r.bottom + 10, 12, window.innerHeight - 12);

    setPos({ top, left });
  }, []);

  const onEnter = () => {
    if (!id) return;
    compute();
    setOpen(true);
  };

  const onLeave = () => {
    setOpen(false);
    setCopied(false);
    if (timerRef.current) window.clearTimeout(timerRef.current);
    timerRef.current = null;
  };

  const doCopy = async () => {
    if (!id) return;
    try {
      await navigator.clipboard.writeText(id);
      setCopied(true);
      if (timerRef.current) window.clearTimeout(timerRef.current);
      timerRef.current = window.setTimeout(() => setCopied(false), 900);
    } catch {
      // no-op: clipboard may be blocked in some contexts
    }
  };

  React.useEffect(() => {
    if (!open) return;
    const onScroll = () => compute();
    const onResize = () => compute();
    window.addEventListener("scroll", onScroll, true);
    window.addEventListener("resize", onResize);
    return () => {
      window.removeEventListener("scroll", onScroll, true);
      window.removeEventListener("resize", onResize);
    };
  }, [open, compute]);

  React.useEffect(() => {
    return () => {
      if (timerRef.current) window.clearTimeout(timerRef.current);
    };
  }, []);

  if (!id) {
    return (
      <span className="inline-flex items-center gap-1 text-slate-500">
        {label} <span className="text-slate-700">unknown</span>
      </span>
    );
  }

  return (
    <span className="inline-flex items-center gap-1">
      <span className="text-slate-500">{label}</span>

      <span
        ref={ref}
        className="inline-flex items-center"
        onMouseEnter={onEnter}
        onMouseLeave={onLeave}
        onFocus={onEnter}
        onBlur={onLeave}
      >
        <span
          role="button"
          tabIndex={0}
          onClick={doCopy}
          onKeyDown={(e) => {
            if (e.key === "Enter" || e.key === " ") {
              e.preventDefault();
              doCopy();
            }
          }}
          className="cursor-pointer select-none rounded-md px-1 font-medium text-slate-900 hover:bg-slate-100 focus:outline-none focus:ring-2 focus:ring-slate-300"
          title="Click to copy"
        >
          {shortId(id)}
        </span>
      </span>

      {open && pos
        ? createPortal(
            <div
              className="pointer-events-none fixed z-[9999] whitespace-nowrap rounded-md bg-slate-900 px-2 py-1 text-xs text-white shadow-lg"
              style={{
                top: pos.top,
                left: pos.left,
                transform: "translateX(-50%)",
              }}
            >
              {copied ? "Copied" : id}
            </div>,
            document.body
          )
        : null}
    </span>
  );
}
