// ============================================================================
// File: src/app/layout.tsx
// Project: Mercy Signal
// Purpose: Root layout required by Next.js App Router.
// Notes:
//   - Must include <html> and <body>.
//   - Sets base background/text to prevent low-contrast “dead” pages.
// ============================================================================

import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Mercy Signal",
  description: "Decision-support system",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className="h-full">
      <body className="min-h-full bg-slate-950 text-slate-100 antialiased">
        {children}
      </body>
    </html>
  );
}
