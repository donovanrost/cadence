# Brief: dashboards (feature engineer, Dashboards)

You rebuild Cadence's dashboards inside the Apogee console, so the old dashboard pages can be deleted
(BACKLOG §11, row L8). The user decided on 11-12 to start this now, in parallel with the rest of the
team. This reverses DECISIONS #11 ("dashboards come last"). The director hired you and owns scope;
**lead** owns the console architecture and shared kit; **ux** owns how it looks.

## What already exists (read before planning)
- `docs/apogee/TEAM.md`, `frontend/AGENTS.md`, `frontend/docs/code-standard.md`, `CLAUDE.md`.
- The existing dashboards: `frontend/modules/dashboards-and-exploration` (engine, widget renderers,
  `chart-*.ts`, `DashboardGrid`, GridStack), the legacy routes `/ops/dashboards/**` in
  `apps/cadence_web/lib/cadence_web/router.ex`, and their server modules (`Cadence.Dashboards.*`,
  `DocumentCodec`, `Documents`).
- The user's 2026-10-08 product decisions for the dashboards overhaul. These are binding:
  - **Edit in place** on the viewer: an Edit toggle unlocks the grid; a side sheet configures a
    widget; the draft autosaves. `/edit` redirects into the viewer's edit mode.
  - **Grafana-style saving:** no draft/publish. Every save makes a new version that is current for
    everyone at once; readiness checks run at save. Versions view with compare and non-destructive
    restore (restore = a new version). Save drawer with an optional message and a summary of
    changes; opt-in "save current time range/scope as default". Concurrent edit: "changed by
    another session" with Continue editing / Discard; Continue replays my edits onto the newer
    version and reports any that no longer apply.
  - **Server push for live data**; no client polling. In the console that means the console's
    Phoenix Channel, as the rest of the console does live values.
  - **Scope:** all dashboard pages: viewer/editor, directory/new, settings/sharing/activity/
    diagnostics, library/playlists/explore, export, snapshots.
  - Don't reintroduce the outline / "apply to candidate" / separate-editor flow. Reuse the existing
    widget renderers, `chart-*.ts`, `DashboardGrid` and engine where they fit the console.
- There is no Apogee design board for dashboards. A dashboard is a full-screen cockpit and
  deliberately breaks the management look; ux decides how it sits in the console shell.

## First deliverable (before any code)
`docs/apogee/plans/dashboards.md`: route map in the console, which existing engine/renderer code
you reuse vs rewrite, the data each screen needs and where it comes from (existing endpoint, a
legacy LiveView-only path, or missing), the live-data path over the Channel, the save/version/
conflict model against what the server supports today, a build order in slices that each ship
something usable, and open questions. Send **api** / **api-ops** the missing-endpoint list (via
lead), **ux** the layout questions, and the director the path.

## Rules
- Shared worktree (`ui-apogee-spa`): keep lib compiling after every save; commit only your own
  files/hunks; `HK=0 git commit` after running your own checks (typecheck, lint, unit tests;
  Elixir: format, compile --warnings-as-errors, targeted tests). Read
  `docs/apogee/ROSTER.md` for who is who.
- Use your own `MIX_TEST_PARTITION=9` for any Elixir tests. Check `uptime` first; over 16 means
  targeted tests only. The machine is shared by ~12 agents.
- **No browser e2e in your routine checks** (CI runs them). Running a spec locally is fine only
  while writing that spec.
- **No new features in the legacy pages**; they are being deleted.
- **Freeze 11-13 23:33Z to 11-14 01:00Z**: no lib saves, no :4011/simulator restarts, light load.
- Don't touch the dev DB or restart :4011; qa owns the dev stack.
- Talk via herdr: `"$HERDR_BIN_PATH" pane run <pane> "[from dashboards] ..."`. Report to lead
  for day-to-day; scope questions to the director (`w0Q:p1`).
