defmodule Cadence.Persistence.Schemas.SpacecraftTelemetryDecomConfigRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Applications.TelemetryDecom.Config
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Persistence.OrganizationScope

  @primary_key {:spacecraft_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]

  schema "spacecraft_telemetry_decom_configs" do
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:catalog_revision_id, :string)
    field(:handled_apids, {:array, :integer}, default: [])
    field(:source_endpoint_id, :string)
    field(:enabled, :boolean, default: true)
    field(:applied_binding_set_id, :string)
    field(:applied_binding_set_version, :integer)
    field(:applied_at, :utc_datetime_usec)
    field(:metadata, :map, default: %{})

    timestamps()
  end

  @required_fields [
    :spacecraft_id,
    :mission_id,
    :catalog_revision_id,
    :handled_apids,
    :source_endpoint_id,
    :metadata
  ]

  @spec changeset(Config.t()) :: Ecto.Changeset.t()
  def changeset(%Config{} = config) do
    %__MODULE__{}
    |> cast(domain_attrs(config), all_fields())
    |> OrganizationScope.put_organization_id()
    |> validate_required(@required_fields)
  end

  @spec to_domain(struct()) :: Config.t()
  def to_domain(%__MODULE__{} = row) do
    %Config{
      spacecraft_id: row.spacecraft_id,
      organization_id: row.organization_id,
      mission_id: row.mission_id,
      catalog_revision_id: row.catalog_revision_id,
      handled_apids: row.handled_apids || [],
      source_endpoint_id: row.source_endpoint_id,
      enabled: row.enabled,
      applied_binding_set_id: row.applied_binding_set_id,
      applied_binding_set_version: row.applied_binding_set_version,
      applied_at: row.applied_at,
      metadata: JsonDocument.unwrap_value(row.metadata)
    }
  end

  defp domain_attrs(%Config{} = config) do
    %{
      spacecraft_id: config.spacecraft_id,
      organization_id: config.organization_id,
      mission_id: config.mission_id,
      catalog_revision_id: config.catalog_revision_id,
      handled_apids: config.handled_apids,
      source_endpoint_id: config.source_endpoint_id,
      enabled: config.enabled,
      applied_binding_set_id: config.applied_binding_set_id,
      applied_binding_set_version: config.applied_binding_set_version,
      applied_at: config.applied_at,
      metadata: JsonDocument.wrap_value(config.metadata)
    }
  end

  defp all_fields do
    [
      :spacecraft_id,
      :organization_id,
      :mission_id,
      :catalog_revision_id,
      :handled_apids,
      :source_endpoint_id,
      :enabled,
      :applied_binding_set_id,
      :applied_binding_set_version,
      :applied_at,
      :metadata
    ]
  end
end
