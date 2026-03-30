defmodule Cadence.ActionRequests.UplinkRequest do
  @moduledoc """
  Typed platform-owned uplink action request emitted into the transport runtime.
  """

  @type t :: %__MODULE__{
          command_release_attempt_id: binary(),
          command_queue_entry_id: binary(),
          command_request_id: binary(),
          source_endpoint_ref: binary(),
          command_snapshot_id: binary(),
          command_id: binary(),
          command_name: binary() | nil,
          layout_kind: atom() | nil,
          preferred_uplink_service: binary() | nil,
          apid: non_neg_integer() | nil,
          service_type: non_neg_integer() | nil,
          service_subtype: non_neg_integer() | nil,
          opcode: term() | nil,
          encoded_binary_base64: binary(),
          encoded_size_bytes: non_neg_integer(),
          transport_profile: atom() | nil,
          transfer_frames_base64: [binary()],
          transfer_frame_count: non_neg_integer() | nil,
          transfer_frame_size_bytes: non_neg_integer() | nil,
          first_frame_seq: non_neg_integer() | nil,
          last_frame_seq: non_neg_integer() | nil,
          scid: non_neg_integer() | nil,
          vcid: non_neg_integer() | nil,
          bypass_flag: 0 | 1 | nil,
          control_command_flag: 0 | 1 | nil,
          segment_header_flag: 0 | 1 | nil,
          metadata: map()
        }

  defstruct [
    :command_release_attempt_id,
    :command_queue_entry_id,
    :command_request_id,
    :source_endpoint_ref,
    :command_snapshot_id,
    :command_id,
    :command_name,
    :layout_kind,
    :preferred_uplink_service,
    :apid,
    :service_type,
    :service_subtype,
    :opcode,
    :encoded_binary_base64,
    :encoded_size_bytes,
    :transport_profile,
    :transfer_frames_base64,
    :transfer_frame_count,
    :transfer_frame_size_bytes,
    :first_frame_seq,
    :last_frame_seq,
    :scid,
    :vcid,
    :bypass_flag,
    :control_command_flag,
    :segment_header_flag,
    metadata: %{}
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      command_release_attempt_id: Map.fetch!(attrs, :command_release_attempt_id),
      command_queue_entry_id: Map.fetch!(attrs, :command_queue_entry_id),
      command_request_id: Map.fetch!(attrs, :command_request_id),
      source_endpoint_ref: Map.fetch!(attrs, :source_endpoint_ref),
      command_snapshot_id: Map.fetch!(attrs, :command_snapshot_id),
      command_id: Map.fetch!(attrs, :command_id),
      command_name: Map.get(attrs, :command_name),
      layout_kind: Map.get(attrs, :layout_kind),
      preferred_uplink_service: Map.get(attrs, :preferred_uplink_service),
      apid: Map.get(attrs, :apid),
      service_type: Map.get(attrs, :service_type),
      service_subtype: Map.get(attrs, :service_subtype),
      opcode: Map.get(attrs, :opcode),
      encoded_binary_base64: Map.fetch!(attrs, :encoded_binary_base64),
      encoded_size_bytes: Map.fetch!(attrs, :encoded_size_bytes),
      transport_profile: Map.get(attrs, :transport_profile),
      transfer_frames_base64: Map.get(attrs, :transfer_frames_base64, []),
      transfer_frame_count: Map.get(attrs, :transfer_frame_count),
      transfer_frame_size_bytes: Map.get(attrs, :transfer_frame_size_bytes),
      first_frame_seq: Map.get(attrs, :first_frame_seq),
      last_frame_seq: Map.get(attrs, :last_frame_seq),
      scid: Map.get(attrs, :scid),
      vcid: Map.get(attrs, :vcid),
      bypass_flag: Map.get(attrs, :bypass_flag),
      control_command_flag: Map.get(attrs, :control_command_flag),
      segment_header_flag: Map.get(attrs, :segment_header_flag),
      metadata: Map.get(attrs, :metadata, %{})
    }
  end
end
