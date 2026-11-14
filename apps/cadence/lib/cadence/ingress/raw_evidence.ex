defmodule Cadence.Ingress.RawEvidence do
  @moduledoc """
  Immutable ingress evidence captured before interpretation.

  `receipt_time` is when the first byte reached Cadence. Evidence built from several journal
  records also carries `receipt_times`: each record's absolute start offset and its own socket
  receipt time, so a frame keeps the time its bytes arrived rather than the first record's
  (`receipt_time_at/2`).
  """

  alias Cadence.Ids

  @receipt_times_key "journal_receipt_times"

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
          receipt_times: [{non_neg_integer(), DateTime.t()}],
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
    receipt_times: [],
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
      receipt_times: Map.get(attrs, :receipt_times, []),
      source_ref: Map.get(attrs, :source_ref),
      metadata: Map.get(attrs, :metadata, %{})
    }
  end

  @doc """
  The receipt time of the byte at `absolute_offset`: that of the last record starting at or
  before it. Bytes before the first record (a frame carried over from earlier evidence) read as
  the first record's time; evidence without records reads as `receipt_time`.
  """
  @spec receipt_time_at(t(), integer()) :: DateTime.t()
  def receipt_time_at(%__MODULE__{} = evidence, absolute_offset) do
    case receipt_times(evidence) do
      [] -> evidence.receipt_time
      [{_start, first} | _] = times -> time_at(times, first, absolute_offset)
    end
  end

  defp time_at(times, first, absolute_offset) do
    Enum.reduce_while(times, first, fn
      {start, time}, _acc when start <= absolute_offset -> {:cont, time}
      _later, acc -> {:halt, acc}
    end)
  end

  # The struct field, else the metadata copy (evidence read back from the ingress archive).
  defp receipt_times(%__MODULE__{receipt_times: [_ | _] = times}), do: times

  defp receipt_times(%__MODULE__{metadata: metadata}) when is_map(metadata),
    do: decode_receipt_times(Map.get(metadata, @receipt_times_key))

  defp receipt_times(_evidence), do: []

  @doc false
  def receipt_times_key, do: @receipt_times_key

  @doc false
  @spec encode_receipt_times([{non_neg_integer(), DateTime.t()}]) :: [[term()]]
  def encode_receipt_times(times),
    do: Enum.map(times, fn {start, time} -> [start, DateTime.to_iso8601(time)] end)

  defp decode_receipt_times(encoded) when is_list(encoded) do
    Enum.flat_map(encoded, fn
      [start, iso] when is_integer(start) and is_binary(iso) ->
        case DateTime.from_iso8601(iso) do
          {:ok, time, _offset} -> [{start, time}]
          _invalid -> []
        end

      _other ->
        []
    end)
  end

  defp decode_receipt_times(_encoded), do: []
end
