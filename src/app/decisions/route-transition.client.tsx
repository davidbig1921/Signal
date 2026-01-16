// ============================================================================
// File: src/app/decisions/route-transition.client.tsx
// Version: 20260116-02-route-transition-safe
// Project: Mercy Signal
// Purpose:
//   Safe fade-in on route segment change without hydration race conditions.
// Notes:
//   - Uses key-based remount only (no opacity flip-flop).
//   - Proven safe with App Router + Server Components.
// ============================================================================

"use client";

import React from "react";
import { usePathname } from "next/navigation";

export default function DecisionsRouteTransition({
  children,
}: {
  children: React.ReactNode;
}) {
  const pathname = usePathname();

  return (
    <div
      key={pathname}
      className="animate-in fade-in duration-150"
    >
      {children}
    </div>
  );
}
