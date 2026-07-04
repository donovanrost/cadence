defmodule Cadence.Dashboards.DataSourceEvent do
  @moduledoc """
  Append-only lifecycle event for a dashboard data source.

  The `dashboard_data_sources` row is the current source descriptor projection.
  Events preserve how that descriptor changed so runtime invalidations, audit,
  and future source administration screens can explain source mutations.
  """

  alias Cadence.Ids

  @type event_type :: :registered | :changed | :enabled | :disabled
  @type status :: :active | :disabled

  @type t :: %__MODULE__{
          data_source_event_id: binary(),
          data_source_id: binary(),
          organization_id: binary() | nil,
          mission_id: binary() | nil,
          event_type: event_type(),
          previous_status: status() | nil,
          current_status: status(),
          previous_owner: atom() | binary() | nil,
          current_owner: atom() | binary(),
          previous_kind: atom() | binary() | nil,
          current_kind: atom() | binary(),
          previous_adapter: module() | nil,
          current_adapter: module() | nil,
          previous_isolation_level: atom() | binary() | nil,
          current_isolation_level: atom() | binary(),
          previous_credentials_ref: binary() | nil,
          current_credentials_ref: binary() | nil,
          previous_capabilities: map() | nil,
          current_capabilities: map(),
          previous_metadata: map() | nil,
          current_metadata: map(),
          actor_id: binary() | nil,
          occurred_at: DateTime.t(),
          payload: map()
        }

  defstruct [
    :data_source_event_id,
    :data_source_id,
    :organization_id,
    :mission_id,
    :event_type,
    :previous_status,
    :current_status,
    :previous_owner,
    :current_owner,
    :previous_kind,
    :current_kind,
    :previous_adapter,
    :current_adapter,
    :previous_isolation_level,
    :current_isolation_level,
    :previous_credentials_ref,
    :current_credentials_ref,
    :previous_capabilities,
    :current_capabilities,
    :previous_metadata,
    :current_metadata,
    :actor_id,
    :occurred_at,
    payload: %{}
  ]

  @event_types [:registered, :changed, :enabled, :disabled]
  @statuses [:active, :disabled]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      data_source_event_id:
        get_attr(attrs, :data_source_event_id) || Ids.new("dashboard_data_source_event"),
      data_source_id: get_attr(attrs, :data_source_id),
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
      previous_owner: get_attr(attrs, :previous_owner),
      current_owner: get_attr(attrs, :current_owner),
      previous_kind: get_attr(attrs, :previous_kind),
      current_kind: get_attr(attrs, :current_kind),
      previous_adapter: get_attr(attrs, :previous_adapter),
      current_adapter: get_attr(attrs, :current_adapter),
      previous_isolation_level: get_attr(attrs, :previous_isolation_level),
      current_isolation_level: get_attr(attrs, :current_isolation_level),
      previous_credentials_ref: get_attr(attrs, :previous_credentials_ref),
      current_credentials_ref: get_attr(attrs, :current_credentials_ref),
      previous_capabilities: get_attr(attrs, :previous_capabilities),
      current_capabilities: get_attr(attrs, :current_capabilities, %{}),
      previous_metadata: get_attr(attrs, :previous_metadata),
      current_metadata: get_attr(attrs, :current_metadata, %{}),
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

  defp get_attr(attrs, key, default \\ nil) do
    Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
  end
end
