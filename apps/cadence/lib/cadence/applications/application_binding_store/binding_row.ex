defmodule Cadence.Applications.ApplicationBindingStore.BindingRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Applications.ApplicationBinding
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Persistence.OrganizationScope

  @primary_key {:application_binding_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]

  schema "spacecraft_application_bindings" do
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:spacecraft_id, :string)
    field(:application_key, :string)
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
    :application_binding_id,
    :mission_id,
    :spacecraft_id,
    :application_key,
    :catalog_revision_id,
    :handled_apids,
    :source_endpoint_id,
    :metadata
  ]

  @spec changeset(ApplicationBinding.t()) :: Ecto.Changeset.t()
  def changeset(%ApplicationBinding{} = binding) do
    %__MODULE__{}
    |> cast(domain_attrs(binding), all_fields())
    |> OrganizationScope.put_organization_id()
    |> validate_required(@required_fields)
    |> unique_constraint([:organization_id, :mission_id, :spacecraft_id, :application_key],
      name: :spacecraft_application_bindings_scope_idx
    )
  end

  @spec to_domain(struct()) :: ApplicationBinding.t()
  def to_domain(%__MODULE__{} = row) do
    %ApplicationBinding{
      application_binding_id: row.application_binding_id,
      organization_id: row.organization_id,
      mission_id: row.mission_id,
      spacecraft_id: row.spacecraft_id,
      application_key: row.application_key,
      catalog_revision_id: row.catalog_revision_id,
      handled_apids: row.handled_apids || [],
      source_endpoint_id: row.source_endpoint_id,
      enabled: row.enabled,
      applied_binding_set_id: row.applied_binding_set_id,
      applied_binding_set_version: row.applied_binding_set_version,
      applied_at: row.applied_at,
      updated_at: row.updated_at,
      metadata: JsonDocument.unwrap_value(row.metadata)
    }
  end

  defp domain_attrs(%ApplicationBinding{} = binding) do
    %{
      application_binding_id: binding.application_binding_id,
      organization_id: binding.organization_id,
      mission_id: binding.mission_id,
      spacecraft_id: binding.spacecraft_id,
      application_key: binding.application_key,
      catalog_revision_id: binding.catalog_revision_id,
      handled_apids: binding.handled_apids,
      source_endpoint_id: binding.source_endpoint_id,
      enabled: binding.enabled,
      applied_binding_set_id: binding.applied_binding_set_id,
      applied_binding_set_version: binding.applied_binding_set_version,
      applied_at: binding.applied_at,
      metadata: JsonDocument.wrap_value(binding.metadata)
    }
  end

  defp all_fields do
    [
      :application_binding_id,
      :organization_id,
      :mission_id,
      :spacecraft_id,
      :application_key,
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
