defmodule Cadence.Commanding.CommandPolicyTest do
  use ExUnit.Case, async: true

  alias Cadence.Commanding.CommandPolicy

  defp cmd(id, opts \\ []),
    do: Map.merge(%{command_id: id, name: String.upcase(id)}, Map.new(opts))

  test "a routine command to few targets needs no second GO" do
    assert %{second_go_required: false, reasons: []} =
             CommandPolicy.evaluate([cmd("noop")], 3, fleet_reach_threshold: 10)
  end

  test "hazardous, critical and policy-hint commands each give a keyed reason, once per command" do
    result =
      CommandPolicy.evaluate(
        [
          cmd("pwr", hazardous: true),
          cmd("pwr", hazardous: true),
          cmd("reset", significance: :critical),
          cmd("dump", release_policy_hint: "approval_required"),
          cmd("noop")
        ],
        1,
        fleet_reach_threshold: 10
      )

    assert result.second_go_required

    assert result.reasons == [
             %{key: :hazardous_command, command_id: "pwr", name: "PWR"},
             %{key: :critical_command, command_id: "reset", name: "RESET"},
             %{key: :policy_hint, command_id: "dump", name: "DUMP"}
           ]
  end

  test "reaching the fleet threshold needs a second GO even for routine commands" do
    assert %{
             second_go_required: true,
             reasons: [%{key: :fleet_reach, targets: 10, threshold: 10}]
           } =
             CommandPolicy.evaluate([cmd("noop")], 10, fleet_reach_threshold: 10)

    assert %{second_go_required: false} =
             CommandPolicy.evaluate([cmd("noop")], 9, fleet_reach_threshold: 10)
  end

  test "the default threshold is 10 (DECISIONS #31) and policies expose it" do
    assert CommandPolicy.fleet_reach_threshold() == 10

    assert %{key: :fleet_reach, parameters: %{threshold: 10}} =
             Enum.find(CommandPolicy.policies(), &(&1.key == :fleet_reach))
  end
end
