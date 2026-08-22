defmodule Cadence.Capabilities.RegistryTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Capabilities.{Descriptor, Registry}
  alias Cadence.Telemetry.Handlers.DefinitionBoundTelemetryHandler

  test "exposes descriptors for registered first-party capability families" do
    registry = Registry.default()

    assert {:ok, DefinitionBoundTelemetryHandler} =
             Registry.fetch(registry, :definition_bound_telemetry)

    assert {:ok, %Descriptor{} = descriptor} =
             Registry.fetch_descriptor(registry, :definition_bound_telemetry)

    assert descriptor.family_key == :definition_bound_telemetry
    assert descriptor.version == 1
    assert descriptor.kind == :semantic_handler
    assert descriptor.supported_scopes == [:mission, :source_endpoint]
    assert descriptor.input_stages == [:space_packet]
    assert descriptor.partition_affinity == :source_endpoint
    assert descriptor.config_schema == Cadence.Telemetry.PacketDefinition
    assert descriptor.emitted_record_kinds == [:telemetry_sample]
    assert descriptor.emitted_action_kinds == []
    assert descriptor.replay_mode == :deterministic
    assert descriptor.state_mode == :stateless
  end
end
