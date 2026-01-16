// src/app/decisions/layout.tsx
import type { ReactNode } from "react";
import DecisionsRouteTransition from "./route-transition.client";

export default function DecisionsLayout({ children }: { children: ReactNode }) {
  return (
    <div className="min-h-screen bg-neutral-950 text-neutral-50">
      {/* Stable header = less “full rerender” feeling */}
      <div className="border-b border-neutral-800 bg-neutral-950/80 backdrop-blur">
        <div className="mx-auto flex max-w-5xl items-center justify-between px-4 py-4">
          <div className="text-sm font-medium tracking-wide text-neutral-200">
            Mercy Signal
          </div>
          <div className="text-xs text-neutral-400">
            Decisions
          </div>
        </div>
      </div>

      <div className="mx-auto max-w-5xl px-4 py-6">
        {/* Wrap children in a tiny “fade-in on route change” */}
        <DecisionsRouteTransition>{children}</DecisionsRouteTransition>
      </div>
    </div>
  );
}
