# STRATEGY — Rich-Corpus Fixture

> Synthetic spec corpus for testing SpecSwarm v7's `ss-tech-stack-extractor` and
> `ss-constitution-extractor` subagents. Mirrors the shape of a real product
> Strategy doc with `[DECIDED]` / `[OPEN]` markers and a decision log.

## 1. Vision

The Acme Widget Platform is a customer-facing storefront. The decisions below
are binding for the implementation team; deviations require an amendment to
this document and a re-review.

## 2. Architecture Overview

We build a single-page web app with server-rendered routing, server-managed
state (no client store), and a single Postgres database. Caching is intentionally
absent in phase 1.

## 3. Decision log

| Date       | Decision                                                  | Rationale (brief)                                      |
|------------|-----------------------------------------------------------|--------------------------------------------------------|
| 2026-03-01 | Framework: **React Router v7** [DECIDED]                  | Loaders/actions match our server-first preference.     |
| 2026-03-01 | Language: **TypeScript 5.4**, strict mode on [DECIDED]    | Domain model has heavy invariants; types pay off.      |
| 2026-03-03 | Build tool: **Vite 6** [DECIDED]                          | HMR speed; first-class React Router framework support. |
| 2026-03-05 | State management: **Server-side via React Router** [DECIDED] | No Redux. No Zustand. Server actions for mutations. |
| 2026-03-05 | Styling: **Tailwind CSS v4** [DECIDED]                    | Team familiarity; design tokens map cleanly.           |
| 2026-03-10 | Testing: **Vitest** (unit), **Playwright** (e2e) [DECIDED] | Replaces Jest; Vitest matches Vite tooling.           |
| 2026-03-15 | DB: **PostgreSQL 17** [DECIDED]                           | Mature; JSONB for flexible product attributes.         |

## 4. Tech Stack

### 4.1 Framework

- **React Router v7** [DECIDED 2026-03-01]
- We use framework mode (not library mode). Routes are configured in
  `app/routes.ts`. All data flows through loaders and actions.
- **Rejected**: Next.js (App Router was less mature when we decided; team had
  React Router muscle memory).

### 4.2 Language

- **TypeScript 5.4** [DECIDED 2026-03-01]
- Strict flags enabled: `strict`, `noUncheckedIndexedAccess`, `exactOptionalPropertyTypes`
- Rationale: the product's pricing engine has subtle correctness requirements
  that strict types catch at edit time.

### 4.3 Build tool

- **Vite 6** [DECIDED 2026-03-03]
- React Router v7 framework mode runs natively on Vite.

### 4.4 State management

- **Server-managed via React Router loaders/actions** [DECIDED 2026-03-05]
- Forbidden: Redux, Zustand, Recoil, MobX, Jotai, any client-side store
  library. If you find yourself reaching for one, the answer is "use a
  loader."
- A small amount of UI-local state (open/closed dialog, hover state) lives
  in component state via `useState`; this is fine.

### 4.5 Styling

- **Tailwind CSS v4** [DECIDED 2026-03-05]
- Forbidden: styled-components, emotion, CSS-in-JS in general.
- Design tokens live in `app/styles/tokens.css`.

### 4.6 Testing

- **Vitest** for unit testing [DECIDED 2026-03-10]
- **Playwright** for end-to-end testing [DECIDED 2026-03-10]
- Integration testing happens within Vitest with the React Testing Library;
  we do not maintain a separate integration test runner.
- **Rejected**: Jest (slower; tooling mismatch with Vite).

### 4.7 Approved libraries

These libraries are pre-approved and don't need re-justification:

- `zod` — runtime validation, shared with TypeScript inference
- `@react-router/node` — Node adapter for React Router v7
- `drizzle-orm` — DB access layer (chosen over Prisma; ORM-level type inference fits TS strict mode)
- `argon2` — password hashing
- `pino` — structured logging

### 4.8 Prohibited technologies

- ❌ **Axios** → Use `fetch` (native, no extra bytes)
- ❌ **Lodash** → Use native JS array/object methods
- ❌ **moment.js** → Use `date-fns` or native `Intl.DateTimeFormat`
- ❌ **Class components** → Functional components only
- ❌ **Default exports** in app code → Named exports only; clearer refactors

## 5. Open decisions

These have NOT been decided yet and are tracked for upcoming phases:

- [OPEN] **Image CDN provider** — phase 2 deadline; candidates: Cloudinary, imgix, Vercel Image Optimization.
- [OPEN] **Email transactional provider** — phase 2 deadline; candidates: Postmark, Resend.
- [OPEN] **Analytics**: PostHog vs. Mixpanel vs. self-hosted — phase 3 deadline.

## 6. Database

- **PostgreSQL 17** [DECIDED 2026-03-15]
- Managed via Drizzle ORM.
- Migrations live under `db/migrations/` and are append-only after merge.

## 7. Deployment

Out of scope for this fixture.

## 8. Cross-cutting

- All HTTP requests originating from the browser MUST go through React Router
  loaders/actions. No `fetch()` calls inside components.
- All database access happens inside loaders or actions. No DB calls inside
  components.

---

_Fixture file. Not real product strategy. Used by SpecSwarm v7 tests._
