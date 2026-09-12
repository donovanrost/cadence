# Ops initial-state QA

## Scope

The September 11, 2026 QA pass investigated generic feature-unavailable messages on command creation and an unpublished dashboard. It used an authenticated browser against a sandboxed fresh mission, with no activated mission model, no command requests, and one empty unpublished dashboard. This complements the migration checks with setup and publication lifecycle coverage.

Three distinct causes were found:

- The initial Ops LiveView crash came from pending development database migrations: the command queue schema expected `active_release_attempt_id`. Applying the reviewed pending migrations restored the shared Ops context read.
- Command creation treated the absence of an activated command model as a generic feature failure. The authorized feature now renders a command-model prerequisite and offers a read-only refresh. Preview and creation remain unavailable until the model is activated.
- The dashboard directory omitted publication status and sent unpublished drafts to a published-only viewer. Both that viewer and execution diagnostics treated an unpublished dashboard as a generic feature failure. Directory rows now carry `published_version`; authors open unpublished dashboards in the editor. Direct viewer and diagnostics links explain that publication is required and offer refresh and an authorized editor link.

Published viewers still pin published versions. The publication prerequisite contains scoped identity and author capability, with no draft name or document. Missing, archived, foreign, unauthorized, and malformed-URL requests retain their existing rejection behavior. Diagnostics prerequisites hold no inspection session and admit no inspection action. Current policy grants dashboard authoring to active human mission operators; the frontend also honors an explicit false author capability.

## Repeatable browser coverage

`apps/cadence_web/browser_test/cadence_web/assets/ops_initial_state_browser_test.exs` drives `frontend/tools/phoenix/ops_initial_state_browser.mjs` against an ephemeral Phoenix endpoint and published frontend assets. The test creates sandboxed fixtures, authenticates with credentials passed through stdin, and verifies these 29 routes:

| Area | Routes relative to `/missions/:mission_id` |
| --- | --- |
| Overview | `/ops` |
| Dashboards | `/ops/dashboards`, `/new`, `/library`, `/playlists` beneath the directory; unpublished `/:dashboard_id`, `/edit`, `/settings`, `/activity`, `/diagnostics` |
| Commands | `/ops/commands`, `/new`, `/stages`, `/stages/new` beneath commands |
| Observation | `/ops/explore`, `/ops/alarms`, `/ops/timeline` |
| Planning | `/ops/planning`, `/new`, `/policy` beneath planning |
| Requirements | `/ops/requirements`, `/ops/requirements/new`, `/ops/requirement-templates` |
| Contacts | `/ops/contacts` |
| Data sources | `/ops/data-sources`, `/ops/data-sources/registration/new` |
| Data operations | `/ops/data-operations`, `/ops/data-operations/manage` |
| Activation | `/ops/activations` |

Each route must render without a JavaScript page error, timeout, or generic Ops-unavailable fallback. The browser also verifies the draft directory link, publication notices, refresh, editor navigation, and 390px layout. The native test verifies that the audit creates no command requests, activates no model, and leaves the dashboard unpublished. JSON results and desktop/mobile screenshots are written to `CADENCE_INITIAL_STATE_ARTIFACTS`, or a unique temporary directory when unset.

After installing the existing frontend dependencies and building publication assets:

```sh
# From frontend
corepack pnpm build:publication

# From apps/cadence_web
MIX_ENV=test mix assets.build
CADENCE_BROWSER_PROPS_DIFF=true MIX_ENV=test mix test --include browser_smoke --only browser_smoke browser_test/cadence_web/assets/ops_initial_state_browser_test.exs
```

Use the checkout's supported Elixir/OTP toolchain and an installed Chrome browser. Clear `CADENCE_BROWSER_PROPS_DIFF` before ordinary LiveVue tests and root `mix precommit`.

Focused native tests in `ops_workspace_page_test.exs`, `ops_diagnostics_page_test.exs`, `ops_directory_page_test.exs`, and `dashboard_workspace_read_test.exs` cover publication transitions, invalid scope and URL rejection, real producer-to-Vue rendering, absence of inspection authority before publication, and published/draft separation. Frontend tests cover strict prerequisite admission, capability-dependent links, refresh failure redaction, and directory navigation before and after publication.

## Observed verification

The initial 29-route diagnostic reproduced two generic failures: the unpublished dashboard viewer and its diagnostics page. After the lifecycle fix, the same initial-state matrix passed in Chrome with zero generic fallbacks, timeouts, or recorded page errors. Desktop and 390px screenshots were inspected. Focused verification passed 26 native tests, 69 dashboard frontend tests, and 57 host integration tests. The frontend check passed all 20 projects with zero errors and the existing 238 warnings; publication and Phoenix asset builds passed.

## Limits

This matrix covers initial routes and the specific dashboard publication lifecycle. It does not prove every resource detail route, all 75 features, every role, populated telemetry behavior, or all write workflows. A passing fresh-mission matrix is not a substitute for QA of populated missions and governed actions. The audit does not publish or activate user data.
