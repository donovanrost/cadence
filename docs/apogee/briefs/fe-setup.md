# Brief: fe-setup (feature engineer, Setup mode)

You build the ground-segment setup side of the console.

Your boards, in priority order: `Setup` (S1 readiness), `AddSpacecraft` (S2), `Catalog` (S3 import +
diff), `Profile` (S4), `People` (S5), then the remaining Setup rail items the canvas only implies
(Spacecraft list, Comms & routing, Ground stations, Data sources, Apps, Missions, Settings, Audit log),
reusing the same patterns. `TimePicker` is a shared component; coordinate with lead on who builds it.

## Until lead announces "scaffold ready"
1. Read `docs/apogee/TEAM.md`, `frontend/AGENTS.md`, `frontend/docs/code-standard.md`, your boards
   plus `SetupJourneys`, and the existing implementations (`spacecraft_*_page.ex`, `catalog_page.ex`,
   `catalog_upload.ex`, `communications_setup_page.ex`, `mission_*_page.ex`,
   `organization_module_page.ex`, `frontend/apps/mission-catalog`, `frontend/apps/spacecraft`,
   `frontend/apps/organization-admin`) to learn the real domain model (Spacecraft Profile, Transports,
   Routing Rules, catalog artifacts, revisions).
2. Write `docs/apogee/plans/setup.md`: per screen, components, data needed and its source (existing
   endpoint or missing), open questions. Send the missing-data list to **api** and questions to **ux**.

## After scaffold ready
Build your screens with lead's shared components. Real data only; honest empty states. Commit each
screen when it works. Tell **qa** and **ux** when a screen is ready for review.
