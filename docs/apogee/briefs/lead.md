# Brief: lead (tech lead / frontend architect)

You own the technical shape of the new Vue SPA and keep the team unblocked.

## First deliverables (in order)
1. Read `docs/apogee/TEAM.md`, `frontend/AGENTS.md`, `frontend/docs/code-standard.md`,
   `frontend/README.md`, and skim `docs/apogee/design-reference/Main.dc.html` + `Now.dc.html` + `Catalog.dc.html`.
   Run `corepack pnpm install` in `frontend/` (toolchain is pinned via mise/vp; `mise trust` is already done).
2. Write `docs/apogee/ARCHITECTURE.md` (short): app location, routing map (Ops vs Setup modes,
   mission-scoped URLs like `/console/:org/:mission/...`), state, API client + runtime decoding,
   live-data (Phoenix Channels) approach, auth/CSRF, how Phoenix serves the built SPA and how dev works
   (Vite dev server proxying to Phoenix on :4000). Confirm or change the defaults in TEAM.md.
3. Scaffold `frontend/apps/console` (or your chosen location): Vue 3 + TS + vue-router + Tailwind v4,
   Apogee tokens from ux (start from the canvas values: bg `#05070A`, panel `#0A0E13`, rules `#1C2530`,
   text `#E6EDF3`, muted `#7D8A99`/`#9DAAB8`, caution `#FFB020`, fonts Saira / Saira Condensed / Azeret Mono).
4. The **app shell**: top bar (Cadence mark, org/mission switcher, Ops|Setup mode toggle, ⌘K search
   trigger, config revision, UTC clock, account), the Setup left rail, the panel primitive
   (indexed header `A1 TITLE … right meta`), buttons, tags/status, tables, stat strips.
   Build these as a small shared component set the feature engineers will reuse.
5. Work with **api** so Phoenix serves the SPA at `/console/*` behind the session, and the SPA can call
   a bootstrap endpoint (current user, orgs, missions, CSRF).
6. When the shell renders with real session data, message fe-ops, fe-setup, qa and the director:
   "scaffold ready" + where things live + how to run it.

## Ongoing
- Review feature engineers' structure; keep shared components in one place; prevent duplication.
- Resolve technical disputes; escalate scope questions to the director.
