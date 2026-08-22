defmodule Cadence.Runtime.Commanding do
  @moduledoc """
  Data-plane boundary for command encoding and live transmission.
  """

  alias Cadence.ActionRequests.UplinkRequest
  alias Cadence.Commanding.Encoder
  alias Cadence.Runtime
  alias Cadence.Runtime.TransmitCommand

  @spec encode(term(), map()) :: {:ok, map()} | {:error, term()}
  def encode(immutable_runtime_definition, resolved_argument_values)
      when is_map(resolved_argument_values) do
    Encoder.encode(immutable_runtime_definition, resolved_argument_values)
  end

  @spec transmit(TransmitCommand.t()) :: {:ok, [term()]} | {:error, term()}
  def transmit(%TransmitCommand{} = request) do
    Runtime.handle_path_control_input(
      request.mission_id,
      request.realized_contact_id,
      request.path_id,
      request.transport_binding_id,
      to_uplink_request(request),
      occurred_at: request.occurred_at
    )
  end

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
