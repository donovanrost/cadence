# Console accessibility specs

These specs check that every console screen can be used by keyboard and screen reader (#189). The
rules are in `docs/apogee/ux/design-language.md` §6, and the pass/fail items are in
`docs/apogee/ux/a11y-checklist.md`. Results and the open-gap inventory are recorded on #189.

- `sweep.a11y.ts` loads every console screen and runs axe and the keyboard pass on it. It is the
  broad net: each screen prints one `A11Y-SWEEP {json}` line, and its findings fail softly.
- `<screen>.a11y.ts` is a per-screen spec. It adds what a sweep can't see: sheets and dialogs
  opened and closed (checklist A1–A5), reading order, and screen-specific stops. `now.a11y.ts` is
  the example to copy.

## Where they run

- **CI:** the `console-e2e` job (`.github/workflows/ci.yml`) runs them on every PR that touches
  code, in four shards. It is non-blocking and not in `ci-ok`. Each shard boots its own Postgres,
  QuestDB, simulator and Phoenix, seeds the Reflect Orbital demo and the QA personas, and uploads
  the Playwright report. To read the sweep from a run, use
  `gh run view --job <id> --log | grep A11Y-SWEEP`.
- **Locally:** only while you write or fix a spec. Full runs belong in CI. Run against your own
  worktree's stack, never someone else's. Use the same settings as the CI job:
  - your own database (`CADENCE_DEV_DATABASE`), Phoenix port (`PORT`) and simulator port
    (`EARENDIL_SIMULATOR_PORT`, `EARENDIL_PROVIDER_URL`);
  - the built console (`CONSOLE_VITE_ORIGIN=""`), or the Vite dev server;
  - the seeds `dev/reflect_orbital_demo.exs`, `dev/apogee_qa_personas.exs` and
    `dev/reflect_orbital_planning.exs`.

  Then, from `frontend/apps/console`:

  ```sh
  BASE_URL=http://127.0.0.1:<port> ./node_modules/.bin/playwright test e2e/a11y/<file> \
    --project=a11y-desktop-admin --workers=1
  ```

  The personas sign in with `CADENCE_ADMIN_EMAIL`/`_PASSWORD` and `E2E_PERSONA_PASSWORD`
  (`e2e/support/env.ts`). Never commit a password.

## Projects

Every `*.a11y.ts` runs in four projects (`playwright.config.ts`, `e2e/support/a11y-projects.ts`):

- two widths: desktop 1440×900 and phone 390×844;
- two personas: `admin`, an organization admin (`qa-org-admin`), and `member`, an operator without
  admin (`qa-operator`).

The sweep runs as `admin` only, because that persona sees the most controls. A per-screen spec
reads the persona with `a11yPersona(info)` when the screen differs by role.

## What each check does

- **Read-only** (`support/read-only.ts`): the specs load pages, press Tab, and open and close
  sheets. Any write is aborted, so they never act on data.
- **Rendered first** (`waitForScreen`): checks wait for `body[data-shell-ready]`, a quiet network
  (best effort, since live pushes may never go idle), and no "Loading…" left in `<main>`.
- **axe** (`expectAccessible`, or the sweep's own call): WCAG 2.1 A/AA (`wcag2a`, `wcag2aa`,
  `wcag21a`, `wcag21aa`). This includes 4.5:1 text contrast and `scrollable-region-focusable`.
- **Keyboard pass** (`expectKeyboardPass`):
  - one `h1`, one `main`, and no sideways scroll;
  - then Tab from the top, up to 120 stops. Each stop must be visible, not inside `aria-hidden`,
    not covered by another element (`elementFromPoint`), and show a focus indicator;
  - focus must never stick, and Tab must not come back to a landmark it left.

  Kit inputs show focus by turning their wrapper's border white rather than with an outline, and
  the probe counts that as an indicator.

- **Sheets** (`expectSheetChecks`, checklist A1–A5): opening moves focus into the sheet, the sheet
  has a name, focus is trapped inside it, Esc closes it, and focus returns to the opener.
- **Excluded:** the dev-only Tidewave toolbar (`#tidewave-toolbar`). It isn't in production builds.

## Not covered by the sweep

- Platform admin (`/admin`), which needs step-up admin mode.
- The dev-only `/kit`.
- Detail screens without a stable demo id.

Per-screen specs cover those as their owners add them.
