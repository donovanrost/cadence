defmodule Cadence.Reads.CommandPreflight.VerifierGroupsTest do
  @moduledoc """
  U51: a stacked command's targets grouped by the verifiers their pinned revision gives it
  (compared without ids), largest group first; a target with no verifier is its own group.
  Plus domain's fix: the group's policy takes the strictest classification across targets.
  """
  use ExUnit.Case, async: true

  alias Cadence.Catalog.Command.Compiler.VerifierPlan
  alias Cadence.Commanding.Groups.Validation
  alias Cadence.Reads.CommandPreflight.VerifierGroups

  defp plan(id, name, timeout_ms) do
    VerifierPlan.new(%{
      command_id: "set-mode",
      verifier_id: id,
      name: name,
      phase: :completion,
      timeout_ms: timeout_ms
    })
  end

  # Revision 3 and 4 give the same two verifiers different ids; 4 adds 'Mode applied'.
  defp rev3,
    do: [plan("v3-a", "Uplink started", 30_000), plan("v3-b", "Accepted on board", 30_000)]

  defp rev4,
    do: [
      plan("v4-a", "Uplink started", 30_000),
      plan("v4-b", "Accepted on board", 30_000),
      plan("v4-c", "Mode applied", 60_000)
    ]

  defp member(index, plans),
    do: %{
      target_index: index,
      position: 0,
      request: %{command_id: "set-mode", mission_model_revision_id: "mm-#{index}"},
      verifier_plans: plans
    }

  test "targets group by verifier set, ids ignored, largest first" do
    targets = Map.new(0..3, &{&1, %{spacecraft_id: "sc-00#{&1}"}})
    revisions = %{0 => %{number: 4, label: "Revision 4"}, 1 => %{number: 3, label: "Revision 3"}}
    revisions = Map.merge(revisions, %{2 => revisions[1], 3 => %{number: 2, label: "Revision 2"}})

    members = [
      member(0, rev4()),
      member(1, rev3()),
      member(2, Enum.reverse(rev3())),
      member(3, rev3())
    ]

    assert [%{position: 0, command_id: "set-mode", verifier_groups: [big, small]}] =
             VerifierGroups.commands([%{command_id: "set-mode"}], members, targets, revisions)

    assert big.spacecraft_ids == ["sc-001", "sc-002", "sc-003"]

    assert big.catalog_revisions == [
             %{number: 2, label: "Revision 2"},
             %{number: 3, label: "Revision 3"}
           ]

    assert Enum.map(big.verifiers, & &1.name) |> Enum.sort() == [
             "Accepted on board",
             "Uplink started"
           ]

    assert small.spacecraft_ids == ["sc-000"]
    assert small.catalog_revisions == [%{number: 4, label: "Revision 4"}]
    assert "Mode applied" in Enum.map(small.verifiers, & &1.name)
  end

  test "a target with no verifier is its own group; a command with no member has none" do
    targets = %{0 => %{spacecraft_id: "sc-a"}, 1 => %{spacecraft_id: "sc-b"}}

    assert [%{verifier_groups: groups}, %{verifier_groups: []}] =
             VerifierGroups.commands(
               [%{command_id: "set-mode"}, %{command_id: "noop"}],
               [member(0, rev3()), member(1, [])],
               targets,
               %{}
             )

    assert Enum.map(groups, &{&1.spacecraft_ids, length(&1.verifiers)}) == [
             {["sc-a"], 2},
             {["sc-b"], 0}
           ]
  end

  test "the policy takes the strictest classification across targets, not the first" do
    snapshot = %{catalog: %{operational_bindings: []}}

    members = [
      %{request: %{command_id: "set-mode", command_name: "SET_MODE", significance: :routine}},
      %{
        request: %{
          command_id: "set-mode",
          significance: :hazardous,
          critical: true,
          release_policy_hint: "approval_required"
        }
      }
    ]

    assert [
             %{
               command_id: "set-mode",
               name: "SET_MODE",
               significance: :hazardous,
               critical: true,
               hazardous: false,
               release_policy_hint: "approval_required"
             }
           ] = Validation.policy_commands([%{command_id: "set-mode"}], members, snapshot)
  end
end
