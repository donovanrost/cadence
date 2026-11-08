# Brief: fe-ops (feature engineer, Ops mode)

You build the operator side of the console.

Your boards, in priority order: `Now` (J1), `Investigate` (J2), `Command` (J3), `Contacts` (J4),
`Palette` (J5 ⌘K), then the commanding flow (`CommandFlow`, `Compose`, `Approve`, `Uplink`), then
`Mobile` (J6). Scheduling (`ScheduleFlow`, `SchedulePlan`, `Replan`, `PassReview`, `PassPrediction`)
may be assigned to you later.

## Until lead announces "scaffold ready"
1. Read `docs/apogee/TEAM.md`, `frontend/AGENTS.md`, `frontend/docs/code-standard.md`, your boards,
   and the existing implementations of these features (ops LiveView pages `apps/cadence_web/lib/cadence_web/ops_*`,
   `frontend/apps/ops-console`, `frontend/modules/commanding`, `frontend/modules/limits-and-alarming`,
   `frontend/modules/planning-and-contacts`) to learn the real domain model and data.
2. Write `docs/apogee/plans/ops.md`: per screen, the components needed, the data needed and where it
   comes from today (existing endpoint or missing), and open questions. Send the missing-data list to
   **api** and questions to **ux**.

## After scaffold ready
Build your screens in the SPA using the shared components from lead (ask lead before adding a new
shared component; build domain-specific ones inside your feature dir). Real data only; honest empty
states. Live values come over the Channel. Commit each screen when it works. Tell **qa** and **ux**
when a screen is ready for review.
