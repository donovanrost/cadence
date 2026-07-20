defmodule Cadence.Contacts.LinkAssignmentStore.LinkAssignmentRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Contacts.LinkAssignment
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Persistence.OrganizationScope

  @primary_key false
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "contact_link_assignments" do
    field(:link_assignment_id, :string)
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:lifecycle_state, :string)
    field(:spacecraft_id, :string)
    field(:source_endpoint_ref, :string)
    field(:path_template_id, :string)
    field(:path_template_version, :integer)
    field(:direction, :string)
    field(:selection_role, :string)
    field(:provider_path_ref, :string)
    field(:provider_profile_ref_documents, :map, default: %{})
    field(:transport_profile_ref_documents, :map, default: %{})
    field(:metadata, :map, default: %{})

    timestamps()
  end

  @required_fields [
    :link_assignment_id,
    :mission_id,
    :lifecycle_state,
    :spacecraft_id,
    :source_endpoint_ref,
    :path_template_id,
    :path_template_version,
    :direction,
    :selection_role,
    :provider_profile_ref_documents,
    :transport_profile_ref_documents,
    :metadata
  ]

  @spec changeset(LinkAssignment.t()) :: Ecto.Changeset.t()
  def changeset(%LinkAssignment{} = assignment) do
    %__MODULE__{}
    |> cast(domain_attrs(assignment), all_fields())
    |> OrganizationScope.put_organization_id()
    |> validate_required(@required_fields)
    |> unique_constraint([:mission_id, :link_assignment_id],
      name: :contact_link_assignments_scope_idx
    )
  end

  @spec to_domain(struct()) :: LinkAssignment.t()
  def to_domain(%__MODULE__{} = row) do
    LinkAssignment.new(%{
      link_assignment_id: row.link_assignment_id,
      organization_id: row.organization_id,
      mission_id: row.mission_id,
      lifecycle_state: row.lifecycle_state,
      spacecraft_id: row.spacecraft_id,
      source_endpoint_ref: row.source_endpoint_ref,
      path_template_id: row.path_template_id,
      path_template_version: row.path_template_version,
      direction: row.direction,
      selection_role: row.selection_role,
      provider_path_ref: row.provider_path_ref,
      provider_profile_refs: JsonDocument.unwrap_items(row.provider_profile_ref_documents),
      transport_profile_refs: JsonDocument.unwrap_items(row.transport_profile_ref_documents),
      metadata: JsonDocument.unwrap_value(row.metadata)
    })
  end

  defp domain_attrs(%LinkAssignment{} = assignment) do
    %{
      link_assignment_id: assignment.link_assignment_id,
      organization_id: assignment.organization_id,
      mission_id: assignment.mission_id,
      lifecycle_state: Atom.to_string(assignment.lifecycle_state),
      spacecraft_id: assignment.spacecraft_id,
      source_endpoint_ref: assignment.source_endpoint_ref,
      path_template_id: assignment.path_template_id,
      path_template_version: assignment.path_template_version,
      direction: Atom.to_string(assignment.direction),
      selection_role: Atom.to_string(assignment.selection_role),
      provider_path_ref: assignment.provider_path_ref,
      provider_profile_ref_documents: JsonDocument.wrap_items(assignment.provider_profile_refs),
      transport_profile_ref_documents: JsonDocument.wrap_items(assignment.transport_profile_refs),
      metadata: JsonDocument.wrap_value(assignment.metadata)
    }
  end

  defp all_fields do
    [
      :link_assignment_id,
      :organization_id,
      :mission_id,
      :lifecycle_state,
      :spacecraft_id,
      :source_endpoint_ref,
      :path_template_id,
      :path_template_version,
      :direction,
      :selection_role,
      :provider_path_ref,
      :provider_profile_ref_documents,
      :transport_profile_ref_documents,
      :metadata
    ]
  end
end
