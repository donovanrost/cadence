defmodule Cadence.Runtime.Transport.ProtocolEvent do
  @moduledoc """
  Transport-level protocol event emitted for uplink outcomes.
  """

  alias Cadence.Time, as: CadenceTime

  @type status ::
          :accepted
          | :rejected
          | :timeout
          | :cop1_retransmit
          | :cop1_timeout
          | :cop1_window_full
          | :cop1_stream_lockout
          | :cop1_report_decode_failed
          | :cop1_stream_hold
          | :cop1_stream_resynced
          | :cop1_stream_restarted
          | :cop1_report_for_unknown_stream
          | :tc_route_used
          | :routing_ambiguous

  @type t :: %__MODULE__{
          id: String.t(),
          mission_id: String.t(),
          interface_id: String.t(),
          protocol: atom(),
          status: status(),
          reason: term() | nil,
          seq: non_neg_integer() | nil,
          stream_id: term() | nil,
          correlation_id: term() | nil,
          timestamp: DateTime.t()
        }

  @derive Jason.Encoder
  defstruct [
    :id,
    :mission_id,
    :interface_id,
    :protocol,
    :status,
    :reason,
    :seq,
    :stream_id,
    :correlation_id,
    :timestamp
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      id: attrs[:id] || generate_id(),
      mission_id: attrs[:mission_id],
      interface_id: attrs[:interface_id],
      protocol: attrs[:protocol],
      status: attrs[:status],
      reason: attrs[:reason],
      seq: attrs[:seq],
      stream_id: attrs[:stream_id],
      correlation_id: attrs[:correlation_id],
      timestamp: attrs[:timestamp] || CadenceTime.now()
    }
  end

  @spec broadcast(t()) :: :ok
  def broadcast(%__MODULE__{} = event) do
    Phoenix.PubSub.broadcast(
      Cadence.PubSub,
      "mission:#{event.mission_id}:events",
      {:protocol_event, event}
    )
  end

  defp generate_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
end
