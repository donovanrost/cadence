# Review: repair chain (qa #30)

Commits `096e088d`, `80d81b1f`, `40f9e285`, `cb54761f` (api). Reviewed by domain against the
model call (chain, head, lost/replaced, persisted pairing, chain-level repairability).

**Verdict: approved, with R1 and R2 to fix and R3 to answer.** R4 is a follow-up.

The model is implemented as decided:
- the chain runs from the root plus applied repairs, and repairs start from the head;
- locks are the live items across the chain;
- lost means rejected, failed after placement, or `operator_not_booked` (#53 fits);
- the pairing is persisted on the repair run, and a lost replacement stands for the need;
- repairability is decided per chain.

Tests pass (fleet_planner, repair_diff, passes, plus booking_resolutions and
contact_plan_executions), and the architecture check is green.

## R1: pairing can bind a new pass to the wrong lost booking (fix)

`RepairPairing.pair/2` zips each spacecraft's new passes and lost bookings in time order. Two
cases go wrong:
- **Counts differ.** A spacecraft lost 10:00 and 22:00, and the repair adds only 21:50 (the
  10:00 need was dropped or covered). 21:50 pairs with 10:00. The 22:00 booking then reads
  lost and unreplaced, and the passes read shows `replaced_by` on the wrong row.
- **Unrelated demand.** `fresh` is every unlocked selected pass, including passes for demand
  that was never lost (newly unmet requirements), and those can claim a lost booking.

Fix: pair within the same `contact_requirement_id` first (snapshots carry it), then by nearest
`starts_at`, greedily, and leave the remainder unpaired. Add a test with unequal counts.

## R2: backfill aborts on the first bad link, and nothing runs it (fix)

The `for` in `RepairChain.backfill/2` uses `{:ok, chain} = load(...)`,
`{:ok, version} = fetch_version(...)` and `:ok = put_replaces(...)`. A failed match raises
`MatchError` and stops the whole backfill. Use generator filters
(`{:ok, chain} <- [load(...)]`) so a bad link is skipped, and return the skipped ids. Also:
nothing calls it. Say how it's run (an RPC one-off on :4011? a mix task?) in `scheduling.md`,
and run it once on cadence_apogee_dev for 8ae6517e.

## R3: `version.locked_snapshot_ids` no longer locks (question)

The old `source_locked_commitments` locked the source version's `locked_snapshot_ids` and its
live items. The new one locks only live items across the chain. If a plan version can lock a
snapshot that has no live item (a reviewed commitment not yet executed, or one an operator
pinned), a repair can now move it. Was dropping that intended? If so, add a line to the
moduledoc; if not, keep the version's locked ids.

## R4: single bookings aren't in the chain (follow-up)

A pass booked through `actions/reserve` (qa's 004 Kiruna rebook) covers a lost need, but it
isn't a plan item. So the chain still lists the need as lost, and a repair may book it a second
time. Options:
- (a) The repair also locks the mission's live reservations in its horizon that belong to no
  plan, and they can pair with lost bookings.
- (b) A single booking that overlaps a lost booking's window for the same spacecraft records
  itself as that booking's replacement.

(a) is simpler and covers bookings made anywhere. This needs a director call; not blocking.
