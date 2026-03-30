defmodule Cadence.Ingress.RawEvidence do
  @moduledoc """
  Immutable ingress evidence captured before interpretation.
  """

  alias Cadence.Ids

  @type t :: %__MODULE__{
          evidence_id: binary(),
          mission_id: binary(),
          source_endpoint_ref: binary() | nil,
          spacecraft_id: binary() | nil,
          protocol_family: atom(),
          direction: :downlink | :uplink,
          raw: binary(),
          source_time: DateTime.t() | nil,
          receipt_time: DateTime.t(),
          source_ref: binary() | nil,
          metadata: map()
        }

  defstruct [
    :evidence_id,
    :mission_id,
    :source_endpoint_ref,
    :spacecraft_id,
    :protocol_family,
    :direction,
    :raw,
    :source_time,
    :receipt_time,
    :source_ref,
    metadata: %{}
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    mission_id = Map.fetch!(attrs, :mission_id)
    raw = Map.fetch!(attrs, :raw)

    %__MODULE__{
      evidence_id: Map.get(attrs, :evidence_id, Ids.new("evidence")),
      mission_id: mission_id,
      source_endpoint_ref: Map.get(attrs, :source_endpoint_ref),
      spacecraft_id: Map.get(attrs, :spacecraft_id),
      protocol_family: Map.get(attrs, :protocol_family, :space_packet),
      direction: Map.get(attrs, :direction, :downlink),
      raw: raw,
      source_time: Map.get(attrs, :source_time),
      receipt_time: Map.get(attrs, :receipt_time, DateTime.utc_now()),
      source_ref: Map.get(attrs, :source_ref),
      metadata: Map.get(attrs, :metadata, %{})
    }
  end
end
