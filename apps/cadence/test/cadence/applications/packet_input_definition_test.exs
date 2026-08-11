defmodule Cadence.Applications.PacketInputDefinitionTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Applications.PacketInputDefinition
  alias Cadence.Capabilities.Definitions.DefinitionBoundTelemetry

  test "declares a bounded, isolated compatible-field input for Telemetry Decom" do
    descriptor = DefinitionBoundTelemetry.descriptor()

    assert [input] = descriptor.packet_inputs
    assert input.input_id == "telemetry-fields"
    assert input.selection_mode == :compatible_fields
    assert input.accepted_resource_kinds == [:field]
    assert input.accepted_data_types == [:uint, :int, :float, :bool]
    assert input.failure_policy == :isolated
    assert :ok = PacketInputDefinition.validate(input)
  end

  test "rejects semantically incompatible selection modes and unbounded cardinality" do
    base = %PacketInputDefinition{
      input_id: "whole-packet",
      version: 1,
      capability_family_key: :definition_bound_telemetry,
      accepted_resource_kinds: [:whole_packet],
      accepted_data_types: [],
      selection_mode: :whole_packet,
      min_selected: 1,
      max_selected: 32,
      delivery: :packet_record,
      failure_policy: :isolated
    }

    assert :ok = PacketInputDefinition.validate(base)

    assert {:error, :invalid_packet_input_definition} =
             PacketInputDefinition.validate(%{
               base
               | accepted_resource_kinds: [:field],
                 max_selected: 10_000
             })
  end
end
