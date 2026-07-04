defmodule Cadence.OperationalEvents.EffectiveInterval do
  @moduledoc """
  Effective interval projected from canonical operational events.

  Intervals are read models, not canonical facts. They explain which operational
  meaning was active across a time span and point back to the source events that
  opened and closed the interval.
  """

  @type kind ::
          :application_binding
          | :binding_set
          | :catalog_revision
          | :ground_station_connection_state
          | :link_frame_sync_state
          | :link_rf_lock_state
          | :operational_observable_state
          | :source_binding
          | :transport_connection_state
          | :transport_execution

  @type t :: %__MODULE__{
          interval_id: binary(),
          organization_id: binary() | nil,
          mission_id: binary(),
          kind: kind(),
          subject_kind: atom() | binary(),
          subject_id: binary(),
          starts_at: DateTime.t(),
          ends_at: DateTime.t() | nil,
          source_event_id: binary(),
          superseded_by_event_id: binary() | nil,
          payload: map(),
          metadata: map()
        }

  defstruct [
    :interval_id,
    :organization_id,
    :mission_id,
    :kind,
    :subject_kind,
    :subject_id,
    :starts_at,
    :ends_at,
    :source_event_id,
    :superseded_by_event_id,
    payload: %{},
    metadata: %{}
  ]

  @spec contains?(t(), DateTime.t()) :: boolean()
  def contains?(%__MODULE__{} = interval, %DateTime{} = at) do
    DateTime.compare(interval.starts_at, at) != :gt and ends_after?(interval.ends_at, at)
  end

  @spec overlaps?(t(), DateTime.t() | nil, DateTime.t() | nil) :: boolean()
  def overlaps?(%__MODULE__{}, nil, nil), do: true

  def overlaps?(%__MODULE__{} = interval, from, to) do
    starts_before_to? = is_nil(to) or DateTime.compare(interval.starts_at, to) == :lt
    ends_after_from? = is_nil(from) or ends_after?(interval.ends_at, from)

    starts_before_to? and ends_after_from?
  end

  @spec metadata(t()) :: map()
  def metadata(%__MODULE__{} = interval) do
    %{
      interval_id: interval.interval_id,
      kind: interval.kind,
      subject_kind: interval.subject_kind,
      subject_id: interval.subject_id,
      starts_at: interval.starts_at,
      ends_at: interval.ends_at,
      source_event_id: interval.source_event_id,
      superseded_by_event_id: interval.superseded_by_event_id,
      payload: interval.payload
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp ends_after?(nil, %DateTime{}), do: true

  defp ends_after?(%DateTime{} = ends_at, %DateTime{} = at) do
    DateTime.compare(ends_at, at) == :gt
  end
end
