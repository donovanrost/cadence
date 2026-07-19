defmodule Cadence.Dashboards.DataSources.DataSourceRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Dashboards.{DataSource, SourceExecutionPolicy}
  alias Cadence.Persistence.JsonDocument

  @primary_key {:data_source_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]

  schema "dashboard_data_sources" do
    field(:owner, :string)
    field(:kind, :string)
    field(:adapter, :string)
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:isolation_level, :string)
    field(:credentials_ref, :string)
    field(:status, :string)
    field(:current_event_id, :string)
    field(:disabled_at, :utc_datetime_usec)
    field(:capabilities, :map, default: %{})
    field(:metadata, :map, default: %{})

    timestamps()
  end

  @fields [
    :data_source_id,
    :owner,
    :kind,
    :adapter,
    :organization_id,
    :mission_id,
    :isolation_level,
    :credentials_ref,
    :status,
    :current_event_id,
    :disabled_at,
    :capabilities,
    :metadata
  ]

  @required_fields [
    :data_source_id,
    :owner,
    :kind,
    :isolation_level,
    :status,
    :capabilities,
    :metadata
  ]

  @spec changeset(DataSource.t()) :: Ecto.Changeset.t()
  def changeset(%DataSource{} = data_source), do: changeset(%__MODULE__{}, data_source)

  @spec changeset(struct(), DataSource.t()) :: Ecto.Changeset.t()
  def changeset(%__MODULE__{} = row, %DataSource{} = data_source) do
    row
    |> cast(domain_attrs(data_source), @fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:owner, enum_strings([:cadence, :customer]))
    |> validate_inclusion(
      :kind,
      enum_strings([:managed_tsdb, :byo_tsdb, :postgres, :object_archive, :projection])
    )
    |> validate_inclusion(
      :isolation_level,
      enum_strings([:shared, :org_isolated, :mission_isolated, :customer_owned])
    )
    |> validate_inclusion(:status, enum_strings([:active, :disabled]))
    |> validate_data_source_configuration()
    |> validate_dashboard_policy_metadata()
    |> foreign_key_constraint(:credentials_ref, name: :dashboard_data_sources_credentials_ref_fk)
    |> foreign_key_constraint(:organization_id, name: :dashboard_data_sources_org_fk)
    |> foreign_key_constraint(:mission_id, name: :dashboard_data_sources_org_mission_fk)
  end

  @spec to_domain(struct()) :: DataSource.t()
  def to_domain(%__MODULE__{} = row) do
    %DataSource{
      data_source_id: row.data_source_id,
      owner: known_atom(row.owner),
      kind: known_atom(row.kind),
      adapter: adapter_module(row.adapter),
      organization_id: row.organization_id,
      mission_id: row.mission_id,
      isolation_level: known_atom(row.isolation_level),
      credentials_ref: row.credentials_ref,
      status: known_atom(row.status),
      current_event_id: row.current_event_id,
      disabled_at: row.disabled_at,
      capabilities: JsonDocument.unwrap_value(row.capabilities),
      metadata: JsonDocument.unwrap_value(row.metadata)
    }
  end

  defp domain_attrs(%DataSource{} = data_source) do
    %{
      data_source_id: data_source.data_source_id,
      owner: enum_string(data_source.owner),
      kind: enum_string(data_source.kind),
      adapter: adapter_string(data_source.adapter),
      organization_id: data_source.organization_id,
      mission_id: data_source.mission_id,
      isolation_level: enum_string(data_source.isolation_level),
      credentials_ref: data_source.credentials_ref,
      status: enum_string(data_source.status),
      current_event_id: data_source.current_event_id,
      disabled_at: data_source.disabled_at,
      capabilities: JsonDocument.wrap_value(data_source.capabilities),
      metadata: JsonDocument.wrap_value(data_source.metadata)
    }
  end

  defp enum_strings(values), do: Enum.map(values, &Atom.to_string/1)
  defp enum_string(value) when is_atom(value), do: Atom.to_string(value)
  defp enum_string(value), do: value

  defp known_atom(value) when is_binary(value), do: String.to_existing_atom(value)
  defp known_atom(value), do: value

  defp adapter_string(nil), do: nil
  defp adapter_string(adapter) when is_atom(adapter), do: Atom.to_string(adapter)

  defp adapter_module(nil), do: nil
  defp adapter_module(adapter) when is_binary(adapter), do: String.to_existing_atom(adapter)

  defp validate_data_source_configuration(changeset) do
    changeset
    |> changeset_data_source()
    |> DataSource.validate_configuration()
    |> case do
      :ok -> changeset
      {:error, errors} -> Enum.reduce(errors, changeset, &add_error(&2, elem(&1, 0), elem(&1, 1)))
    end
  end

  defp changeset_data_source(changeset) do
    %DataSource{
      data_source_id: get_field(changeset, :data_source_id),
      owner: get_field(changeset, :owner),
      kind: get_field(changeset, :kind),
      adapter: get_field(changeset, :adapter),
      organization_id: get_field(changeset, :organization_id),
      mission_id: get_field(changeset, :mission_id),
      isolation_level: get_field(changeset, :isolation_level),
      credentials_ref: get_field(changeset, :credentials_ref),
      status: get_field(changeset, :status),
      current_event_id: get_field(changeset, :current_event_id),
      disabled_at: get_field(changeset, :disabled_at),
      capabilities: get_field(changeset, :capabilities) |> JsonDocument.unwrap_value(),
      metadata: get_field(changeset, :metadata) |> JsonDocument.unwrap_value()
    }
  end

  defp validate_dashboard_policy_metadata(changeset) do
    changeset
    |> get_field(:metadata)
    |> JsonDocument.unwrap_value()
    |> SourceExecutionPolicy.validate_metadata_policy()
    |> case do
      :ok -> changeset
      {:error, errors} -> Enum.reduce(errors, changeset, &add_error(&2, :metadata, &1))
    end
  end
end
