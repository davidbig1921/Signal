// ============================================================================
// File: src/app/layout.tsx
// Project: Mercy Signal
// Purpose: Root layout required by Next.js App Router.
// Notes:
//   - Must include <html> and <body>.
// ============================================================================

import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Mercy Signal",
  description: "Decision-support system",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
