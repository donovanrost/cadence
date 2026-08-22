defmodule Cadence.Telemetry.Storage.BackfillLifecycleEvents.EventRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Persistence.JsonDocument
  alias Cadence.Telemetry.Storage.BackfillLifecycleEvent
  alias Cadence.Telemetry.Storage.WriteContext

  @primary_key {:backfill_lifecycle_event_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "telemetry_backfill_lifecycle_events" do
    field(:backfill_run_id, :string)
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:realm, :string)
    field(:replay_run_id, :string)
    field(:data_source_id, :string)
    field(:binding_id, :string)
    field(:observable_id, :string)
    field(:point_id, :string)
    field(:spacecraft_id, :string)
    field(:event_type, :string)
    field(:source_from, :utc_datetime_usec)
    field(:source_to, :utc_datetime_usec)
    field(:receipt_from, :utc_datetime_usec)
    field(:receipt_to, :utc_datetime_usec)
    field(:sample_count, :integer)
    field(:authority, :string)
    field(:reason, :string)
    field(:actor_id, :string)
    field(:actor_kind, :string)
    field(:occurred_at, :utc_datetime_usec)
    field(:payload, :map, default: %{})

    timestamps()
  end

  @fields [
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
    :authority,
    :reason,
    :actor_id,
    :actor_kind,
    :occurred_at,
    :payload
  ]

  @required_fields [
    :backfill_lifecycle_event_id,
    :backfill_run_id,
    :organization_id,
    :mission_id,
    :realm,
    :event_type,
    :authority,
    :occurred_at,
    :payload
  ]

  @event_types Enum.map(BackfillLifecycleEvent.event_types(), &Atom.to_string/1)
  @authorities Enum.map(BackfillLifecycleEvent.authorities(), &Atom.to_string/1)

  @spec changeset(BackfillLifecycleEvent.t()) :: Ecto.Changeset.t()
  def changeset(%BackfillLifecycleEvent{} = event) do
    %__MODULE__{}
    |> cast(domain_attrs(event), @fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:event_type, @event_types)
    |> validate_inclusion(:authority, @authorities)
    |> validate_number(:sample_count, greater_than_or_equal_to: 0)
    |> validate_map(:payload)
  end

  @spec to_domain(%__MODULE__{}) :: BackfillLifecycleEvent.t()
  def to_domain(%__MODULE__{} = row) do
    BackfillLifecycleEvent.new(%{
      backfill_lifecycle_event_id: row.backfill_lifecycle_event_id,
      backfill_run_id: row.backfill_run_id,
      organization_id: row.organization_id,
      mission_id: row.mission_id,
      realm: normalize_realm(row.realm),
      replay_run_id: row.replay_run_id,
      data_source_id: row.data_source_id,
      binding_id: row.binding_id,
      observable_id: row.observable_id,
      point_id: row.point_id,
      spacecraft_id: row.spacecraft_id,
      event_type: maybe_existing_atom(row.event_type),
      source_from: row.source_from,
      source_to: row.source_to,
      receipt_from: row.receipt_from,
      receipt_to: row.receipt_to,
      sample_count: row.sample_count,
      authority: maybe_existing_atom(row.authority),
      reason: maybe_existing_atom(row.reason),
      actor_id: row.actor_id,
      actor_kind: row.actor_kind,
      occurred_at: row.occurred_at,
      payload: JsonDocument.unwrap_value(row.payload)
    })
  end

  defp domain_attrs(%BackfillLifecycleEvent{} = event) do
    %{
      backfill_lifecycle_event_id: event.backfill_lifecycle_event_id,
      backfill_run_id: event.backfill_run_id,
      organization_id: event.organization_id,
      mission_id: event.mission_id,
      realm: enum_string(event.realm),
      replay_run_id: event.replay_run_id,
      data_source_id: event.data_source_id,
      binding_id: event.binding_id,
      observable_id: event.observable_id,
      point_id: event.point_id,
      spacecraft_id: event.spacecraft_id,
      event_type: enum_string(event.event_type),
      source_from: event.source_from,
      source_to: event.source_to,
      receipt_from: event.receipt_from,
      receipt_to: event.receipt_to,
      sample_count: event.sample_count,
      authority: enum_string(event.authority),
      reason: enum_string(event.reason),
      actor_id: event.actor_id,
      actor_kind: event.actor_kind,
      occurred_at: event.occurred_at,
      payload: JsonDocument.wrap_value(event.payload)
    }
  end

  defp validate_map(changeset, field) do
    case get_field(changeset, field) do
      value when is_map(value) -> changeset
      _value -> add_error(changeset, field, "must be a map")
    end
  end

  defp enum_string(nil), do: nil
  defp enum_string(value) when is_atom(value), do: Atom.to_string(value)
  defp enum_string(value), do: value

  defp normalize_realm(realm) when is_binary(realm) do
    Enum.find(WriteContext.realms(), realm, &(Atom.to_string(&1) == realm)) || realm
  end

  defp normalize_realm(realm), do: realm

  defp maybe_existing_atom(nil), do: nil

  defp maybe_existing_atom(value) when is_binary(value) do
    String.to_existing_atom(value)
  rescue
    ArgumentError -> value
  end

  defp maybe_existing_atom(value), do: value
end
