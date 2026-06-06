Implement the spec in `docs/superpowers/specs/2026-06-01-comms-transport-routing-and-spacecraft-profile-design.md` autonomously
  until the acceptance criteria are satisfied.

  Treat the current worktree as authoritative. Start by reading:
  1. `AGENTS.md`
  2. `docs/superpowers/specs/2026-06-01-comms-transport-routing-and-spacecraft-profile-design.md`
  3. the current router, domain modules, persistence schemas, LiveViews, and tests related to spacecraft types, spacecraft
  creation, provider profiles, path templates, link assignments, comms validation, and readiness.

  Do not stop after analysis or after the first easy slice. Work through the implementation order in the spec:
  1. Stabilize the current worktree.
  2. Rename Spacecraft Type to Spacecraft Profile.
  3. Add first-class Transport domain/table/store/UI, with TCP as the first concrete kind.
  4. Add first-class Routing Rule state/events/domain/table/store/UI.
  5. Update Spacecraft Setup/readiness language.
  6. Update validation and tests.
  7. Remove old primary setup UI only after replacement Profile, Transport, and Routing surfaces exist.

  Before each meaningful code slice, write a short slice-selection note in the conversation:
  - chosen slice
  - why it matters for the spec
  - likely files/tests
  - definition of done

  Keep a compact handoff file at `.codex/status/comms_transport_routing_profile.md`. After each completed slice, replace it with
  the current state:
  - completed changes
  - files touched
  - tests run and results
  - remaining spec gaps
  - next recommended slice

  Follow these route/auth requirements:
  - Spacecraft Profile routes belong in the authenticated mission-scoped `:spacecraft` LiveSession because profiles are mission-
  owned spacecraft configuration and need organization, mission, and user-menu context.
  - Transport and Routing routes belong in the authenticated mission-scoped `:comms` LiveSession because they are mission-owned
  comms setup and need organization, mission, and user-menu context.
  - Spacecraft-specific routing pages belong in the `:spacecraft_show` LiveSession because they require
  `CadenceWeb.SpacecraftAuth` to load `current_spacecraft`.
  - Always pass `current_scope` into `<Layouts.app ...>` and context calls as required by the app’s auth conventions.

  Implementation constraints:
  - Use Phoenix 1.8 conventions from `AGENTS.md`.
  - LiveView templates must start with `<Layouts.app flash={@flash} ...>`.
  - Use `<.input>` and `to_form/2` for forms.
  - Use streams for LiveView collections where appropriate.
  - Use `<.icon>` for icons.
  - Do not use persistent “Link” as the setup noun. Reserve Link for runtime/contact realization.
  - Do not add Contact planning/execution UI in this pass.
  - Do not design generic credential or Transport Behavior UI ahead of concrete adapter needs.
  - Early-development DB reset is acceptable, so prefer clean schema and route design over backward compatibility with old UI
  routes.
  - Keep runtime compatibility bridges only where existing runtime code still needs `ProviderProfile`, `PathTemplate`, or
  `LinkAssignment`.

  Verification expectations:
  - Add or rewrite domain tests for SpacecraftProfile, Transport, TransportKinds.TCPSocket, RoutingRule, routing events,
  validation, and compatibility materialization where implemented.
  - Add or rewrite LiveView tests around user-facing vocabulary and route behavior.
  - Add route/navigation tests for:
    - `/missions/:mission_id/spacecraft/profiles`
    - `/missions/:mission_id/comms/transports`
    - `/missions/:mission_id/comms/routing`
  - Prefer focused tests after each slice, then run `mix precommit` when all changes are done.
  - If `mix precommit` fails, keep fixing until it passes or until there is a genuine external blocker.

  Completion criteria:
  - Creating a spacecraft only asks for identity and optional Spacecraft Profile.
  - Spacecraft Profile pages do not mention contacts or transports.
  - Transport pages describe durable byte-moving capabilities, not active connections.
  - Routing pages describe durable spacecraft use of transports without Link/PathTemplate as primary setup nouns.
  - Spacecraft setup checks only claim identity/profile/application setup, not operational comms readiness.
  - Comms validation findings are visible and actionable under Spacecraft Setup, Transport Setup, Routing Setup, and advanced/
  runtime identity groups.
  - Old provider/path/link setup UI is no longer primary once replacements exist.
  - Tests assert the new vocabulary and boundary: Spacecraft Profile, Transport, Routing Rule, Contact, and runtime Link.
