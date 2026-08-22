# Comms Transport/Routing/Profile Handoff

## Completed Changes

- Moved primary Spacecraft Profile UI to `/missions/:mission_id/spacecraft/profiles`, `/new`, and `/:profile_id` in the authenticated mission-scoped `:spacecraft` LiveSession.
- Updated mission/sidebar and spacecraft create/edit/show copy to use "Spacecraft Profile"; spacecraft creation asks only for identity plus optional profile.
- Kept `SpacecraftType` backend names as a temporary compatibility bridge while the user-facing surface uses Profile vocabulary.
- Added first-class `Cadence.Comms.Transport` domain object, `comms_transports` migration/table, persistence schema, store, TCP socket kind, provider-profile compatibility materialization, public facade functions, and authenticated `:comms` Transport routes/UI.
- Added first-class `Cadence.Comms.RoutingRule` and `RoutingRuleEvent` domain objects, `comms_routing_rules` and `comms_routing_rule_events` migration/tables, persistence schemas, store, append-only events, PathTemplate/LinkAssignment runtime compatibility materialization, public facade functions, authenticated `:comms` Routing routes/UI, and spacecraft-scoped Routing page in `:spacecraft_show`.
- Reworked spacecraft readiness so it only summarizes identity, Spacecraft Profile, applications, and a Routing handoff; it no longer claims link assignment or operational comms readiness.
- Reworked Comms validation findings into Spacecraft Setup, Transport Setup, Routing Setup, and Advanced / Runtime Identity groups.
- Removed Providers from the primary Comms sidebar; direct Provider routes remain as internal compatibility UI, and legacy provider/path/link URLs redirect to Transports or Routing.
- Converted primary Profile, Transport, mission Routing, and spacecraft Routing lists to LiveView streams.
- Tightened Contact/runtime Link boundary copy and tests so Link appears only as runtime terminology, not a durable setup noun.
- Cleaned pre-existing strict Credo blockers enough for `mix precommit` to pass: reworded authz TODO comments, fixed one expensive list-length guard, and added targeted suppressions for existing nesting/large-struct debt.

## Tests And Verification

- Focused web tests: `mix test test/cadence_web/live/comms_transport_live_test.exs test/cadence_web/live/comms_routing_live_test.exs test/cadence_web/live/spacecraft_profile_live_test.exs test/cadence_web/live/spacecraft_new_live_test.exs` from `apps/cadence_web`: passed, 18 tests.
- Focused domain tests: `mix test test/cadence/comms/transport_store_test.exs test/cadence/comms/routing_rule_store_test.exs test/cadence/spacecraft_type_store_test.exs test/cadence/spacecraft_store_test.exs` from `apps/cadence`: passed, 14 tests.
- Focused readiness/validation/nav tests: `mix test test/cadence_web/live/comms_live_test.exs test/cadence_web/live/spacecraft_readiness_live_test.exs test/cadence_web/live/spacecraft_show_live_test.exs test/cadence_web/live/mission_show_live_test.exs` from `apps/cadence_web`: passed, 23 tests.
- `mix precommit`: passed.
  - `cadence`: 239 tests, 0 failures.
  - `cadence_simulator`: 66 tests, 0 failures.
  - `cadence_web`: 207 tests, 0 failures.

## Remaining Notes

- No remaining acceptance-criteria gaps found in the final audit.
- Backend modules and database columns still use `SpacecraftType`/`spacecraft_type_id`; this is an intentional temporary bridge.
- Direct Provider routes remain as internal compatibility UI, but they are no longer primary navigation.
