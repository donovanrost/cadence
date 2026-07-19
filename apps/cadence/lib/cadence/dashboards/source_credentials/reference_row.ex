defmodule Cadence.Dashboards.SourceCredentials.ReferenceRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Dashboards.{SecretMetadata, SourceCredentialReference}
  alias Cadence.Persistence.JsonDocument

  @primary_key {:credentials_ref, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]

  schema "dashboard_source_credential_references" do
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:data_source_id, :string)
    field(:owner, :string)
    field(:kind, :string)
    field(:provider, :string)
    field(:status, :string)
    field(:credential_version, :integer)
    field(:current_event_id, :string)
    field(:last_rotated_at, :utc_datetime_usec)
    field(:disabled_at, :utc_datetime_usec)
    field(:metadata, :map, default: %{})

    timestamps()
  end

  @fields [
    :credentials_ref,
    :organization_id,
    :mission_id,
    :data_source_id,
    :owner,
    :kind,
    :provider,
    :status,
    :credential_version,
    :current_event_id,
    :last_rotated_at,
    :disabled_at,
    :metadata
  ]

  @required_fields [
    :credentials_ref,
    :organization_id,
    :owner,
    :kind,
    :status,
    :credential_version,
    :metadata
  ]

  @owners ["cadence", "customer"]
  @kinds ["byo_tsdb_connection", "managed_tsdb_connection"]
  @statuses ["active", "disabled"]

  @spec changeset(SourceCredentialReference.t()) :: Ecto.Changeset.t()
  def changeset(%SourceCredentialReference{} = reference) do
    changeset(%__MODULE__{}, reference)
  end

  @spec changeset(struct(), SourceCredentialReference.t()) :: Ecto.Changeset.t()
  def changeset(%__MODULE__{} = row, %SourceCredentialReference{} = reference) do
    row
    |> cast(domain_attrs(reference), @fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:owner, @owners)
    |> validate_inclusion(:kind, @kinds)
    |> validate_inclusion(:status, @statuses)
    |> validate_number(:credential_version, greater_than: 0)
    |> validate_metadata_has_no_secrets()
    |> foreign_key_constraint(:organization_id, name: :dashboard_source_credentials_org_fk)
    |> foreign_key_constraint(:mission_id, name: :dashboard_source_credentials_org_mission_fk)
  end

  @spec to_domain(struct()) :: SourceCredentialReference.t()
  def to_domain(%__MODULE__{} = row) do
    SourceCredentialReference.new(%{
      credentials_ref: row.credentials_ref,
      organization_id: row.organization_id,
      mission_id: row.mission_id,
      data_source_id: row.data_source_id,
      owner: row.owner,
      kind: row.kind,
      provider: row.provider,
      status: row.status,
      credential_version: row.credential_version,
      current_event_id: row.current_event_id,
      last_rotated_at: row.last_rotated_at,
      disabled_at: row.disabled_at,
      metadata: JsonDocument.unwrap_value(row.metadata)
    })
  end

  defp domain_attrs(%SourceCredentialReference{} = reference) do
    %{
      credentials_ref: reference.credentials_ref,
      organization_id: reference.organization_id,
      mission_id: reference.mission_id,
      data_source_id: reference.data_source_id,
      owner: enum_string(reference.owner),
      kind: enum_string(reference.kind),
      provider: reference.provider,
      status: enum_string(reference.status),
      credential_version: reference.credential_version,
      current_event_id: reference.current_event_id,
      last_rotated_at: reference.last_rotated_at,
      disabled_at: reference.disabled_at,
      metadata: JsonDocument.wrap_value(reference.metadata)
    }
  end

  defp validate_metadata_has_no_secrets(changeset) do
    changeset
    |> get_field(:metadata)
    |> JsonDocument.unwrap_value()
    |> SecretMetadata.contains_secret?()
    |> case do
      true -> add_error(changeset, :metadata, "must not embed credentials or secrets")
      false -> changeset
    end
  end

  defp enum_string(nil), do: nil
  defp enum_string(value) when is_atom(value), do: Atom.to_string(value)
  defp enum_string(value), do: value
end
