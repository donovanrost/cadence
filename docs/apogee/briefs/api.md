# Brief: api (backend / Phoenix API engineer)

You own every Elixir change: serving the SPA, auth for it, and the JSON + Channel contracts it uses.
Modifying APIs is allowed; prefer clean, purpose-built endpoints.

## First deliverables
1. Read `CLAUDE.md`, `AGENTS.md`, `docs/apogee/TEAM.md`, and `apps/cadence_web/lib/cadence_web/router.ex`.
   Load the relevant elixir-phoenix-guide skills before writing code (phoenix-json-api,
   phoenix-channels-essentials, security-essentials, testing-essentials).
2. `docs/apogee/api/inventory.md`: what already exists that the SPA can use (the `/api/...` routes
   behind `authenticated_api`, `/api/cadence/application-host/v1`, `/api/cadence/contact-workspace/v1`,
   the facades in `apps/cadence`), how each authenticates, and gaps.
3. **SPA hosting + session:** a `/console/*` catch-all in the browser pipeline that requires an
   authenticated scope (redirect to `/sign-in` otherwise) and serves the built SPA index; a
   session-authenticated JSON scope for the SPA (cookie + CSRF header) e.g. `/api/console/v1/...`;
   a bootstrap endpoint (`GET /api/console/v1/session`: user, orgs, missions, capabilities, CSRF token).
   Coordinate the build-output path and dev proxy with **lead**.
4. A Phoenix Channel socket for the SPA (session-authenticated) for live data: mission health/alarms,
   latest telemetry, uplink progress. Start with what Now needs.
5. Then build endpoints screen by screen as **ux** and the feature engineers send data needs. Document
   each contract in `docs/apogee/api/<area>.md` (request, response shape, errors, example) before or
   alongside the code so frontend can build against it.

## Rules
- `mix compile --warnings-as-errors`, `mix credo --strict`, `mix format`, and tests for every endpoint
  (`cd apps/cadence_web && mix test`). Controllers call the `Cadence` facade (domain layering).
- Authorization: org/mission scoping must be enforced server side on every endpoint.
