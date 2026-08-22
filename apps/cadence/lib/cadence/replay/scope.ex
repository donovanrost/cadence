defmodule Cadence.Replay.Scope do
  @moduledoc """
  Describes which persisted evidence should be replayed.
  """

  @type t :: %__MODULE__{
          evidence_ids: [binary()] | nil,
          from_receipt_time: DateTime.t() | nil,
          to_receipt_time: DateTime.t() | nil,
          source_ref: binary() | nil,
          realized_contact_id: binary() | nil,
          metadata_match: map() | nil,
          spacecraft_id: binary() | nil,
          limit: pos_integer() | nil
        }

  defstruct [
    :evidence_ids,
    :from_receipt_time,
    :to_receipt_time,
    :source_ref,
    :realized_contact_id,
    :metadata_match,
    :spacecraft_id,
    :limit
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      evidence_ids: normalize_evidence_ids(Map.get(attrs, :evidence_ids)),
      from_receipt_time: Map.get(attrs, :from_receipt_time),
      to_receipt_time: Map.get(attrs, :to_receipt_time),
      source_ref: Map.get(attrs, :source_ref),
      realized_contact_id: Map.get(attrs, :realized_contact_id),
      metadata_match: normalize_metadata_match(Map.get(attrs, :metadata_match)),
      spacecraft_id: Map.get(attrs, :spacecraft_id),
      limit: Map.get(attrs, :limit)
    }
  end

  @spec metadata(t()) :: map()
  def metadata(%__MODULE__{} = scope) do
    %{
      "evidence_ids" => scope.evidence_ids,
      "from_receipt_time" => encode_datetime(scope.from_receipt_time),
      "to_receipt_time" => encode_datetime(scope.to_receipt_time),
      "source_ref" => scope.source_ref,
      "realized_contact_id" => scope.realized_contact_id,
      "metadata_match" => scope.metadata_match,
      "spacecraft_id" => scope.spacecraft_id,
      "limit" => scope.limit
    }
  end

  @spec from_metadata(map()) :: t()
  def from_metadata(metadata) when is_map(metadata) do
    %__MODULE__{
      evidence_ids: normalize_evidence_ids(metadata_get(metadata, "evidence_ids")),
      from_receipt_time: decode_datetime(metadata_get(metadata, "from_receipt_time")),
      to_receipt_time: decode_datetime(metadata_get(metadata, "to_receipt_time")),
      source_ref: metadata_get(metadata, "source_ref"),
      realized_contact_id: metadata_get(metadata, "realized_contact_id"),
      metadata_match: normalize_metadata_match(metadata_get(metadata, "metadata_match")),
      spacecraft_id: metadata_get(metadata, "spacecraft_id"),
      limit: metadata_get(metadata, "limit")
    }
  end

  defp normalize_evidence_ids(nil), do: nil

  defp normalize_evidence_ids(evidence_ids) when is_list(evidence_ids),
    do: Enum.uniq(evidence_ids)

  defp normalize_metadata_match(nil), do: nil

  defp normalize_metadata_match(metadata_match)
       when is_map(metadata_match) and map_size(metadata_match) == 0,
       do: nil

  defp normalize_metadata_match(metadata_match) when is_map(metadata_match), do: metadata_match

  defp encode_datetime(nil), do: nil
  defp encode_datetime(%DateTime{} = value), do: DateTime.to_iso8601(value)

  defp decode_datetime(nil), do: nil

  defp decode_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      {:error, _reason} -> nil
    end
  end

  defp metadata_get(metadata, "evidence_ids"),
    do: Map.get(metadata, "evidence_ids") || Map.get(metadata, :evidence_ids)

  defp metadata_get(metadata, "from_receipt_time"),
    do: Map.get(metadata, "from_receipt_time") || Map.get(metadata, :from_receipt_time)

  defp metadata_get(metadata, "to_receipt_time"),
    do: Map.get(metadata, "to_receipt_time") || Map.get(metadata, :to_receipt_time)

  defp metadata_get(metadata, "source_ref"),
    do: Map.get(metadata, "source_ref") || Map.get(metadata, :source_ref)

  defp metadata_get(metadata, "realized_contact_id"),
    do: Map.get(metadata, "realized_contact_id") || Map.get(metadata, :realized_contact_id)

  defp metadata_get(metadata, "metadata_match"),
    do: Map.get(metadata, "metadata_match") || Map.get(metadata, :metadata_match)

  defp metadata_get(metadata, "spacecraft_id"),
    do: Map.get(metadata, "spacecraft_id") || Map.get(metadata, :spacecraft_id)

  defp metadata_get(metadata, "limit"),
    do: Map.get(metadata, "limit") || Map.get(metadata, :limit)
end
