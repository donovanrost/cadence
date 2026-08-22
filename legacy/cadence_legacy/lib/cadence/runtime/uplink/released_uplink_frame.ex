defmodule Cadence.Runtime.Uplink.ReleasedUplinkFrame do
  @moduledoc """
  Release contract for uplink bytes emitted by COP-1 or direct sends.
  """

  @type kind :: :initial | :retransmit | :bypass | :direct

  @type t :: %__MODULE__{
          mission_id: String.t(),
          transport_id: String.t(),
          stream_id: term() | nil,
          seq: non_neg_integer() | nil,
          bytes: binary(),
          retries: non_neg_integer() | nil,
          kind: kind(),
          correlation_id: term() | nil
        }

  defstruct [
    :mission_id,
    :transport_id,
    :stream_id,
    :seq,
    :bytes,
    :retries,
    :kind,
    :correlation_id
  ]

  @spec from_frame(String.t(), String.t(), term() | nil, map(), kind()) :: t()
  def from_frame(mission_id, transport_id, stream_id, frame, kind)
      when is_binary(mission_id) and is_binary(transport_id) and is_map(frame) do
    %__MODULE__{
      mission_id: mission_id,
      transport_id: transport_id,
      stream_id: stream_id,
      seq: Map.get(frame, :seq),
      bytes: Map.fetch!(frame, :bytes),
      retries: Map.get(frame, :retries),
      kind: kind,
      correlation_id: Map.get(frame, :correlation_id)
    }
  end

  @spec from_bytes(String.t(), String.t(), term() | nil, binary(), kind(), term() | nil) :: t()
  def from_bytes(mission_id, transport_id, stream_id, bytes, kind, correlation_id \\ nil)
      when is_binary(mission_id) and is_binary(transport_id) and is_binary(bytes) do
    %__MODULE__{
      mission_id: mission_id,
      transport_id: transport_id,
      stream_id: stream_id,
      seq: nil,
      bytes: bytes,
      retries: nil,
      kind: kind,
      correlation_id: correlation_id
    }
  end
end
