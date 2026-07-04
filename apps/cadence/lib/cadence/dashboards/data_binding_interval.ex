defmodule Cadence.Dashboards.DataBindingInterval do
  @moduledoc """
  Effective source-binding interval derived from append-only binding events.

  `started_at` and `ended_at` describe when an event state was the current
  projection. `active_from` and `active_to` remain the operator-defined
  activation window carried by that projection.
  """

  alias Cadence.Dashboards.{DataBinding, DataBindingEvent}

  @type t :: %__MODULE__{
          data_binding_event_id: binary(),
          binding_id: binary(),
          organization_id: binary() | nil,
          mission_id: binary() | nil,
          event_type: DataBindingEvent.event_type(),
          status: DataBindingEvent.status(),
          binding_version: pos_integer(),
          logical_source: atom() | binary(),
          realm: atom() | binary(),
          data_source_id: binary(),
          dataset: binary() | nil,
          priority: non_neg_integer(),
          started_at: DateTime.t(),
          ended_at: DateTime.t() | nil,
          active_from: DateTime.t() | nil,
          active_to: DateTime.t() | nil
        }

  defstruct [
    :data_binding_event_id,
    :binding_id,
    :organization_id,
    :mission_id,
    :event_type,
    :status,
    :binding_version,
    :logical_source,
    :realm,
    :data_source_id,
    :dataset,
    :started_at,
    :ended_at,
    :active_from,
    :active_to,
    priority: 0
  ]

  @spec from_event(DataBindingEvent.t(), DateTime.t() | nil) :: t()
  def from_event(%DataBindingEvent{} = event, ended_at \\ nil) do
    %__MODULE__{
      data_binding_event_id: event.data_binding_event_id,
      binding_id: event.binding_id,
      organization_id: event.organization_id,
      mission_id: event.mission_id,
      event_type: event.event_type,
      status: event.current_status,
      binding_version: event.current_binding_version,
      logical_source: event.current_logical_source,
      realm: event.current_realm,
      data_source_id: event.current_data_source_id,
      dataset: event.current_dataset,
      priority: event.current_priority,
      started_at: event.occurred_at,
      ended_at: ended_at,
      active_from: event.current_active_from,
      active_to: event.current_active_to
    }
  end

  @spec to_binding(t()) :: DataBinding.t()
  def to_binding(%__MODULE__{} = interval) do
    %DataBinding{
      binding_id: interval.binding_id,
      organization_id: interval.organization_id,
      mission_id: interval.mission_id,
      realm: interval.realm,
      logical_source: interval.logical_source,
      data_source_id: interval.data_source_id,
      dataset: interval.dataset,
      priority: interval.priority,
      status: interval.status,
      binding_version: interval.binding_version,
      current_event_id: interval.data_binding_event_id,
      active_from: interval.active_from,
      active_to: interval.active_to,
      metadata: %{}
    }
  end

  @spec contains?(t(), DateTime.t()) :: boolean()
  def contains?(%__MODULE__{status: :active} = interval, %DateTime{} = at) do
    starts_before_or_at?(effective_started_at(interval), at) and
      ends_after?(effective_ended_at(interval), at)
  end

  def contains?(%__MODULE__{}, %DateTime{}), do: false

  @spec overlaps?(t(), DateTime.t(), DateTime.t()) :: boolean()
  def overlaps?(%__MODULE__{status: :active} = interval, %DateTime{} = from, %DateTime{} = to) do
    starts_before?(effective_start(interval), to) and
      ends_after?(effective_end(interval), from)
  end

  def overlaps?(%__MODULE__{}, %DateTime{}, %DateTime{}), do: false

  @spec effective_start(t()) :: DateTime.t()
  def effective_start(%__MODULE__{} = interval) do
    later_datetime(interval.started_at, interval.active_from)
  end

  @spec effective_end(t()) :: DateTime.t() | nil
  def effective_end(%__MODULE__{} = interval) do
    earlier_datetime(interval.ended_at, interval.active_to)
  end

  @spec metadata(t()) :: map()
  def metadata(%__MODULE__{} = interval) do
    %{
      binding_id: interval.binding_id,
      data_binding_event_id: interval.data_binding_event_id,
      event_type: interval.event_type,
      binding_version: interval.binding_version,
      status: interval.status,
      logical_source: interval.logical_source,
      realm: interval.realm,
      data_source_id: interval.data_source_id,
      dataset: interval.dataset,
      started_at: interval.started_at,
      ended_at: interval.ended_at,
      active_from: interval.active_from,
      active_to: interval.active_to
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp effective_started_at(%__MODULE__{} = interval) do
    effective_start(interval)
  end

  defp effective_ended_at(%__MODULE__{} = interval) do
    effective_end(interval)
  end

  defp later_datetime(nil, datetime), do: datetime
  defp later_datetime(datetime, nil), do: datetime

  defp later_datetime(%DateTime{} = left, %DateTime{} = right) do
    if DateTime.compare(left, right) == :lt, do: right, else: left
  end

  defp earlier_datetime(nil, datetime), do: datetime
  defp earlier_datetime(datetime, nil), do: datetime

  defp earlier_datetime(%DateTime{} = left, %DateTime{} = right) do
    if DateTime.compare(left, right) == :gt, do: right, else: left
  end

  defp starts_before_or_at?(%DateTime{} = start, %DateTime{} = at) do
    DateTime.compare(start, at) != :gt
  end

  defp starts_before?(%DateTime{} = start, %DateTime{} = to) do
    DateTime.compare(start, to) == :lt
  end

  defp ends_after?(nil, %DateTime{}), do: true

  defp ends_after?(%DateTime{} = finish, %DateTime{} = at) do
    DateTime.compare(finish, at) == :gt
  end
end
