defmodule Cadence.Repo.Migrations.CreateContactLinkAssignments do
  use Ecto.Migration

  def change do
    create table(:contact_link_assignments, primary_key: false) do
      add(:link_assignment_id, :string, null: false)
      add(:organization_id, :string)
      add(:mission_id, :string, null: false)
      add(:lifecycle_state, :string, null: false, default: "active")
      add(:spacecraft_id, :string, null: false)
      add(:source_endpoint_ref, :string, null: false)
      add(:path_template_id, :string, null: false)
      add(:path_template_version, :integer, null: false, default: 1)
      add(:direction, :string, null: false)
      add(:selection_role, :string, null: false)
      add(:provider_path_ref, :string)
      add(:provider_profile_ref_documents, :map, null: false, default: %{})
      add(:transport_profile_ref_documents, :map, null: false, default: %{})
      add(:metadata, :map, null: false, default: %{})

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(
      unique_index(:contact_link_assignments, [:mission_id, :link_assignment_id],
        name: :contact_link_assignments_scope_idx
      )
    )

    create(index(:contact_link_assignments, [:organization_id, :mission_id]))

    create(
      index(:contact_link_assignments, [
        :organization_id,
        :mission_id,
        :source_endpoint_ref
      ])
    )

    create(
      index(:contact_link_assignments, [
        :organization_id,
        :mission_id,
        :path_template_id
      ])
    )
  end
end
