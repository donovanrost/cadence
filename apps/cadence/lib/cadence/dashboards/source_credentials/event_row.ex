defmodule Cadence.Dashboards.SourceCredentials.EventRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Dashboards.{SecretMetadata, SourceCredentialEvent}
  alias Cadence.Persistence.JsonDocument

  @primary_key {:source_credential_event_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "dashboard_source_credential_events" do
    field(:credentials_ref, :string)
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:data_source_id, :string)
    field(:event_type, :string)
    field(:previous_status, :string)
    field(:current_status, :string)
    field(:previous_credential_version, :integer)
    field(:current_credential_version, :integer)
    field(:actor_id, :string)
    field(:occurred_at, :utc_datetime_usec)
    field(:payload, :map, default: %{})

    timestamps()
  end

  @fields [
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
    :payload
  ]

  @required_fields [
    :source_credential_event_id,
    :credentials_ref,
    :organization_id,
    :event_type,
    :current_status,
    :current_credential_version,
    :occurred_at,
    :payload
  ]

  @event_types ["registered", "rotated", "enabled", "disabled"]
  @statuses ["active", "disabled"]

  @spec changeset(SourceCredentialEvent.t()) :: Ecto.Changeset.t()
  def changeset(%SourceCredentialEvent{} = event) do
    %__MODULE__{}
    |> cast(domain_attrs(event), @fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:event_type, @event_types)
    |> validate_inclusion(:previous_status, @statuses)
    |> validate_inclusion(:current_status, @statuses)
    |> validate_number(:previous_credential_version, greater_than: 0)
    |> validate_number(:current_credential_version, greater_than: 0)
    |> validate_payload_has_no_secrets()
    |> foreign_key_constraint(:credentials_ref, name: :dashboard_source_credential_events_ref_fk)
    |> foreign_key_constraint(:organization_id, name: :dashboard_source_credential_events_org_fk)
    |> foreign_key_constraint(
      :mission_id,
      name: :dashboard_source_credential_events_org_mission_fk
    )
  end

  @spec to_domain(struct()) :: SourceCredentialEvent.t()
  def to_domain(%__MODULE__{} = row) do
    SourceCredentialEvent.new(%{
      source_credential_event_id: row.source_credential_event_id,
      credentials_ref: row.credentials_ref,
      organization_id: row.organization_id,
      mission_id: row.mission_id,
      data_source_id: row.data_source_id,
      event_type: row.event_type,
      previous_status: row.previous_status,
      current_status: row.current_status,
      previous_credential_version: row.previous_credential_version,
      current_credential_version: row.current_credential_version,
      actor_id: row.actor_id,
      occurred_at: row.occurred_at,
      payload: JsonDocument.unwrap_value(row.payload)
    })
  end

  defp domain_attrs(%SourceCredentialEvent{} = event) do
    %{
      source_credential_event_id: event.source_credential_event_id,
      credentials_ref: event.credentials_ref,
      organization_id: event.organization_id,
      mission_id: event.mission_id,
      data_source_id: event.data_source_id,
      event_type: enum_string(event.event_type),
      previous_status: enum_string(event.previous_status),
      current_status: enum_string(event.current_status),
      previous_credential_version: event.previous_credential_version,
      current_credential_version: event.current_credential_version,
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
end
