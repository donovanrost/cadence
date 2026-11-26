defmodule Cadence.Reads.CommandPreflightTest do
  use Cadence.DataCase, async: false

  import Cadence.CommandGroupFixtures

  alias Cadence.Control.Commanding.GroupSubmission
  alias Cadence.Reads.CommandPreflight

  setup do
    setup!(2)
  end

  defp run(c, draft), do: CommandPreflight.run(c.org, c.mission, actor(c), draft)
  defp result(checks, key), do: Enum.find(checks, &(&1.key == key))

  test "a routine draft is GO everywhere it can be; no booked contact is a HOLD per target", c do
    assert {:ok, preflight} =
             run(c, draft(c.spacecraft, [command(c, "SET_SIGNED", %{"counter" => 1})]))

    assert preflight.valid?
    assert is_binary(preflight.digest)

    assert preflight.digest ==
             digest(c, draft(c.spacecraft, [command(c, "SET_SIGNED", %{"counter" => 1})]))

    for key <- [:identity, :catalog, :size, :conflicts, :two_person],
        do: assert(%{result: :go} = result(preflight.checks, key))

    # No commandable contact is a hard HOLD (DECISIONS #60).
    assert %{
             result: :hold,
             ackable: false,
             hold_basis: basis,
             per_target: [%{next_contact: nil, result: :hold, reason: :no_commandable_contact}, _]
           } = result(preflight.checks, :contact)

    assert is_binary(basis)
    assert %{ackable: nil, hold_basis: nil} = result(preflight.checks, :identity)

    assert %{evidence: %{max_targets: 5_000, max_commands: 16, max_members: 20_000}} =
             result(preflight.checks, :size)

    refute Enum.any?(preflight.checks, &(&1.key in [:plan_impact, :umbra_margin]))
  end

  test "hazardous commands need a second GO, which isn't a HOLD (#60/#61)", c do
    {:ok, preflight} = run(c, draft(c.spacecraft, [command(c, "SET_COUNTER", %{"amount" => 2})]))

    assert %{result: :second_go, ackable: nil, evidence: %{reasons: [%{key: :hazardous_command}]}} =
             result(preflight.checks, :two_person)

    assert preflight.policy.second_go_required
  end

  test "the contact window starts at not_before and needs a confirmed uplink (qa #35)", c do
    [sc1, sc2] = c.spacecraft
    not_before = DateTime.add(DateTime.utc_now(), 8 * 3_600)

    # sc1: a commandable pass 9 minutes after not_before, beyond the old now + 6 h horizon.
    commandable_pass!(c.org, c.mission, sc1, DateTime.add(not_before, 540))
    # sc2: a pass that ends before not_before can't carry the release.
    commandable_pass!(c.org, c.mission, sc2, DateTime.add(not_before, -3_600))

    stack = [command(c, "SET_SIGNED", %{"counter" => 1})]
    {:ok, preflight} = run(c, draft(c.spacecraft, stack, %{not_before: not_before}))

    assert %{result: :hold, per_target: per_target} = result(preflight.checks, :contact)
    by_id = Map.new(per_target, &{&1.spacecraft_id, &1})
    assert %{result: :go, next_contact: %{aos: _}} = by_id[sc1]
    assert %{result: :hold, reason: :no_commandable_contact} = by_id[sc2]
  end

  test "holds/2 accepts an ack only for a current ackable HOLD with the same basis", c do
    draft = draft(c.spacecraft, [command(c, "SET_SIGNED", %{"counter" => 1})])
    Enum.each(c.spacecraft, &commandable_pass!(c.org, c.mission, &1))

    {:ok, _group} =
      GroupSubmission.submit(c.scope, c.mission, draft, preflight_digest: digest(c, draft))

    {:ok, preflight} = run(c, draft)
    %{hold_basis: basis} = result(preflight.checks, :conflicts)

    assert %{unsatisfied: [%{key: :conflicts, ackable: true}], accepted: []} =
             CommandPreflight.holds(preflight, [])

    assert %{unsatisfied: [%{key: :conflicts}]} =
             CommandPreflight.holds(preflight, [%{key: "conflicts", hold_basis: "old", note: "x"}])

    assert %{unsatisfied: [], accepted: [%{key: "conflicts", note: "x", evidence: %{count: 2}}]} =
             CommandPreflight.holds(preflight, [%{key: "conflicts", hold_basis: basis, note: "x"}])

    # More work on the lanes changes the HOLD's facts, so the old ack no longer counts.
    {:ok, _another} =
      GroupSubmission.submit(c.scope, c.mission, draft, preflight_digest: digest(c, draft))

    {:ok, changed} = run(c, draft)

    assert %{unsatisfied: [%{key: :conflicts}]} =
             CommandPreflight.holds(changed, [%{key: "conflicts", hold_basis: basis, note: "x"}])
  end

  test "work already on the lanes is a conflicts HOLD", c do
    draft = draft(c.spacecraft, [command(c, "SET_SIGNED", %{"counter" => 1})])

    {:ok, _group} =
      GroupSubmission.submit(c.scope, c.mission, draft, preflight_digest: digest(c, draft))

    {:ok, preflight} = run(c, draft)

    assert %{result: :hold, ackable: true, evidence: %{count: 2}} =
             result(preflight.checks, :conflicts)
  end

  test "unknown targets are NO-GO and oversize drafts report the bounds", c do
    {:ok, preflight} = run(c, draft(["nobody"], [command(c, "SET_SIGNED", %{"counter" => 1})]))
    refute preflight.valid?

    assert %{
             result: :no_go,
             per_target: [%{spacecraft_id: "nobody", reason: :source_endpoint_not_found}]
           } =
             result(preflight.checks, :identity)

    commands = for _ <- 1..17, do: command(c, "SET_SIGNED", %{"counter" => 1})
    {:ok, oversize} = run(c, draft(c.spacecraft, commands))

    assert [%{key: :size, result: :no_go, evidence: %{max_commands: 16, commands: 17}}] =
             oversize.checks
  end

  test "review leaves the group's own members out of conflicts", c do
    draft = draft(c.spacecraft, [command(c, "SET_COUNTER", %{"amount" => 2})], %{log_entry: "x"})

    {:ok, group} =
      GroupSubmission.submit(c.scope, c.mission, draft, preflight_digest: digest(c, draft))

    {:ok, review} = CommandPreflight.review(c.org, c.mission, group)
    assert %{result: :go, evidence: %{count: 0}} = result(review.checks, :conflicts)
    assert %{result: :go} = result(review.checks, :changed_since_submit)

    # A fresh draft on the same targets still sees them.
    {:ok, other} = run(c, draft)
    assert %{result: :hold, evidence: %{count: 2}} = result(other.checks, :conflicts)
  end
end
