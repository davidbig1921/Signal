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
 * - supports hover/focus/click/touch
 */
export default function TooltipIdClient({ label, id }: TooltipIdProps) {
  const [open, setOpen] = React.useState(false);
  const [pos, setPos] = React.useState<{ top: number; left: number } | null>(null);
  const anchorRef = React.useRef<HTMLSpanElement | null>(null);
  const tipRef = React.useRef<HTMLDivElement | null>(null);

  const compute = React.useCallback(() => {
    const el = anchorRef.current;
    if (!el) return;

    const r = el.getBoundingClientRect();

    // Estimate tooltip size (fallback); refine after first paint using tipRef.
    const tipW = tipRef.current?.offsetWidth ?? 260;
    const tipH = tipRef.current?.offsetHeight ?? 28;

    const margin = 8;
    const desiredTop = r.bottom + 8;
    const desiredLeft = r.left;

    // Clamp into viewport
    const left = clamp(desiredLeft, margin, window.innerWidth - tipW - margin);
    const top = clamp(desiredTop, margin, window.innerHeight - tipH - margin);

    setPos({ top, left });
  }, []);

  const close = React.useCallback(() => setOpen(false), []);

  const openNow = React.useCallback(() => {
    if (!id) return;
    setOpen(true);
    // compute after open so tipRef can measure
    requestAnimationFrame(() => compute());
  }, [id, compute]);

  React.useEffect(() => {
    if (!open) return;

    const onScroll = () => close(); // “alive” UX: close on scroll
    const onResize = () => compute();
    const onKeyDown = (e: KeyboardEvent) => {
      if (e.key === "Escape") close();
    };
    const onPointerDown = (e: PointerEvent) => {
      const a = anchorRef.current;
      const t = tipRef.current;
      const target = e.target as Node | null;
      if (!target) return;

      // Close when clicking outside both anchor and tooltip
      if (a && a.contains(target)) return;
      if (t && t.contains(target)) return;
      close();
    };

    window.addEventListener("scroll", onScroll, true);
    window.addEventListener("resize", onResize);
    window.addEventListener("keydown", onKeyDown);
    window.addEventListener("pointerdown", onPointerDown);

    return () => {
      window.removeEventListener("scroll", onScroll, true);
      window.removeEventListener("resize", onResize);
      window.removeEventListener("keydown", onKeyDown);
      window.removeEventListener("pointerdown", onPointerDown);
    };
  }, [open, close, compute]);

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
        ref={anchorRef}
        className="inline-flex items-center"
        onMouseEnter={openNow}
        onMouseLeave={close}
        onFocus={openNow}
        onBlur={close}
        onClick={(e) => {
          e.preventDefault();
          e.stopPropagation();
          open ? close() : openNow();
        }}
        onTouchStart={(e) => {
          e.preventDefault();
          e.stopPropagation();
          open ? close() : openNow();
        }}
        tabIndex={0}
        role="button"
        aria-label={`${label} ${id}`}
        aria-expanded={open}
      >
        <span className="cursor-default font-medium text-slate-900 underline decoration-slate-200 underline-offset-2">
          {shortId(id)}
        </span>
      </span>

      {open && pos
        ? createPortal(
            <div
              ref={tipRef}
              className="pointer-events-none fixed z-[9999] whitespace-nowrap rounded-md bg-slate-900 px-2 py-1 text-xs text-white shadow-lg"
              style={{ top: pos.top, left: pos.left }}
            >
              {id}
            </div>,
            document.body
          )
        : null}
    </span>
  );
}
