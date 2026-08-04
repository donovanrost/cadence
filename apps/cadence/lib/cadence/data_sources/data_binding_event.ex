defmodule Cadence.DataSources.DataBindingEvent do
  @moduledoc """
  Append-only lifecycle event for a data-source binding.

  The `data_source_bindings` row is the current projection. Events preserve
  how that projection changed so dashboard frames, replay, and audit can later
  explain which physical source backed a logical source at a point in time.
  """

  alias Cadence.Ids

  @type event_type :: :registered | :changed | :enabled | :disabled | :superseded
  @type status :: :active | :disabled | :superseded

  @type t :: %__MODULE__{
          data_binding_event_id: binary(),
          binding_id: binary(),
          organization_id: binary() | nil,
          mission_id: binary() | nil,
          event_type: event_type(),
          previous_status: status() | nil,
          current_status: status(),
          previous_binding_version: pos_integer() | nil,
          current_binding_version: pos_integer(),
          previous_logical_source: atom() | binary() | nil,
          current_logical_source: atom() | binary(),
          previous_realm: atom() | binary() | nil,
          current_realm: atom() | binary(),
          previous_data_source_id: binary() | nil,
          current_data_source_id: binary(),
          previous_dataset: binary() | nil,
          current_dataset: binary() | nil,
          previous_priority: integer() | nil,
          current_priority: integer(),
          previous_active_from: DateTime.t() | nil,
          current_active_from: DateTime.t() | nil,
          previous_active_to: DateTime.t() | nil,
          current_active_to: DateTime.t() | nil,
          actor_id: binary() | nil,
          occurred_at: DateTime.t(),
          payload: map()
        }

  defstruct [
    :data_binding_event_id,
    :binding_id,
    :organization_id,
    :mission_id,
    :event_type,
    :previous_status,
    :current_status,
    :previous_binding_version,
    :current_binding_version,
    :previous_logical_source,
    :current_logical_source,
    :previous_realm,
    :current_realm,
    :previous_data_source_id,
    :current_data_source_id,
    :previous_dataset,
    :current_dataset,
    :previous_priority,
    :current_priority,
    :previous_active_from,
    :current_active_from,
    :previous_active_to,
    :current_active_to,
    :actor_id,
    :occurred_at,
    payload: %{}
  ]

  @event_types [:registered, :changed, :enabled, :disabled, :superseded]
  @statuses [:active, :disabled, :superseded]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      data_binding_event_id:
        get_attr(attrs, :data_binding_event_id) || Ids.new("data_source_binding_event"),
      binding_id: get_attr(attrs, :binding_id),
      organization_id: get_attr(attrs, :organization_id),
      mission_id: get_attr(attrs, :mission_id),
      event_type:
        attrs
        |> get_attr(:event_type)
        |> normalize(:event_type, @event_types),
      previous_status: normalize_optional(get_attr(attrs, :previous_status), :status, @statuses),
      current_status:
        attrs
        |> get_attr(:current_status)
        |> normalize(:status, @statuses),
      previous_binding_version: get_attr(attrs, :previous_binding_version),
      current_binding_version: get_attr(attrs, :current_binding_version),
      previous_logical_source: get_attr(attrs, :previous_logical_source),
      current_logical_source: get_attr(attrs, :current_logical_source),
      previous_realm: get_attr(attrs, :previous_realm),
      current_realm: get_attr(attrs, :current_realm),
      previous_data_source_id: get_attr(attrs, :previous_data_source_id),
      current_data_source_id: get_attr(attrs, :current_data_source_id),
      previous_dataset: get_attr(attrs, :previous_dataset),
      current_dataset: get_attr(attrs, :current_dataset),
      previous_priority: get_attr(attrs, :previous_priority),
      current_priority: get_attr(attrs, :current_priority, 0),
      previous_active_from: normalize_optional_datetime(get_attr(attrs, :previous_active_from)),
      current_active_from: normalize_optional_datetime(get_attr(attrs, :current_active_from)),
      previous_active_to: normalize_optional_datetime(get_attr(attrs, :previous_active_to)),
      current_active_to: normalize_optional_datetime(get_attr(attrs, :current_active_to)),
      actor_id: get_attr(attrs, :actor_id),
      occurred_at:
        attrs
        |> get_attr(:occurred_at, DateTime.utc_now())
        |> DateTime.truncate(:microsecond),
      payload: get_attr(attrs, :payload, %{})
    }
  end

  defp normalize_optional(nil, _field, _values), do: nil
  defp normalize_optional(value, field, values), do: normalize(value, field, values)

  defp normalize(value, field, values) when is_atom(value) do
    if value in values do
      value
    else
      raise ArgumentError, "unsupported #{field}: #{inspect(value)}"
    end
  end

  defp normalize(value, field, values) when is_binary(value) do
    Enum.find(values, &(Atom.to_string(&1) == value)) ||
      raise ArgumentError, "unsupported #{field}: #{inspect(value)}"
  end

  defp normalize(value, field, _values) do
    raise ArgumentError, "unsupported #{field}: #{inspect(value)}"
  end

  defp normalize_optional_datetime(nil), do: nil

  defp normalize_optional_datetime(%DateTime{} = datetime) do
    DateTime.truncate(datetime, :microsecond)
  end

  defp get_attr(attrs, key, default \\ nil) do
    Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
  end
end
