Roadmap to 100% (rough, but structured)

Here is the 100-phase roadmap grouped into milestones. (Each phase = ~1%. Some will be tiny, some bigger, but the progress bar stays simple.)

0–10% Foundation

Repo + Next app boot

Node/npm stable

Tailwind stable (v3) + CSS builds

Env setup (.env.local)

Supabase project created

Auth working (signup/signin)

Logout

Basic routing

Error boundaries / basic UX polish

ROADMAP.md added + versioning started

11–20% Security baseline

Define roles (leader/staff)

Create profiles table

RLS policies for profiles

Route protection (server-side, stable)

Session handling

First admin bootstrap method

Read-only leadership mode (UI)

Staff edit mode (UI)

Audit fields (created_at/updated_at)

“Bulletproof basics” checklist file

21–40% Core Mercy Signal data model

signals table schema

tags table schema

signal_tags join table

votes table schema

Status enum rules (new/review/planned/done)

RLS for signals (staff write, leader read)

RLS for votes (auth users)

Seed demo data script

API utilities (supabase client wrappers)

Internal conventions doc

Create signal form (staff)

List signals (staff)

Signal detail page

Edit signal status

Tag signals

Search/filter by tag

Sort by priority score

Vote/score UI

Prevent double voting

“Top signals” view

41–60% Decision clarity UX

Dashboard: Top signals

Status board view

“Under review” queue

“Planned” roadmap view

“Completed” archive

Signal grouping (manual grouping v1)

Duplicate detection (manual merge v1)

Comments (optional, minimal)

Decision notes (leadership)

Read-only leadership dashboard

Staff triage workflow (new → review)

Simple analytics: volume by tag

Simple analytics: votes over time

Export CSV (optional)

Minimal notifications (in-app only)

Accessibility pass

Mobile responsive pass

Empty states + loading states

Fast UI polish

Performance pass

61–80% “Government / Assembly grade” hardening

Strict RLS verification tests

Logging strategy (minimal)

Rate-limit public endpoints (if any)

Abuse prevention (votes)

Data retention rules

Multi-organization support (Org table)

Membership table (org_members)

Org switching UI

Role per org (leader/staff)

Invite via admin panel (no email)

Import user list (manual)

Audit trail table (who changed status)

Immutable decision records

Backup/restore notes

Environment separation (dev/prod)

Deployment checklist (Vercel)

Supabase prod policies review

“Least privilege” review

Security doc (1 pager)

Final hardening pass

81–90% Mercy Ecosystem integration readiness

Ecosystem config keys

Shared navbar placeholder

Shared theme tokens

Standard API contract docs

Health check endpoint

Version endpoint

Feature flags file

Tenant isolation tests

Deploy preview workflow

Final integration checklist

91–100% Release

End-to-end test run list

Bugfix sprint 1

Bugfix sprint 2

UI consistency sweep

Documentation sweep

Demo dataset + demo script

Production deploy

Smoke test production

“Ready” sign-off checklist

v100.0 — integrated-ready