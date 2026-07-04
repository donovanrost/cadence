defmodule Cadence.Dashboards.SourceCredentialEvent do
  @moduledoc """
  Append-only lifecycle event for a dashboard source credential reference.
  """

  alias Cadence.Ids

  @type event_type :: :registered | :rotated | :enabled | :disabled
  @type status :: :active | :disabled

  @type t :: %__MODULE__{
          source_credential_event_id: binary(),
          credentials_ref: binary(),
          organization_id: binary(),
          mission_id: binary() | nil,
          data_source_id: binary() | nil,
          event_type: event_type(),
          previous_status: status() | nil,
          current_status: status(),
          previous_credential_version: pos_integer() | nil,
          current_credential_version: pos_integer(),
          actor_id: binary() | nil,
          occurred_at: DateTime.t(),
          payload: map()
        }

  defstruct [
    :source_credential_event_id,
    :credentials_ref,
    :organization_id,
    :mission_id,
    :data_source_id,
    :event_type,
    :previous_status,
    :current_status,
    :previous_credential_version,
    :current_credential_version,
    :actor_id,
    :occurred_at,
    payload: %{}
  ]

  @event_types [:registered, :rotated, :enabled, :disabled]
  @statuses [:active, :disabled]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      source_credential_event_id:
        get_attr(attrs, :source_credential_event_id) || Ids.new("dashboard_source_cred_event"),
      credentials_ref: get_attr(attrs, :credentials_ref),
      organization_id: get_attr(attrs, :organization_id),
      mission_id: get_attr(attrs, :mission_id),
      data_source_id: get_attr(attrs, :data_source_id),
      event_type:
        attrs
        |> get_attr(:event_type)
        |> normalize(:event_type, @event_types),
      previous_status:
        normalize_optional(get_attr(attrs, :previous_status), :previous_status, @statuses),
      current_status:
        attrs
        |> get_attr(:current_status)
        |> normalize(:current_status, @statuses),
      previous_credential_version: get_attr(attrs, :previous_credential_version),
      current_credential_version: get_attr(attrs, :current_credential_version),
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
