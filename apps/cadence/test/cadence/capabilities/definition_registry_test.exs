defmodule Cadence.Capabilities.DefinitionRegistryTest do
  use Cadence.UnitCase, async: true

  alias Cadence.ApplicationDispatch.CapabilityInstance
  alias Cadence.Capabilities.{DefinitionRegistry, Registry, ValidationContext}
  alias Cadence.Capabilities.Definitions.DefinitionBoundTelemetry

  test "registers definitions without exposing executable runtime handlers" do
    definitions = DefinitionRegistry.default()

    assert {:ok, DefinitionBoundTelemetry} =
             DefinitionRegistry.fetch(definitions, :definition_bound_telemetry)

    runtime_registry = Registry.default()

    for family_key <- Map.keys(definitions) do
      assert {:ok, definition_descriptor} =
               DefinitionRegistry.fetch_descriptor(definitions, family_key)

      assert {:ok, runtime_descriptor} =
               Registry.fetch_descriptor(runtime_registry, family_key)

      assert definition_descriptor == runtime_descriptor
    end
  end

  test "validates governed configuration without loading the runtime registry" do
    capability_instance =
      CapabilityInstance.new(%{
        capability_instance_id: "packet-counter",
        family_key: :packet_counter,
        target_scope: :mission,
        runtime_configuration: %{
          "metric_name" => "packet_window",
          "flush_interval_ms" => 25
        }
      })

    validation_context =
      ValidationContext.new(%{
        mission_id: "mission-alpha",
        target_scope: :mission
      })

    assert :ok =
             DefinitionRegistry.validate_capability_instance(
               DefinitionRegistry.default(),
               capability_instance,
               validation_context
             )
  end
end
