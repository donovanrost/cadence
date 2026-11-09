# Review · change-set rollback (0cf7747f, f3c2b2df), DECISIONS #49

Reviewer: **domain** (2026-11-09). Author: api. Status: **changes requested** (items 1 and 2).

The planning model is right:
- the earliest `before` in `(target, head]` is the target state;
- each op is the kind's own inverse against current state;
- refusals before r1 and across `legacy_activation` (naming the newest);
- the outside-change HOLD.

The hooks are small and correct: `source` on staged ops, `Preview` appending holds, and
`Submission` labelling `rollback` with `rolls_back_to`. The framing and pin rollbacks produce
generations (tested, alongside 0e5b17d4).

## Must fix

1. **Derived kinds end up in the plan.** `spacecraft_routes` is derived. Its staging validation
   refuses edits ("Routes come from profile rules"), and `write/7` returns `:routes_are_derived`.
   But finalize records its entries in the ledger whenever a profile's routing rules change.
   So any rollback range that touched profile routing plans `spacecraft_routes` ops and comes
   back NO-GO. Skip derived kinds in `inverse_ops`: they're re-derived by finalize after the
   profile is reverted. A small `derived?/0` on the kind, or a list in `Kinds`, is enough. Add a
   test that rolls back a routing-rule edit.
2. **Creates and deletes need dependency order, not just action order.** Within each action,
   kinds come out in `Enum.group_by` map order. A rollback that re-creates a station and a
   transport (or a profile and a spacecraft pinned to it) can stage the dependent first, which
   fails validation against the not-yet-created parent.
   - Creates: ground_station, transport, spacecraft_profile, spacecraft, spacecraft_override.
   - Deletes: the reverse.
   - Updates: same order as creates.

   The `configuration_kinds` registry order isn't a dependency order (spacecraft precedes its
   profile there), so state the order in `Rollback`.

## Should fix

3. **Edits can join the rollback's set later.** `stage/3` refuses when a set is open, but once the
   rollback is the open set, ordinary staging can add changes to it. The revision is then
   labelled `rollback` while it carries unrelated edits. Either refuse staging into a set whose
   changes carry `source.rollback`, or label the revision `change_set` when other changes exist.
4. **The no-open-set check isn't locked.** `no_open_set/1` reads `ChangeSetStore.active/1` without
   a lock, so a concurrent stage can open a set in between and the rollback joins it. Stage
   through the same lock-or-open path with an "empty set only" condition.

## Note

- Update ops replace top-level keys whole (e.g. `frame_parameters`, `routing_rules`). That's fine
  as long as every kind's editing accepts a top-level path with a full value; please confirm
  `spacecraft_override`, whose keys are paths with `/`.
- Spacecraft creations stay NO-GO until the archive model lands (mine, #50 item 4).

## Re-review · ae9b3aff

**Approved.** I checked these in the code:
- derived kinds (`spacecraft_routes`) are skipped, and a routing-rule rollback test was added;
- dependency order is explicit (parents first for creates and updates, children first for
  deletes);
- `Staging.rollback_alone/2` runs under the set lock and refuses other staging while a rollback
  is staged (`:rollback_in_progress`);
- override `/` keys are single top-level keys, so whole-value updates work.

Leaving a profile revert's pure version re-pin to the rollout is correct, since the rollout is
the derived effect.
