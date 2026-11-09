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

    assert %{result: :hold, per_target: [%{next_contact: nil, result: :hold}, _]} =
             result(preflight.checks, :contact)

    assert %{evidence: %{max_targets: 1_000, max_commands: 16, max_members: 5_000}} =
             result(preflight.checks, :size)

    refute Enum.any?(preflight.checks, &(&1.key in [:plan_impact, :umbra_margin]))
  end

  test "hazardous commands HOLD for a second GO with keyed reasons", c do
    {:ok, preflight} = run(c, draft(c.spacecraft, [command(c, "SET_COUNTER", %{"amount" => 2})]))

    assert %{result: :hold, evidence: %{reasons: [%{key: :hazardous_command}]}} =
             result(preflight.checks, :two_person)
  end

  test "work already on the lanes is a conflicts HOLD", c do
    draft = draft(c.spacecraft, [command(c, "SET_SIGNED", %{"counter" => 1})])

    {:ok, _group} =
      GroupSubmission.submit(c.scope, c.mission, draft, preflight_digest: digest(c, draft))

    {:ok, preflight} = run(c, draft)
    assert %{result: :hold, evidence: %{count: 2}} = result(preflight.checks, :conflicts)
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
