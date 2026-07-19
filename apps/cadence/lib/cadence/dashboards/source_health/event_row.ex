defmodule Cadence.Dashboards.SourceHealth.EventRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Dashboards.SourceHealthEvent
  alias Cadence.Persistence.JsonDocument

  @primary_key {:source_health_event_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "dashboard_source_health_events" do
    field(:source_health_key, :string)
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:logical_source, :string)
    field(:data_source_id, :string)
    field(:source_binding_id, :string)
    field(:realm, :string)
    field(:replay_run_id, :string)
    field(:dataset, :string)
    field(:event_type, :string)
    field(:source_health, :string)
    field(:previous_source_health, :string)
    field(:reason, :string)
    field(:observed_at, :utc_datetime_usec)
    field(:payload, :map, default: %{})

    timestamps()
  end

  @fields [
    :source_health_event_id,
    :source_health_key,
    :organization_id,
    :mission_id,
    :logical_source,
    :data_source_id,
    :source_binding_id,
    :realm,
    :replay_run_id,
    :dataset,
    :event_type,
    :source_health,
    :previous_source_health,
    :reason,
    :observed_at,
    :payload
  ]

  @required_fields [
    :source_health_event_id,
    :source_health_key,
    :mission_id,
    :logical_source,
    :data_source_id,
    :event_type,
    :source_health,
    :observed_at,
    :payload
  ]

  @source_health_values ["healthy", "degraded", "unavailable", "unknown"]
  @event_types ["degraded", "recovered", "unavailable", "unknown"]

  @spec changeset(SourceHealthEvent.t()) :: Ecto.Changeset.t()
  def changeset(%SourceHealthEvent{} = event) do
    %__MODULE__{}
    |> cast(domain_attrs(event), @fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:source_health, @source_health_values)
    |> validate_inclusion(:previous_source_health, @source_health_values)
    |> validate_inclusion(:event_type, @event_types)
  end

  @spec to_domain(struct()) :: SourceHealthEvent.t()
  def to_domain(%__MODULE__{} = row) do
    SourceHealthEvent.new(%{
      source_health_event_id: row.source_health_event_id,
      source_health_key: row.source_health_key,
      organization_id: row.organization_id,
      mission_id: row.mission_id,
      logical_source: maybe_existing_atom(row.logical_source),
      data_source_id: row.data_source_id,
      source_binding_id: row.source_binding_id,
      realm: maybe_existing_atom(row.realm),
      replay_run_id: row.replay_run_id,
      dataset: row.dataset,
      event_type: maybe_existing_atom(row.event_type),
      source_health: maybe_existing_atom(row.source_health),
      previous_source_health: maybe_existing_atom(row.previous_source_health),
      reason: maybe_existing_atom(row.reason),
      observed_at: row.observed_at,
      payload: JsonDocument.unwrap_value(row.payload)
    })
  end

  defp domain_attrs(%SourceHealthEvent{} = event) do
    %{
      source_health_event_id: event.source_health_event_id,
      source_health_key: event.source_health_key,
      organization_id: event.organization_id,
      mission_id: event.mission_id,
      logical_source: enum_string(event.logical_source),
      data_source_id: event.data_source_id,
      source_binding_id: event.source_binding_id,
      realm: enum_string(event.realm),
      replay_run_id: event.replay_run_id,
      dataset: event.dataset,
      event_type: enum_string(event.event_type),
      source_health: enum_string(event.source_health),
      previous_source_health: enum_string(event.previous_source_health),
      reason: enum_string(event.reason),
      observed_at: event.observed_at,
      payload: JsonDocument.wrap_value(event.payload)
    }
  end

  defp enum_string(nil), do: nil
  defp enum_string(value) when is_atom(value), do: Atom.to_string(value)
  defp enum_string(value), do: value

  defp maybe_existing_atom(nil), do: nil

  defp maybe_existing_atom(value) when is_binary(value) do
    String.to_existing_atom(value)
  rescue
    ArgumentError -> value
  end

  defp maybe_existing_atom(value), do: value
end
