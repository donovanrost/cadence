# Director review: change-sets.md + profile-routing.md (draft 1)

**Approved to build P1** (user sign-off 2026-11-08). Fold the notes below into draft 2 as you go.

## Answers (user-confirmed)
1. **Freeze while in review.** One shared set per mission; staging is blocked while it's in review. Revisit later if it slows teams down.
2. **Reviewer distinct from every author** in the set, not just the submitter.
3. **Profile limits: out** this phase (read-only with an honest note). **VC/FEC/randomizer framing: out** (not in the pipeline).

## Review notes (address in draft 2 / P1)
1. **Sandbox side effects.** "Real apply inside a rolled-back transaction" only works if nothing inside
   the sandbox leaves the DB: no PubSub broadcasts, GenServer/registry calls, OperationalEvent emitters
   that publish, telemetry exporters, or `Task`s spawned from `kind.apply`. Make it a rule of the
   `ConfigKind` contract (apply returns Multi ops only; all publishing happens in the after-commit tail),
   and add a test that runs `preview` with PubSub subscribed and asserts no messages arrive.
2. **Preview must not take the apply locks.** No mission advisory lock / `mission_config_heads FOR UPDATE`
   in preview, or a slow preview blocks real applies. Put a statement timeout on preview transactions.
3. **Fleet snapshot cap.** change-sets §1 notes the binding-set fleet snapshot caps at 500 SC / 4 MiB.
   The demo constellation is 550 after Block 2 (AddSpacecraft board). Apply composes the full fleet
   snapshot, so check that the first 50-spacecraft batch doesn't hit the cap. Either lift or restructure
   the cap in P1, or state the limit and the plan for it.
4. **`apply_now` for legacy writers is P3, but legacy writers mutate tables in P1/P2.** Conflict detection
   by value (§5) covers correctness. Make sure the UI can say "changed outside a change set" so
   operators aren't confused by unexplained conflicts. (`changed_in: :outside` already supports it.)
5. **Rollback across a legacy activation:** confirm `inverse` works for entries derived from
   `legacy_activation` snapshot diffs, or document that rollback stops at the first legacy revision.
6. **Facade contract:** once draft 2 settles, put the final function list + shapes in
   `docs/apogee/api/domain.md` and ping api + fe-setup.
