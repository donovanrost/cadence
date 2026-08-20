defmodule Cadence.ActivationsTest do
  use Cadence.RuntimeCase, async: false

  alias Cadence.Activations.Facts, as: ActivationFacts
  alias Cadence.ApplicationDispatch.{BindingRule, BindingSet}
  alias Cadence.Platform.EventBus
  alias Cadence.Runtime
  alias Cadence.Runtime.MissionRuntimeSpec
  alias Cadence.Runtime.Missions, as: RuntimeMissions
  alias Cadence.Telemetry.PacketDefinition

  @organization_id "org-alpha"

  test "activates a persisted binding set and resolves it as the active mission basis" do
    persist_mission_scope(@organization_id, "mission-activation-alpha")
    binding_set = persisted_binding_set("mission-activation-alpha", 1, "HK")
    event_bus = start_event_bus()
    assert :ok = ActivationFacts.subscribe(event_bus, self())

    on_exit(fn ->
      Runtime.stop_mission(binding_set.mission_id)
    end)

    assert {:error, :no_active_binding_set} =
             Cadence.Activations.fetch_active_activation(
               @organization_id,
               binding_set.mission_id
             )

    assert {:ok, activation} =
             Cadence.ActivationFixtures.activate_binding_set(
               @organization_id,
               binding_set.mission_id,
               binding_set.binding_set_id,
               binding_set.version,
               metadata: %{reason: "initial bootstrap"},
               event_bus: event_bus
             )

    assert_receive {:"$gen_cast", {:cadence_fact, {:cadence, :activations, :facts}, ^activation}}

    assert activation.mission_id == binding_set.mission_id
    assert activation.binding_set_id == binding_set.binding_set_id
    assert activation.binding_set_version == binding_set.version
    assert activation.generation == 1

    assert activation.binding_set_content_sha256 ==
             MissionRuntimeSpec.content_sha256(binding_set)

    assert activation.metadata["reason"] == "initial bootstrap"

    assert {:ok, active_activation} =
             Cadence.Activations.fetch_active_activation(
               @organization_id,
               binding_set.mission_id
             )

    assert active_activation.activation_id == activation.activation_id

    assert {:ok, active_binding_set} =
             Cadence.Activations.fetch_active_binding_set(
               @organization_id,
               binding_set.mission_id
             )

    assert active_binding_set.binding_set_id == binding_set.binding_set_id
    assert active_binding_set.version == binding_set.version

    assert {:ok, runtime_spec} = RuntimeMissions.applied_spec(binding_set.mission_id)
    assert runtime_spec.generation == activation.generation
    assert runtime_spec.binding_set == binding_set

    assert {:ok, next_activation} =
             Cadence.ActivationFixtures.activate_binding_set(
               @organization_id,
               binding_set.mission_id,
               binding_set.binding_set_id,
               binding_set.version,
               []
             )

    assert next_activation.generation == 2
    assert {:ok, next_runtime_spec} = RuntimeMissions.applied_spec(binding_set.mission_id)
    assert next_runtime_spec.generation == 2
  end

  defp persisted_binding_set(mission_id, version, packet_name) do
    packet_definition =
      PacketDefinition.new(%{
        organization_id: @organization_id,
        mission_id: mission_id,
        packet_definition_id: packet_name <> "-packet",
        packet_name: packet_name,
        apid: 42,
        version: version,
        fields: [
          %{field_id: "counter", name: "counter", offset_bits: 0, size_bits: 16, data_type: :uint}
        ]
      })

    binding_set =
      BindingSet.new(%{
        organization_id: @organization_id,
        mission_id: mission_id,
        binding_set_id: "default-runtime-basis",
        version: version,
        rules: [
          BindingRule.new(%{
            binding_rule_id: "telemetry-rule-v" <> Integer.to_string(version),
            handler_key: :definition_bound_telemetry,
            packet_kind: :space_packet,
            apid: 42,
            priority: 10,
            handler_configuration: packet_definition
          })
        ]
      })

    assert {:ok, ^binding_set} =
             Cadence.Governance.persist_binding_set(@organization_id, binding_set)

    binding_set
  end

  defp start_event_bus do
    start_supervised!(%{
      id: {:activation_fact_event_bus, make_ref()},
      start: {EventBus, :start_link, [[name: nil, delivery: :async, before_notify: nil]]},
      restart: :temporary
    })
  end
end
