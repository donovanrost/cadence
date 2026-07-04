defmodule Cadence.Dashboards.SourceWatermarkEvent do
  @moduledoc """
  Append-only dashboard source-watermark transition.
  """

  alias Cadence.Dashboards.RuntimeCacheKey
  alias Cadence.Ids

  @type confidence :: :authoritative | :best_effort | :unknown
  @type event_type :: :observed | :advanced | :retreated | :changed | :unknown

  @type t :: %__MODULE__{
          source_watermark_event_id: binary(),
          source_watermark_key: binary(),
          organization_id: binary() | nil,
          mission_id: binary(),
          logical_source: atom() | binary(),
          data_source_id: binary(),
          source_binding_id: binary() | nil,
          realm: atom() | binary() | nil,
          replay_run_id: binary() | nil,
          dataset: binary() | nil,
          event_type: event_type(),
          complete_through: DateTime.t() | nil,
          previous_complete_through: DateTime.t() | nil,
          latest_receipt_time: DateTime.t() | nil,
          previous_latest_receipt_time: DateTime.t() | nil,
          retention_starts_at: DateTime.t() | nil,
          previous_retention_starts_at: DateTime.t() | nil,
          sample_count: non_neg_integer() | nil,
          confidence: confidence(),
          reason: atom() | binary() | nil,
          observed_at: DateTime.t(),
          payload: map()
        }

  defstruct [
    :source_watermark_event_id,
    :source_watermark_key,
    :organization_id,
    :mission_id,
    :logical_source,
    :data_source_id,
    :source_binding_id,
    :realm,
    :replay_run_id,
    :dataset,
    :event_type,
    :complete_through,
    :previous_complete_through,
    :latest_receipt_time,
    :previous_latest_receipt_time,
    :retention_starts_at,
    :previous_retention_starts_at,
    :sample_count,
    :reason,
    :observed_at,
    confidence: :unknown,
    payload: %{}
  ]

  @confidence_values [:authoritative, :best_effort, :unknown]
  @event_types [:observed, :advanced, :retreated, :changed, :unknown]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    identity = source_identity(attrs)

    %__MODULE__{
      source_watermark_event_id:
        get_attr(attrs, :source_watermark_event_id) || Ids.new("dashboard_source_watermark_event"),
      source_watermark_key:
        get_attr(attrs, :source_watermark_key) || source_watermark_key(identity),
      organization_id: Map.get(identity, :organization_id),
      mission_id: Map.fetch!(identity, :mission_id),
      logical_source: Map.fetch!(identity, :logical_source),
      data_source_id: Map.fetch!(identity, :data_source_id),
      source_binding_id: Map.get(identity, :source_binding_id),
      realm: Map.get(identity, :realm),
      replay_run_id: Map.get(identity, :replay_run_id),
      dataset: Map.get(identity, :dataset),
      event_type:
        attrs
        |> get_attr(:event_type, :observed)
        |> normalize_event_type(),
      complete_through: normalize_datetime(get_attr(attrs, :complete_through)),
      previous_complete_through: normalize_datetime(get_attr(attrs, :previous_complete_through)),
      latest_receipt_time: normalize_datetime(get_attr(attrs, :latest_receipt_time)),
      previous_latest_receipt_time:
        normalize_datetime(get_attr(attrs, :previous_latest_receipt_time)),
      retention_starts_at: normalize_datetime(get_attr(attrs, :retention_starts_at)),
      previous_retention_starts_at:
        normalize_datetime(get_attr(attrs, :previous_retention_starts_at)),
      sample_count: normalize_count(get_attr(attrs, :sample_count)),
      confidence:
        attrs
        |> get_attr(:confidence, :unknown)
        |> normalize_confidence(),
      reason: get_attr(attrs, :reason),
      observed_at:
        attrs
        |> get_attr(:observed_at, DateTime.utc_now())
        |> normalize_datetime()
        |> truncate_datetime(),
      payload: get_attr(attrs, :payload, %{})
    }
  end

  @spec source_watermark_key(map()) :: binary()
  def source_watermark_key(identity) when is_map(identity) do
    "source_watermark:" <>
      RuntimeCacheKey.fingerprint(%{
        organization_id: get_attr(identity, :organization_id),
        mission_id: get_attr(identity, :mission_id),
        logical_source: get_attr(identity, :logical_source),
        data_source_id: get_attr(identity, :data_source_id),
        source_binding_id: get_attr(identity, :source_binding_id),
        realm: get_attr(identity, :realm),
        replay_run_id: get_attr(identity, :replay_run_id),
        dataset: get_attr(identity, :dataset)
      })
  end

  defp source_identity(attrs) do
    %{
      organization_id: get_attr(attrs, :organization_id),
      mission_id: get_attr(attrs, :mission_id),
      logical_source: get_attr(attrs, :logical_source),
      data_source_id: get_attr(attrs, :data_source_id),
      source_binding_id: get_attr(attrs, :source_binding_id),
      realm: get_attr(attrs, :realm),
      replay_run_id: get_attr(attrs, :replay_run_id),
      dataset: get_attr(attrs, :dataset)
    }
  end

  defp normalize_confidence(value) when is_atom(value) and value in @confidence_values,
    do: value

  defp normalize_confidence(value) when is_binary(value) do
    Enum.find(@confidence_values, &(Atom.to_string(&1) == value)) || :unknown
  end

  defp normalize_confidence(_value), do: :unknown

  defp normalize_event_type(value) when is_atom(value) and value in @event_types, do: value

  defp normalize_event_type(value) when is_binary(value) do
    Enum.find(@event_types, &(Atom.to_string(&1) == value)) || :unknown
  end

  defp normalize_event_type(_value), do: :unknown

  defp normalize_datetime(nil), do: nil
  defp normalize_datetime(%DateTime{} = datetime), do: truncate_datetime(datetime)

  defp normalize_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      _error -> nil
    end
  end

  defp normalize_datetime(_value), do: nil

  defp truncate_datetime(nil), do: nil

  defp truncate_datetime(%DateTime{} = datetime) do
    datetime = DateTime.truncate(datetime, :microsecond)
    {microsecond, _precision} = datetime.microsecond
    %{datetime | microsecond: {microsecond, 6}}
  end

  defp normalize_count(value) when is_integer(value) and value >= 0, do: value
  defp normalize_count(_value), do: nil

  defp get_attr(attrs, key, default \\ nil)

  defp get_attr(%_{} = attrs, key, default) when is_atom(key) do
    attrs
    |> Map.from_struct()
    |> get_attr(key, default)
  end

  defp get_attr(attrs, key, default) when is_map(attrs) and is_atom(key) do
    Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
  end

  defp get_attr(_attrs, _key, default), do: default
end
