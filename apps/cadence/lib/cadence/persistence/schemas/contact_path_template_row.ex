defmodule Cadence.Persistence.Schemas.ContactPathTemplateRow do
  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Contacts.PathTemplate
  alias Cadence.Persistence.JsonDocument

  @primary_key false
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "contact_path_templates" do
    field(:path_template_id, :string)
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:version, :integer)
    field(:lifecycle_state, :string)
    field(:path_id, :string)
    field(:direction, :string)
    field(:selection_role, :string)
    field(:source_endpoint_ref, :string)
    field(:provider_path_ref, :string)
    field(:provider_profile_ids, {:array, :string}, default: [])
    field(:provider_profile_ref_documents, :map, default: %{})
    field(:transport_profile_ids, {:array, :string}, default: [])
    field(:transport_profile_ref_documents, :map, default: %{})
    field(:metadata, :map, default: %{})

    timestamps()
  end

  @required_fields [
    :path_template_id,
    :mission_id,
    :version,
    :lifecycle_state,
    :path_id,
    :direction,
    :selection_role,
    :provider_profile_ids,
    :provider_profile_ref_documents,
    :transport_profile_ids,
    :transport_profile_ref_documents,
    :metadata
  ]

  @spec changeset(PathTemplate.t()) :: Ecto.Changeset.t()
  def changeset(%PathTemplate{} = path_template) do
    %__MODULE__{}
    |> cast(domain_attrs(path_template), all_fields())
    |> Cadence.Persistence.OrganizationScope.put_organization_id()
    |> validate_required(@required_fields)
    |> unique_constraint([:mission_id, :path_template_id, :version],
      name: :contact_path_templates_scope_idx
    )
  end

  @spec to_domain(struct()) :: PathTemplate.t()
  def to_domain(%__MODULE__{} = row) do
    PathTemplate.new(%{
      path_template_id: row.path_template_id,
      organization_id: row.organization_id,
      mission_id: row.mission_id,
      version: row.version,
      lifecycle_state: row.lifecycle_state,
      path_id: row.path_id,
      direction: row.direction,
      selection_role: row.selection_role,
      source_endpoint_ref: row.source_endpoint_ref,
      provider_path_ref: row.provider_path_ref,
      provider_profile_ids: row.provider_profile_ids,
      provider_profile_refs: JsonDocument.unwrap_items(row.provider_profile_ref_documents),
      transport_profile_ids: row.transport_profile_ids,
      transport_profile_refs: JsonDocument.unwrap_items(row.transport_profile_ref_documents),
      metadata: JsonDocument.unwrap_value(row.metadata)
    })
  end

  defp domain_attrs(%PathTemplate{} = path_template) do
    %{
      path_template_id: path_template.path_template_id,
      organization_id: path_template.organization_id,
      mission_id: path_template.mission_id,
      version: path_template.version,
      lifecycle_state: Atom.to_string(path_template.lifecycle_state),
      path_id: path_template.path_id,
      direction: Atom.to_string(path_template.direction),
      selection_role: Atom.to_string(path_template.selection_role),
      source_endpoint_ref: path_template.source_endpoint_ref,
      provider_path_ref: path_template.provider_path_ref,
      provider_profile_ids: path_template.provider_profile_ids,
      provider_profile_ref_documents:
        JsonDocument.wrap_items(path_template.provider_profile_refs),
      transport_profile_ids: path_template.transport_profile_ids,
      transport_profile_ref_documents:
        JsonDocument.wrap_items(path_template.transport_profile_refs),
      metadata: JsonDocument.wrap_value(path_template.metadata)
    }
  end

  defp all_fields do
    [
      :path_template_id,
      :organization_id,
      :mission_id,
      :version,
      :lifecycle_state,
      :path_id,
      :direction,
      :selection_role,
      :source_endpoint_ref,
      :provider_path_ref,
      :provider_profile_ids,
      :provider_profile_ref_documents,
      :transport_profile_ids,
      :transport_profile_ref_documents,
      :metadata
    ]
  end
end
