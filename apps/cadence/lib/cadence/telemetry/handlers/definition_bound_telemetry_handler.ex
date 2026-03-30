defmodule Cadence.Telemetry.Handlers.DefinitionBoundTelemetryHandler do
  @moduledoc """
  Telemetry application handler backed by a governed packet definition.
  """

  @behaviour Cadence.ApplicationDispatch.Handler
  @behaviour Cadence.Capabilities.Family

  alias Cadence.ApplicationDispatch.WorkItem
  alias Cadence.Capabilities.{Descriptor, ValidationContext}
  alias Cadence.Ids
  alias Cadence.Protocol.PacketRecord
  alias Cadence.Telemetry.{Extractor, PacketDefinition, Sample}

  @impl true
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

  @impl true
  def handler_key, do: :definition_bound_telemetry

  @impl true
  def validate_config(nil, %ValidationContext{}), do: {:error, :missing_packet_definition}

  def validate_config(
        %PacketDefinition{} = packet_definition,
        %ValidationContext{} = validation_context
      ) do
    with :ok <- validate_definition_mission(packet_definition, validation_context.mission_id),
         :ok <- validate_definition_apid(packet_definition, validation_context) do
      :ok
    end
  end

  def validate_config(configuration, %ValidationContext{}) do
    {:error, {:unsupported_handler_configuration, configuration}}
  end

  @impl true
  def build_instance(%PacketDefinition{} = packet_definition, _activation_context),
    do: {:ok, packet_definition}

  def build_instance(nil, _activation_context), do: {:error, :missing_packet_definition}

  def build_instance(configuration, _activation_context),
    do: {:error, {:unsupported_handler_configuration, configuration}}

  @impl true
  def handle(%PacketRecord{} = packet_record, %WorkItem{} = work_item) do
    with %PacketDefinition{} = packet_definition <- work_item.handler_configuration,
         :ok <- validate_mission(packet_record, packet_definition),
         :ok <- validate_apid(packet_record, packet_definition),
         {:ok, extracted_fields} <-
           Extractor.extract(packet_record.packet_data, packet_definition) do
      {:ok,
       Enum.map(extracted_fields, &to_sample(&1, packet_record, packet_definition, work_item))}
    else
      nil -> {:error, :missing_packet_definition}
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_apid(%PacketRecord{apid: apid}, %PacketDefinition{apid: apid}), do: :ok

  defp validate_apid(%PacketRecord{apid: packet_apid}, %PacketDefinition{apid: definition_apid}) do
    {:error, {:apid_mismatch, packet_apid, definition_apid}}
  end

  defp validate_mission(%PacketRecord{mission_id: mission_id}, %PacketDefinition{
         mission_id: mission_id
       }),
       do: :ok

  defp validate_mission(
         %PacketRecord{mission_id: packet_mission_id},
         %PacketDefinition{mission_id: definition_mission_id}
       ) do
    {:error, {:mission_mismatch, packet_mission_id, definition_mission_id}}
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

  defp to_sample({field_definition, raw_value}, packet_record, packet_definition, work_item) do
    point_name = packet_definition.packet_name <> "." <> field_definition.name

    %Sample{
      sample_id: Ids.new("sample"),
      mission_id: packet_record.mission_id,
      spacecraft_id: packet_record.spacecraft_id,
      point_id: point_name,
      point_name: point_name,
      packet_definition_id: packet_definition.packet_definition_id,
      packet_definition_version: packet_definition.version,
      packet_id: packet_record.packet_id,
      evidence_id: packet_record.evidence_id,
      raw_value: raw_value,
      engineering_value: raw_value,
      quality_state: :good,
      generation_time: packet_record.source_time,
      receipt_time: packet_record.receipt_time,
      provenance: %{
        evidence_id: packet_record.evidence_id,
        packet_id: packet_record.packet_id,
        binding_rule_id: work_item.binding_rule_id
      }
    }
  end
end
