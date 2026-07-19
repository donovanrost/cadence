defmodule Cadence.Commanding.VerifierTransportSignals do
  @moduledoc """
  Normalizes transport runtime evidence into command-verifier input signals.
  """

  alias Cadence.Persistence.JsonDocument
  alias Cadence.Runtime.{TransportActionRequest, TransportCapabilityRecord}

  @spec build([TransportCapabilityRecord.t()], [TransportActionRequest.t()]) :: [map()]
  def build(transport_capability_records, transport_action_requests)
      when is_list(transport_capability_records) and is_list(transport_action_requests) do
    capability_signals =
      transport_capability_records
      |> Enum.map(&build_signal/1)
      |> Enum.reject(&is_nil/1)

    action_request_signals =
      transport_action_requests
      |> Enum.map(&build_signal/1)
      |> Enum.reject(&is_nil/1)

    capability_signals ++ action_request_signals
  end

  defp build_signal(%TransportActionRequest{} = transport_action_request) do
    with command_release_attempt_id when is_binary(command_release_attempt_id) <-
           transport_action_request.command_release_attempt_id,
         command_request_id when is_binary(command_request_id) <-
           transport_action_request.command_request_id,
         phase when is_atom(phase) <- transport_action_request.signal_phase do
      %{
        input_kind: :transport,
        mission_id: transport_action_request.mission_id,
        command_release_attempt_id: command_release_attempt_id,
        command_request_id: command_request_id,
        phase: phase,
        occurred_at: transport_action_request.requested_at,
        matched_record_kind: :transport_action_request,
        matched_record_id: transport_action_request.action_request_id,
        subject_values: %{
          "transport:accepted" => phase == :acceptance,
          "transport:started" => phase == :start,
          "transport:completed" => phase == :completion,
          "transport:phase" => Atom.to_string(phase),
          "transport:action_kind" => Atom.to_string(transport_action_request.action_kind),
          "transport:command_release_attempt_id" => command_release_attempt_id,
          "transport:command_request_id" => command_request_id,
          "transport:source_endpoint_ref" => transport_action_request.source_endpoint_ref,
          "transport:command_name" => transport_action_request.command_name,
          "transport:path_id" => transport_action_request.path_id,
          "transport:realized_contact_id" => transport_action_request.realized_contact_id,
          "transport:family_key" => Atom.to_string(transport_action_request.family_key)
        }
      }
    else
      _other -> nil
    end
  end

  defp build_signal(%TransportCapabilityRecord{} = transport_capability_record) do
    state_snapshot = unwrap_document(transport_capability_record.state_snapshot)
    metadata = unwrap_document(transport_capability_record.metadata)

    with phase when is_atom(phase) <- signal_phase(transport_capability_record, metadata),
         command_release_attempt_id when is_binary(command_release_attempt_id) <-
           command_release_attempt_id(state_snapshot, metadata),
         command_request_id when is_binary(command_request_id) <-
           command_request_id(state_snapshot, metadata) do
      %{
        input_kind: :transport,
        mission_id: transport_capability_record.mission_id,
        command_release_attempt_id: command_release_attempt_id,
        command_request_id: command_request_id,
        phase: phase,
        occurred_at: transport_capability_record.recorded_at,
        matched_record_kind: :transport_capability_record,
        matched_record_id: transport_capability_record.transport_record_id,
        subject_values: %{
          "transport:accepted" => phase == :acceptance,
          "transport:started" => phase == :start,
          "transport:completed" => phase == :completion,
          "transport:phase" => Atom.to_string(phase),
          "transport:event_kind" => Atom.to_string(transport_capability_record.event_kind),
          "transport:command_release_attempt_id" => command_release_attempt_id,
          "transport:command_request_id" => command_request_id,
          "transport:command_name" => command_name(state_snapshot, metadata),
          "transport:path_id" => transport_capability_record.path_id,
          "transport:realized_contact_id" => transport_capability_record.realized_contact_id,
          "transport:family_key" => Atom.to_string(transport_capability_record.family_key)
        }
      }
    else
      _other -> nil
    end
  end

  defp signal_phase(%TransportCapabilityRecord{} = record, metadata) when is_map(metadata) do
    metadata_phase =
      metadata[:signal_phase] ||
        metadata["signal_phase"] ||
        metadata[:verifier_phase] ||
        metadata["verifier_phase"]

    cond do
      is_atom(metadata_phase) ->
        metadata_phase

      is_binary(metadata_phase) ->
        String.to_existing_atom(metadata_phase)

      record.family_key == :uplink_gateway and record.event_kind == :control_input_handled ->
        :acceptance

      true ->
        nil
    end
  rescue
    ArgumentError -> nil
  end

  defp command_release_attempt_id(state_snapshot, metadata)
       when is_map(state_snapshot) and is_map(metadata) do
    state_snapshot[:last_release_attempt_id] ||
      state_snapshot["last_release_attempt_id"] ||
      metadata[:command_release_attempt_id] ||
      metadata["command_release_attempt_id"]
  end

  defp command_request_id(state_snapshot, metadata)
       when is_map(state_snapshot) and is_map(metadata) do
    state_snapshot[:last_command_request_id] ||
      state_snapshot["last_command_request_id"] ||
      metadata[:command_request_id] ||
      metadata["command_request_id"]
  end

  defp command_name(state_snapshot, metadata)
       when is_map(state_snapshot) and is_map(metadata) do
    state_snapshot[:last_command_name] ||
      state_snapshot["last_command_name"] ||
      metadata[:command_name] ||
      metadata["command_name"]
  end

  defp unwrap_document(%{} = document), do: JsonDocument.unwrap_value(document)
  defp unwrap_document(document), do: document
end
