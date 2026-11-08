defmodule Cadence.Runtime.Commanding do
  @moduledoc """
  Data-plane boundary for command encoding and live transmission.
  """

  alias Cadence.ActionRequests.UplinkRequest
  alias Cadence.Commanding.Encoder

  alias Cadence.Runtime.{
    MissionRuntime,
    PathCoordinator,
    ProcessNamespace,
    TransmitCommand,
    TransportRuntime,
    UplinkAdmission
  }

  @spec encode(term(), map()) :: {:ok, map()} | {:error, term()}
  def encode(immutable_runtime_definition, resolved_argument_values)
      when is_map(resolved_argument_values) do
    Encoder.encode(immutable_runtime_definition, resolved_argument_values)
  end

  @doc "Admits the exact transport and session before a durable release claim is created."
  def admit(mission, contact, path, binding) do
    name =
      MissionRuntime.path_coordinator_name(ProcessNamespace.default(), mission, contact, path)

    case GenServer.whereis(name) do
      nil -> {:error, :path_runtime_not_running}
      runtime -> PathCoordinator.admit_uplink(runtime, binding)
    end
  catch
    :exit, _ -> {:error, :uplink_admission_unavailable}
  end

  @spec transmit(TransmitCommand.t()) :: {:ok, [term()]} | {:error, term()}
  def transmit(%TransmitCommand{session_admission: %UplinkAdmission{} = admission} = request) do
    if admission.target ==
         {request.mission_id, request.realized_contact_id, request.path_id,
          request.transport_binding_id} do
      TransportRuntime.handle_admitted_control_input(
        admission.runtime,
        to_uplink_request(request),
        admission.permit,
        occurred_at: request.occurred_at
      )
    else
      {:error, :uplink_admission_target_mismatch}
    end
  end

  def transmit(%TransmitCommand{}), do: {:error, :uplink_admission_required}

  defp to_uplink_request(%TransmitCommand{} = request) do
    UplinkRequest.new(%{
      command_release_attempt_id: request.transmit_request_id,
      command_queue_entry_id: request.command_queue_entry_id,
      command_request_id: request.command_request_id,
      source_endpoint_ref: request.source_endpoint_ref,
      mission_model_revision_id: request.mission_model_revision_id,
      command_id: request.command_id,
      command_name: request.command_name,
      layout_kind: request.layout_kind,
      preferred_uplink_service: request.preferred_uplink_service,
      apid: request.apid,
      service_type: request.service_type,
      service_subtype: request.service_subtype,
      opcode: request.opcode,
      encoded_binary_base64: request.encoded_binary_base64,
      encoded_size_bytes: request.encoded_size_bytes,
      metadata:
        Map.merge(request.metadata, %{
          "transmit_content_sha256" => request.content_sha256,
          "transmit_request_id" => request.transmit_request_id
        })
    })
  end
end
