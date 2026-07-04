defmodule Cadence.Persistence.Schemas.LimitDefinitionLifecycleEventRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Limits.DefinitionLifecycleEvent
  alias Cadence.Persistence.JsonDocument

  @primary_key {:limit_definition_lifecycle_event_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "limit_definition_lifecycle_events" do
    field(:definition_activation_key, :string)
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:point_id, :string)
    field(:limit_set_name, :string)
    field(:scope_type, :string)
    field(:scope_ref, :string)
    field(:realm, :string)
    field(:event_type, :string)
    field(:limit_definition_id, :string)
    field(:limit_definition_version, :integer)
    field(:previous_limit_definition_id, :string)
    field(:previous_limit_definition_version, :integer)
    field(:active_from, :utc_datetime_usec)
    field(:active_to, :utc_datetime_usec)
    field(:reason, :string)
    field(:observed_at, :utc_datetime_usec)
    field(:payload, :map, default: %{})

    timestamps()
  end

  @fields [
    :limit_definition_lifecycle_event_id,
    :definition_activation_key,
    :organization_id,
    :mission_id,
    :point_id,
    :limit_set_name,
    :scope_type,
    :scope_ref,
    :realm,
    :event_type,
    :limit_definition_id,
    :limit_definition_version,
    :previous_limit_definition_id,
    :previous_limit_definition_version,
    :active_from,
    :active_to,
    :reason,
    :observed_at,
    :payload
  ]

  @required_fields [
    :limit_definition_lifecycle_event_id,
    :definition_activation_key,
    :mission_id,
    :point_id,
    :limit_set_name,
    :event_type,
    :limit_definition_id,
    :limit_definition_version,
    :active_from,
    :observed_at,
    :payload
  ]

  @event_types ["registered", "activated", "superseded", "disabled", "retired", "unknown"]

  @spec changeset(DefinitionLifecycleEvent.t()) :: Ecto.Changeset.t()
  def changeset(%DefinitionLifecycleEvent{} = event) do
    %__MODULE__{}
    |> cast(domain_attrs(event), @fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:event_type, @event_types)
    |> validate_number(:limit_definition_version, greater_than: 0)
    |> validate_number(:previous_limit_definition_version, greater_than: 0)
  end

  @spec to_domain(struct()) :: DefinitionLifecycleEvent.t()
  def to_domain(%__MODULE__{} = row) do
    DefinitionLifecycleEvent.new(%{
      limit_definition_lifecycle_event_id: row.limit_definition_lifecycle_event_id,
      definition_activation_key: row.definition_activation_key,
      organization_id: row.organization_id,
      mission_id: row.mission_id,
      point_id: row.point_id,
      limit_set_name: row.limit_set_name,
      scope_type: maybe_existing_atom(row.scope_type),
      scope_ref: row.scope_ref,
      realm: maybe_existing_atom(row.realm),
      event_type: maybe_existing_atom(row.event_type),
      limit_definition_id: row.limit_definition_id,
      limit_definition_version: row.limit_definition_version,
      previous_limit_definition_id: row.previous_limit_definition_id,
      previous_limit_definition_version: row.previous_limit_definition_version,
      active_from: row.active_from,
      active_to: row.active_to,
      reason: maybe_existing_atom(row.reason),
      observed_at: row.observed_at,
      payload: JsonDocument.unwrap_value(row.payload)
    })
  end

  defp domain_attrs(%DefinitionLifecycleEvent{} = event) do
    %{
      limit_definition_lifecycle_event_id: event.limit_definition_lifecycle_event_id,
      definition_activation_key: event.definition_activation_key,
      organization_id: event.organization_id,
      mission_id: event.mission_id,
      point_id: event.point_id,
      limit_set_name: event.limit_set_name,
      scope_type: enum_string(event.scope_type),
      scope_ref: event.scope_ref,
      realm: enum_string(event.realm),
      event_type: enum_string(event.event_type),
      limit_definition_id: event.limit_definition_id,
      limit_definition_version: event.limit_definition_version,
      previous_limit_definition_id: event.previous_limit_definition_id,
      previous_limit_definition_version: event.previous_limit_definition_version,
      active_from: event.active_from,
      active_to: event.active_to,
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
