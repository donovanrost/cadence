defmodule Cadence.GroundNetworks.ProviderAccounts.AccountVersionRow do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  alias Cadence.Dashboards.SecretMetadata
  alias Cadence.GroundNetworks.ProviderAccountVersion
  alias Cadence.Persistence.JsonDocument

  @primary_key false
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "provider_account_versions" do
    field(:provider_account_id, :string)
    field(:organization_id, :string)
    field(:version, :integer)
    field(:provider_type, :string)
    field(:client_key, :string)
    field(:base_url, :string)
    field(:region_ref, :string)
    field(:environment_ref, :string)
    field(:credential_ref, :string)
    field(:event_ingestion_mode, :string)
    field(:event_configuration, :map, default: %{})
    field(:request_policy, :map, default: %{})
    field(:guardrails, :map, default: %{})
    field(:provider_configuration, :map, default: %{})
    field(:created_by, :string)
    field(:created_at, :utc_datetime_usec)
    timestamps()
  end

  @documents [:event_configuration, :request_policy, :guardrails, :provider_configuration]
  @fields [
            :provider_account_id,
            :organization_id,
            :version,
            :provider_type,
            :client_key,
            :base_url,
            :region_ref,
            :environment_ref,
            :credential_ref,
            :event_ingestion_mode,
            :created_by,
            :created_at
          ] ++ @documents

  def changeset(%ProviderAccountVersion{} = version) do
    %__MODULE__{}
    |> cast(domain_attrs(version), @fields)
    |> validate_required(@fields -- [:region_ref, :created_by])
    |> validate_number(:version, greater_than: 0)
    |> validate_inclusion(:provider_type, ["simulator"])
    |> validate_inclusion(:client_key, ["simulator_http"])
    |> validate_inclusion(:event_ingestion_mode, ["polling", "webhook", "hybrid", "disabled"])
    |> validate_length(:base_url, min: 1, max: 2_000)
    |> validate_length(:credential_ref, min: 1, max: 500)
    |> validate_documents()
    |> unique_constraint([:provider_account_id, :version],
      name: :provider_account_versions_scope_idx
    )
  end

  def to_domain(%__MODULE__{} = row) do
    ProviderAccountVersion.new(%{
      provider_account_id: row.provider_account_id,
      organization_id: row.organization_id,
      version: row.version,
      provider_type: row.provider_type,
      client_key: row.client_key,
      base_url: row.base_url,
      region_ref: row.region_ref,
      environment_ref: row.environment_ref,
      credential_ref: row.credential_ref,
      event_ingestion_mode: row.event_ingestion_mode,
      event_configuration: unwrap(row.event_configuration),
      request_policy: unwrap(row.request_policy),
      guardrails: unwrap(row.guardrails),
      provider_configuration: unwrap(row.provider_configuration),
      created_by: row.created_by,
      created_at: row.created_at
    })
  end

  defp domain_attrs(version) do
    version
    |> Map.from_struct()
    |> Map.update!(:provider_type, &Atom.to_string/1)
    |> Map.update!(:client_key, &Atom.to_string/1)
    |> Map.update!(:event_ingestion_mode, &Atom.to_string/1)
    |> then(fn attrs ->
      Enum.reduce(
        @documents,
        attrs,
        &Map.update!(&2, &1, fn value -> JsonDocument.wrap_value(value) end)
      )
    end)
  end

  defp validate_documents(changeset) do
    Enum.reduce(@documents, changeset, fn field, current ->
      document = current |> get_field(field) |> unwrap()

      if SecretMetadata.contains_secret?(document),
        do: add_error(current, field, "must be secret-free"),
        else: current
    end)
  end

  defp unwrap(document), do: JsonDocument.unwrap_value(document)
end
