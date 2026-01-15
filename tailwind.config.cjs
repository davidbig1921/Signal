// ============================================================================
// File: tailwind.config.cjs
// Version: 20260112-01
// Project: Mercy Signal
// Purpose:
//   Tailwind configuration for Next.js App Router project.
// Notes:
//   - Scans both ./src (current) and ./app (legacy).
//   - CommonJS avoids ESM parsing issues.
// ============================================================================

/** @type {import('tailwindcss').Config} */
module.exports = {
  content: [
    "./src/**/*.{js,ts,jsx,tsx,mdx}",
    "./app/**/*.{js,ts,jsx,tsx,mdx}",
  ],
  theme: {
    extend: {},
  },
  plugins: [],
};
