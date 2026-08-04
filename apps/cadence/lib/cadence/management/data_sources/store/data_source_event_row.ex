defmodule Cadence.Management.DataSources.Store.DataSourceEventRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Platform.SecretMetadata

  alias Cadence.DataSources.DataSourceEvent
  alias Cadence.Persistence.JsonDocument

  @primary_key {:data_source_event_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "data_source_definition_events" do
    field(:data_source_id, :string)
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:event_type, :string)
    field(:previous_status, :string)
    field(:current_status, :string)
    field(:previous_owner, :string)
    field(:current_owner, :string)
    field(:previous_kind, :string)
    field(:current_kind, :string)
    field(:previous_adapter, :string)
    field(:current_adapter, :string)
    field(:previous_isolation_level, :string)
    field(:current_isolation_level, :string)
    field(:previous_credentials_ref, :string)
    field(:current_credentials_ref, :string)
    field(:previous_capabilities, :map)
    field(:current_capabilities, :map, default: %{})
    field(:previous_metadata, :map)
    field(:current_metadata, :map, default: %{})
    field(:actor_id, :string)
    field(:occurred_at, :utc_datetime_usec)
    field(:payload, :map, default: %{})

    timestamps()
  end

  @fields [
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
    :payload
  ]

  @required_fields [
    :data_source_event_id,
    :data_source_id,
    :event_type,
    :current_status,
    :current_owner,
    :current_kind,
    :current_isolation_level,
    :current_capabilities,
    :current_metadata,
    :occurred_at,
    :payload
  ]

  @event_types ["registered", "changed", "enabled", "disabled"]
  @statuses ["active", "disabled"]
  @owners ["cadence", "customer"]
  @kinds ["managed_tsdb", "byo_tsdb", "postgres", "object_archive", "projection"]
  @isolation_levels ["shared", "org_isolated", "mission_isolated", "customer_owned"]

  @spec changeset(DataSourceEvent.t()) :: Ecto.Changeset.t()
  def changeset(%DataSourceEvent{} = event) do
    %__MODULE__{}
    |> cast(domain_attrs(event), @fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:event_type, @event_types)
    |> validate_inclusion(:previous_status, @statuses)
    |> validate_inclusion(:current_status, @statuses)
    |> validate_inclusion(:previous_owner, @owners)
    |> validate_inclusion(:current_owner, @owners)
    |> validate_inclusion(:previous_kind, @kinds)
    |> validate_inclusion(:current_kind, @kinds)
    |> validate_inclusion(:previous_isolation_level, @isolation_levels)
    |> validate_inclusion(:current_isolation_level, @isolation_levels)
    |> validate_maps_have_no_secrets()
    |> foreign_key_constraint(:data_source_id, name: :data_source_definition_events_source_fk)
    |> foreign_key_constraint(:organization_id, name: :data_source_definition_events_org_fk)
    |> foreign_key_constraint(
      :mission_id,
      name: :data_source_definition_events_org_mission_fk
    )
  end

  @spec to_domain(struct()) :: DataSourceEvent.t()
  def to_domain(%__MODULE__{} = row) do
    DataSourceEvent.new(%{
      data_source_event_id: row.data_source_event_id,
      data_source_id: row.data_source_id,
      organization_id: row.organization_id,
      mission_id: row.mission_id,
      event_type: row.event_type,
      previous_status: maybe_existing_atom(row.previous_status),
      current_status: maybe_existing_atom(row.current_status),
      previous_owner: maybe_existing_atom(row.previous_owner),
      current_owner: maybe_existing_atom(row.current_owner),
      previous_kind: maybe_existing_atom(row.previous_kind),
      current_kind: maybe_existing_atom(row.current_kind),
      previous_adapter: adapter_module(row.previous_adapter),
      current_adapter: adapter_module(row.current_adapter),
      previous_isolation_level: maybe_existing_atom(row.previous_isolation_level),
      current_isolation_level: maybe_existing_atom(row.current_isolation_level),
      previous_credentials_ref: row.previous_credentials_ref,
      current_credentials_ref: row.current_credentials_ref,
      previous_capabilities: JsonDocument.unwrap_value(row.previous_capabilities),
      current_capabilities: JsonDocument.unwrap_value(row.current_capabilities),
      previous_metadata: JsonDocument.unwrap_value(row.previous_metadata),
      current_metadata: JsonDocument.unwrap_value(row.current_metadata),
      actor_id: row.actor_id,
      occurred_at: row.occurred_at,
      payload: JsonDocument.unwrap_value(row.payload)
    })
  end

  defp domain_attrs(%DataSourceEvent{} = event) do
    %{
      data_source_event_id: event.data_source_event_id,
      data_source_id: event.data_source_id,
      organization_id: event.organization_id,
      mission_id: event.mission_id,
      event_type: enum_string(event.event_type),
      previous_status: enum_string(event.previous_status),
      current_status: enum_string(event.current_status),
      previous_owner: enum_string(event.previous_owner),
      current_owner: enum_string(event.current_owner),
      previous_kind: enum_string(event.previous_kind),
      current_kind: enum_string(event.current_kind),
      previous_adapter: adapter_string(event.previous_adapter),
      current_adapter: adapter_string(event.current_adapter),
      previous_isolation_level: enum_string(event.previous_isolation_level),
      current_isolation_level: enum_string(event.current_isolation_level),
      previous_credentials_ref: event.previous_credentials_ref,
      current_credentials_ref: event.current_credentials_ref,
      previous_capabilities: JsonDocument.wrap_value(event.previous_capabilities),
      current_capabilities: JsonDocument.wrap_value(event.current_capabilities),
      previous_metadata: JsonDocument.wrap_value(event.previous_metadata),
      current_metadata: JsonDocument.wrap_value(event.current_metadata),
      actor_id: event.actor_id,
      occurred_at: event.occurred_at,
      payload: JsonDocument.wrap_value(event.payload)
    }
  end

  defp validate_maps_have_no_secrets(changeset) do
    changeset
    |> validate_map_has_no_secrets(:previous_metadata)
    |> validate_map_has_no_secrets(:current_metadata)
    |> validate_map_has_no_secrets(:payload)
  end

  defp validate_map_has_no_secrets(changeset, field) do
    changeset
    |> get_field(field)
    |> JsonDocument.unwrap_value()
    |> SecretMetadata.contains_secret?()
    |> case do
      true -> add_error(changeset, field, "must not embed credentials or secrets")
      false -> changeset
    end
  end

  defp enum_string(nil), do: nil
  defp enum_string(value) when is_atom(value), do: Atom.to_string(value)
  defp enum_string(value), do: value

  defp adapter_string(nil), do: nil
  defp adapter_string(adapter) when is_atom(adapter), do: Atom.to_string(adapter)

  defp adapter_module(nil), do: nil
  defp adapter_module(adapter) when is_binary(adapter), do: String.to_existing_atom(adapter)

  defp maybe_existing_atom(nil), do: nil

  defp maybe_existing_atom(value) when is_binary(value) do
    String.to_existing_atom(value)
  rescue
    ArgumentError -> value
  end

  defp maybe_existing_atom(value), do: value
end
