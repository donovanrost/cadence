defmodule Cadence.Applications.MissionBindingComposerTest do
  use Cadence.DataCase, async: false

  alias Cadence.ApplicationDispatch.{BindingRule, CapabilityInstance}
  alias Cadence.Applications.{MissionBindingComposer, MissionBindingContribution}

  @organization_id "org-mission-binding-composer"
  @mission_id "mission-binding-composer"

  setup do
    persist_mission_scope(@organization_id, @mission_id)
    :ok
  end

  test "builds one deterministically ordered application-neutral mission basis" do
    contribution = contribution("telemetry_decom", "instance-z", "rule-z", 42)
    observer = contribution("packet_observer", "instance-a", "rule-a", 42)

    assert {:ok, binding_set} =
             MissionBindingComposer.compose(
               @organization_id,
               @mission_id,
               [contribution, observer]
             )

    assert binding_set.binding_set_id == "mission_applications:#{@mission_id}"
    assert binding_set.version == 1

    assert Enum.map(binding_set.capability_instances, & &1.capability_instance_id) == [
             "instance-a",
             "instance-z"
           ]

    assert Enum.map(binding_set.rules, & &1.binding_rule_id) == ["rule-a", "rule-z"]
    assert Enum.all?(binding_set.rules, &(&1.selector.match.apid == 42))
  end

  test "rejects duplicate runtime identities across application contributions" do
    first = contribution("first", "shared-instance", "first-rule", 42)
    second = contribution("second", "shared-instance", "second-rule", 42)

    assert {:error, :duplicate_mission_capability_instance} =
             MissionBindingComposer.compose(
               @organization_id,
               @mission_id,
               [first, second]
             )
  end

  defp contribution(application_key, capability_instance_id, binding_rule_id, apid) do
    instance =
      CapabilityInstance.new(%{
        capability_instance_id: capability_instance_id,
        family_key: :packet_counter,
        target_scope: :mission,
        runtime_configuration: %{"metric_name" => application_key}
      })

    rule =
      BindingRule.new(%{
        binding_rule_id: binding_rule_id,
        capability_instance_id: capability_instance_id,
        selector: %{
          scope: %{target_scope: :mission},
          match: %{packet_kind: :space_packet, apid: apid}
        },
        fanout_mode: :multi
      })

    %MissionBindingContribution{
      contribution_id: application_key,
      application_key: application_key,
      capability_instances: [instance],
      rules: [rule]
    }
  end
end
