defmodule Cadence.Telemetry.Storage.BackfillLifecycleEvent do
  @moduledoc """
  Durable lifecycle event for telemetry backfill/import runs.

  These events are coarse operational facts about a historical data movement
  workflow. Individual observations remain telemetry facts; this event tells
  dashboards why a historical range is being or was changed.
  """

  alias Cadence.Ids
  alias Cadence.Telemetry.BackfillLifecycleChanged
  alias Cadence.Telemetry.Storage.WriteContext

  @type event_type ::
          :backfill_requested
          | :backfill_approved
          | :backfill_rejected
          | :backfill_started
          | :backfill_completed
          | :backfill_failed
          | :backfill_retried
          | :backfill_missing_replacement_inspected
          | :backfill_stale_replacement_inspected
          | :backfill_stale_replacement_requeued
          | :import_requested
          | :import_approved
          | :import_rejected
          | :import_started
          | :import_completed
          | :import_failed
          | :import_retried
          | :import_missing_replacement_inspected
          | :import_stale_replacement_inspected
          | :import_stale_replacement_requeued
          | :late_data_accepted
          | :late_data_rejected
          | :unknown

  @type authority :: :authoritative | :advisory | :comparison | :unknown

  @type t :: %__MODULE__{
          backfill_lifecycle_event_id: binary(),
          backfill_run_id: binary(),
          organization_id: binary(),
          mission_id: binary(),
          realm: WriteContext.realm() | binary(),
          replay_run_id: binary() | nil,
          data_source_id: binary() | nil,
          binding_id: binary() | nil,
          observable_id: binary() | nil,
          point_id: binary() | nil,
          spacecraft_id: binary() | nil,
          event_type: event_type(),
          source_from: DateTime.t() | nil,
          source_to: DateTime.t() | nil,
          receipt_from: DateTime.t() | nil,
          receipt_to: DateTime.t() | nil,
          sample_count: non_neg_integer() | nil,
          authority: authority(),
          reason: binary() | atom() | nil,
          actor_id: binary() | nil,
          actor_kind: binary() | nil,
          occurred_at: DateTime.t(),
          payload: map()
        }

  defstruct [
    :backfill_lifecycle_event_id,
    :backfill_run_id,
    :organization_id,
    :mission_id,
    :realm,
    :replay_run_id,
    :data_source_id,
    :binding_id,
    :observable_id,
    :point_id,
    :spacecraft_id,
    :event_type,
    :source_from,
    :source_to,
    :receipt_from,
    :receipt_to,
    :sample_count,
    :reason,
    :actor_id,
    :actor_kind,
    :occurred_at,
    authority: :unknown,
    payload: %{}
  ]

  @event_types [
    :backfill_requested,
    :backfill_approved,
    :backfill_rejected,
    :backfill_started,
    :backfill_completed,
    :backfill_failed,
    :backfill_retried,
    :backfill_missing_replacement_inspected,
    :backfill_stale_replacement_inspected,
    :backfill_stale_replacement_requeued,
    :import_requested,
    :import_approved,
    :import_rejected,
    :import_started,
    :import_completed,
    :import_failed,
    :import_retried,
    :import_missing_replacement_inspected,
    :import_stale_replacement_inspected,
    :import_stale_replacement_requeued,
    :late_data_accepted,
    :late_data_rejected,
    :unknown
  ]

  @authorities [:authoritative, :advisory, :comparison, :unknown]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      backfill_lifecycle_event_id:
        get_attr(attrs, :backfill_lifecycle_event_id) ||
          Ids.new("telemetry_backfill_lifecycle_event"),
      backfill_run_id:
        get_attr(attrs, :backfill_run_id) || get_attr(attrs, :import_run_id) ||
          Ids.new("telemetry_backfill_run"),
      organization_id: get_attr(attrs, :organization_id),
      mission_id: get_attr(attrs, :mission_id),
      realm: get_attr(attrs, :realm),
      replay_run_id: get_attr(attrs, :replay_run_id),
      data_source_id: get_attr(attrs, :data_source_id),
      binding_id: get_attr(attrs, :binding_id) || get_attr(attrs, :source_binding_id),
      observable_id: get_attr(attrs, :observable_id),
      point_id: get_attr(attrs, :point_id) || get_attr(attrs, :observable_id),
      spacecraft_id: get_attr(attrs, :spacecraft_id),
      event_type:
        attrs
        |> get_attr(:event_type, :unknown)
        |> normalize_event_type(),
      source_from: normalize_datetime(get_attr(attrs, :source_from)),
      source_to: normalize_datetime(get_attr(attrs, :source_to)),
      receipt_from: normalize_datetime(get_attr(attrs, :receipt_from)),
      receipt_to: normalize_datetime(get_attr(attrs, :receipt_to)),
      sample_count: normalize_count(get_attr(attrs, :sample_count)),
      authority:
        attrs
        |> get_attr(:authority, :unknown)
        |> normalize_authority(),
      reason: get_attr(attrs, :reason),
      actor_id: get_attr(attrs, :actor_id) || get_attr(attrs, :operator_id),
      actor_kind: get_attr(attrs, :actor_kind),
      occurred_at:
        attrs
        |> get_attr(:occurred_at, DateTime.utc_now())
        |> normalize_datetime()
        |> truncate_datetime(),
      payload: get_attr(attrs, :payload, %{})
    }
  end

  @spec event_types() :: [event_type()]
  def event_types, do: @event_types

  @spec authorities() :: [authority()]
  def authorities, do: @authorities

  @spec to_fact(t()) :: BackfillLifecycleChanged.t()
  def to_fact(%__MODULE__{} = event) do
    BackfillLifecycleChanged.from_committed_event(event)
  end

  defp normalize_event_type(value) when is_atom(value) and value in @event_types, do: value

  defp normalize_event_type(value) when is_binary(value) do
    Enum.find(@event_types, &(Atom.to_string(&1) == value)) || :unknown
  end

  defp normalize_event_type(_value), do: :unknown

  defp normalize_authority(value) when is_atom(value) and value in @authorities, do: value

  defp normalize_authority(value) when is_binary(value) do
    Enum.find(@authorities, &(Atom.to_string(&1) == value)) || :unknown
  end

  defp normalize_authority(_value), do: :unknown

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
