defmodule Cadence.Capabilities.Definitions.DefinitionBoundTelemetry do
  @moduledoc false

  alias Cadence.Capabilities.{Descriptor, ValidationContext}
  alias Cadence.Telemetry.PacketDefinition

  @spec descriptor() :: Descriptor.t()
  def descriptor do
    Descriptor.new(%{
      family_key: :definition_bound_telemetry,
      kind: :semantic_handler,
      supported_scopes: [:mission, :source_endpoint],
      input_stages: [:space_packet],
      partition_affinity: :source_endpoint,
      config_schema: PacketDefinition,
      emitted_record_kinds: [:telemetry_sample],
      emitted_action_kinds: [],
      replay_mode: :deterministic,
      state_mode: :stateless
    })
  end

  @spec validate_config(term(), ValidationContext.t()) :: :ok | {:error, term()}
  def validate_config(nil, %ValidationContext{}), do: {:error, :missing_packet_definition}

  def validate_config(
        %PacketDefinition{} = packet_definition,
        %ValidationContext{} = validation_context
      ) do
    with :ok <- validate_definition_mission(packet_definition, validation_context.mission_id) do
      validate_definition_apid(packet_definition, validation_context)
    end
  end

  def validate_config(configuration, %ValidationContext{}) do
    {:error, {:unsupported_handler_configuration, configuration}}
  end

  defp validate_definition_mission(%PacketDefinition{mission_id: mission_id}, mission_id), do: :ok

  defp validate_definition_mission(
         %PacketDefinition{mission_id: definition_mission_id},
         mission_id
       ) do
    {:error, {:packet_definition_mission_mismatch, definition_mission_id, mission_id}}
  end

  defp validate_definition_apid(%PacketDefinition{}, %ValidationContext{metadata: metadata})
       when metadata == %{},
       do: :ok

  defp validate_definition_apid(%PacketDefinition{} = packet_definition, %ValidationContext{
         metadata: metadata
       }) do
    case Map.get(metadata, :apid, Map.get(metadata, "apid")) do
      nil ->
        :ok

      apid when apid == packet_definition.apid ->
        :ok

      binding_rule_apid ->
        {:error, {:binding_rule_apid_mismatch, binding_rule_apid, packet_definition.apid}}
    end
  end
end
