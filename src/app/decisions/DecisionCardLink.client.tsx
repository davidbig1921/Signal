"use client";

import React from "react";
import Link from "next/link";

export default function DecisionCardLink({
  href,
  children,
}: {
  href: string;
  children: React.ReactNode;
}) {
  const [pressed, setPressed] = React.useState(false);

  return (
    <Link
      href={href}
      prefetch
      scroll={false}
      className={[
        "group block rounded-2xl focus:outline-none focus:ring-2 focus:ring-slate-300",
        pressed ? "opacity-90" : "",
      ].join(" ")}
      onMouseDown={() => setPressed(true)}
      onMouseUp={() => setPressed(false)}
      onMouseLeave={() => setPressed(false)}
      onTouchStart={() => setPressed(true)}
      onTouchEnd={() => setPressed(false)}
      onKeyDown={(e) => {
        if (e.key === "Enter" || e.key === " ") setPressed(true);
      }}
      onKeyUp={() => setPressed(false)}
    >
      {/* Motion feedback */}
      <div className="rounded-2xl transition group-hover:-translate-y-[1px] group-hover:shadow-md active:scale-[0.99]">
        {children}
      </div>

      {/* Small cue */}
      <div className="mt-2 text-[11px] text-slate-400 opacity-0 transition group-hover:opacity-100">
        Open detail →
      </div>
    </Link>
  );
}
