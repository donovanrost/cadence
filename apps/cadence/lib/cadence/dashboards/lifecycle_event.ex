defmodule Cadence.Dashboards.LifecycleEvent do
  @moduledoc """
  Append-only event for dashboard document lifecycle transitions.
  """

  alias Cadence.Ids

  @type event_type ::
          :published
          | :archived
          | :restored
          | :reverted
          | :comparison_review_requested
          | :comparison_review_resolved
          | :health_snapshot_captured
          | :publish_readiness_checked

  @type t :: %__MODULE__{
          dashboard_lifecycle_event_id: binary(),
          organization_id: binary() | nil,
          mission_id: binary(),
          dashboard_id: binary(),
          event_type: event_type(),
          dashboard_version: pos_integer() | nil,
          previous_lifecycle_state: binary() | nil,
          current_lifecycle_state: binary() | nil,
          previous_published_version: pos_integer() | nil,
          current_published_version: pos_integer() | nil,
          actor_id: binary() | nil,
          occurred_at: DateTime.t(),
          payload: map()
        }

  @type version_snapshot :: %{
          lifecycle_state: binary() | nil,
          latest_version: pos_integer() | nil,
          draft_version: pos_integer() | nil,
          published_version: pos_integer() | nil
        }

  @type details :: %{
          event_type: event_type(),
          dashboard_name: binary() | nil,
          previous: version_snapshot(),
          current: version_snapshot(),
          source_version: pos_integer() | nil,
          reverted_version: pos_integer() | nil
        }

  defstruct [
    :dashboard_lifecycle_event_id,
    :organization_id,
    :mission_id,
    :dashboard_id,
    :event_type,
    :dashboard_version,
    :previous_lifecycle_state,
    :current_lifecycle_state,
    :previous_published_version,
    :current_published_version,
    :actor_id,
    :occurred_at,
    payload: %{}
  ]

  @event_types [
    :published,
    :archived,
    :restored,
    :reverted,
    :comparison_review_requested,
    :comparison_review_resolved,
    :health_snapshot_captured,
    :publish_readiness_checked
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      dashboard_lifecycle_event_id:
        Map.get(
          attrs,
          :dashboard_lifecycle_event_id,
          Map.get(attrs, "dashboard_lifecycle_event_id", Ids.new("dashboard_lifecycle_event"))
        ),
      organization_id: Map.get(attrs, :organization_id, Map.get(attrs, "organization_id")),
      mission_id: Map.fetch!(attrs, :mission_id),
      dashboard_id: Map.fetch!(attrs, :dashboard_id),
      event_type:
        attrs
        |> Map.get(:event_type, Map.get(attrs, "event_type"))
        |> normalize_event_type(),
      dashboard_version: Map.get(attrs, :dashboard_version, Map.get(attrs, "dashboard_version")),
      previous_lifecycle_state:
        Map.get(attrs, :previous_lifecycle_state, Map.get(attrs, "previous_lifecycle_state")),
      current_lifecycle_state:
        Map.get(attrs, :current_lifecycle_state, Map.get(attrs, "current_lifecycle_state")),
      previous_published_version:
        Map.get(attrs, :previous_published_version, Map.get(attrs, "previous_published_version")),
      current_published_version:
        Map.get(attrs, :current_published_version, Map.get(attrs, "current_published_version")),
      actor_id: Map.get(attrs, :actor_id, Map.get(attrs, "actor_id")),
      occurred_at:
        attrs
        |> Map.get(:occurred_at, Map.get(attrs, "occurred_at", DateTime.utc_now()))
        |> DateTime.truncate(:microsecond),
      payload: Map.get(attrs, :payload, Map.get(attrs, "payload", %{}))
    }
  end

  @spec details(t()) :: details()
  def details(%__MODULE__{} = event) do
    payload = payload_map(event.payload)

    %{
      event_type: event.event_type,
      dashboard_name: payload_value(payload, "dashboard_name"),
      previous: %{
        lifecycle_state:
          payload_value(payload, ["previous", "lifecycle_state"]) ||
            event.previous_lifecycle_state,
        latest_version: payload_version(payload, ["previous", "latest_version"]),
        draft_version: payload_version(payload, ["previous", "draft_version"]),
        published_version:
          payload_version(payload, ["previous", "published_version"]) ||
            event.previous_published_version
      },
      current: %{
        lifecycle_state:
          payload_value(payload, ["current", "lifecycle_state"]) ||
            event.current_lifecycle_state,
        latest_version: payload_version(payload, ["current", "latest_version"]),
        draft_version: payload_version(payload, ["current", "draft_version"]),
        published_version:
          payload_version(payload, ["current", "published_version"]) ||
            event.current_published_version
      },
      source_version: payload_version(payload, "source_version"),
      reverted_version: payload_version(payload, "reverted_version")
    }
  end

  @spec source_version(t()) :: pos_integer() | nil
  def source_version(%__MODULE__{} = event), do: event |> details() |> Map.fetch!(:source_version)

  @spec reverted_version(t()) :: pos_integer() | nil
  def reverted_version(%__MODULE__{} = event),
    do: event |> details() |> Map.fetch!(:reverted_version)

  defp normalize_event_type(value) when is_atom(value) and value in @event_types, do: value

  defp normalize_event_type(value) when is_binary(value) do
    Enum.find(@event_types, &(Atom.to_string(&1) == value)) ||
      raise ArgumentError, "unsupported event_type: #{inspect(value)}"
  end

  defp normalize_event_type(value) do
    raise ArgumentError, "unsupported event_type: #{inspect(value)}"
  end

  defp payload_map(payload) when is_map(payload), do: payload
  defp payload_map(_payload), do: %{}

  defp payload_value(payload, path) when is_list(path) do
    Enum.reduce_while(path, payload, fn key, acc ->
      case payload_value(acc, key) do
        nil -> {:halt, nil}
        value -> {:cont, value}
      end
    end)
  end

  defp payload_value(payload, key) when is_map(payload) do
    Map.get(payload, key) || Map.get(payload, maybe_atom_key(key))
  end

  defp payload_value(_payload, _key), do: nil

  defp payload_version(payload, path) do
    payload
    |> payload_value(path)
    |> normalize_version()
  end

  defp normalize_version(version) when is_integer(version) and version > 0, do: version

  defp normalize_version(version) when is_binary(version) do
    case Integer.parse(version) do
      {parsed, ""} when parsed > 0 -> parsed
      _invalid -> nil
    end
  end

  defp normalize_version(_version), do: nil

  defp maybe_atom_key("dashboard_name"), do: :dashboard_name
  defp maybe_atom_key("previous"), do: :previous
  defp maybe_atom_key("current"), do: :current
  defp maybe_atom_key("lifecycle_state"), do: :lifecycle_state
  defp maybe_atom_key("latest_version"), do: :latest_version
  defp maybe_atom_key("draft_version"), do: :draft_version
  defp maybe_atom_key("published_version"), do: :published_version
  defp maybe_atom_key("source_version"), do: :source_version
  defp maybe_atom_key("reverted_version"), do: :reverted_version
  defp maybe_atom_key(key), do: key
end
