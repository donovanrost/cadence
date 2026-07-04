defmodule Cadence.Persistence.Schemas.DashboardDataBindingEventRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Dashboards.{DataBindingEvent, SecretMetadata}
  alias Cadence.Persistence.JsonDocument

  @primary_key {:data_binding_event_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "dashboard_data_binding_events" do
    field(:binding_id, :string)
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:event_type, :string)
    field(:previous_status, :string)
    field(:current_status, :string)
    field(:previous_binding_version, :integer)
    field(:current_binding_version, :integer)
    field(:previous_logical_source, :string)
    field(:current_logical_source, :string)
    field(:previous_realm, :string)
    field(:current_realm, :string)
    field(:previous_data_source_id, :string)
    field(:current_data_source_id, :string)
    field(:previous_dataset, :string)
    field(:current_dataset, :string)
    field(:previous_priority, :integer)
    field(:current_priority, :integer)
    field(:previous_active_from, :utc_datetime_usec)
    field(:current_active_from, :utc_datetime_usec)
    field(:previous_active_to, :utc_datetime_usec)
    field(:current_active_to, :utc_datetime_usec)
    field(:actor_id, :string)
    field(:occurred_at, :utc_datetime_usec)
    field(:payload, :map, default: %{})

    timestamps()
  end

  @fields [
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
    :payload
  ]

  @required_fields [
    :data_binding_event_id,
    :binding_id,
    :event_type,
    :current_status,
    :current_binding_version,
    :current_logical_source,
    :current_realm,
    :current_data_source_id,
    :current_priority,
    :occurred_at,
    :payload
  ]

  @event_types ["registered", "changed", "enabled", "disabled", "superseded"]
  @statuses ["active", "disabled", "superseded"]

  @spec changeset(DataBindingEvent.t()) :: Ecto.Changeset.t()
  def changeset(%DataBindingEvent{} = event) do
    %__MODULE__{}
    |> cast(domain_attrs(event), @fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:event_type, @event_types)
    |> validate_inclusion(:previous_status, @statuses)
    |> validate_inclusion(:current_status, @statuses)
    |> validate_number(:previous_binding_version, greater_than: 0)
    |> validate_number(:current_binding_version, greater_than: 0)
    |> validate_number(:previous_priority, greater_than_or_equal_to: 0)
    |> validate_number(:current_priority, greater_than_or_equal_to: 0)
    |> validate_payload_has_no_secrets()
    |> foreign_key_constraint(:binding_id, name: :dashboard_data_binding_events_binding_fk)
    |> foreign_key_constraint(:organization_id, name: :dashboard_data_binding_events_org_fk)
    |> foreign_key_constraint(
      :mission_id,
      name: :dashboard_data_binding_events_org_mission_fk
    )
  end

  @spec to_domain(struct()) :: DataBindingEvent.t()
  def to_domain(%__MODULE__{} = row) do
    DataBindingEvent.new(%{
      data_binding_event_id: row.data_binding_event_id,
      binding_id: row.binding_id,
      organization_id: row.organization_id,
      mission_id: row.mission_id,
      event_type: row.event_type,
      previous_status: row.previous_status,
      current_status: row.current_status,
      previous_binding_version: row.previous_binding_version,
      current_binding_version: row.current_binding_version,
      previous_logical_source: maybe_existing_atom(row.previous_logical_source),
      current_logical_source: maybe_existing_atom(row.current_logical_source),
      previous_realm: maybe_existing_atom(row.previous_realm),
      current_realm: maybe_existing_atom(row.current_realm),
      previous_data_source_id: row.previous_data_source_id,
      current_data_source_id: row.current_data_source_id,
      previous_dataset: row.previous_dataset,
      current_dataset: row.current_dataset,
      previous_priority: row.previous_priority,
      current_priority: row.current_priority,
      previous_active_from: row.previous_active_from,
      current_active_from: row.current_active_from,
      previous_active_to: row.previous_active_to,
      current_active_to: row.current_active_to,
      actor_id: row.actor_id,
      occurred_at: row.occurred_at,
      payload: JsonDocument.unwrap_value(row.payload)
    })
  end

  defp domain_attrs(%DataBindingEvent{} = event) do
    %{
      data_binding_event_id: event.data_binding_event_id,
      binding_id: event.binding_id,
      organization_id: event.organization_id,
      mission_id: event.mission_id,
      event_type: enum_string(event.event_type),
      previous_status: enum_string(event.previous_status),
      current_status: enum_string(event.current_status),
      previous_binding_version: event.previous_binding_version,
      current_binding_version: event.current_binding_version,
      previous_logical_source: enum_string(event.previous_logical_source),
      current_logical_source: enum_string(event.current_logical_source),
      previous_realm: enum_string(event.previous_realm),
      current_realm: enum_string(event.current_realm),
      previous_data_source_id: event.previous_data_source_id,
      current_data_source_id: event.current_data_source_id,
      previous_dataset: event.previous_dataset,
      current_dataset: event.current_dataset,
      previous_priority: event.previous_priority,
      current_priority: event.current_priority,
      previous_active_from: event.previous_active_from,
      current_active_from: event.current_active_from,
      previous_active_to: event.previous_active_to,
      current_active_to: event.current_active_to,
      actor_id: event.actor_id,
      occurred_at: event.occurred_at,
      payload: JsonDocument.wrap_value(event.payload)
    }
  end

  defp validate_payload_has_no_secrets(changeset) do
    changeset
    |> get_field(:payload)
    |> JsonDocument.unwrap_value()
    |> SecretMetadata.contains_secret?()
    |> case do
      true -> add_error(changeset, :payload, "must not embed credentials or secrets")
      false -> changeset
    end
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
