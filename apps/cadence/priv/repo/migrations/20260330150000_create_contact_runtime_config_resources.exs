defmodule Cadence.Repo.Migrations.CreateContactRuntimeConfigResources do
  use Ecto.Migration

  def change do
    create table(:contact_provider_profiles, primary_key: false) do
      add(:provider_profile_id, :string, primary_key: true)
      add(:organization_id, :string)
      add(:mission_id, :string, null: false)
      add(:adapter_key, :string, null: false)
      add(:configuration, :map, null: false, default: %{})
      add(:metadata, :map, null: false, default: %{})

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(unique_index(:contact_provider_profiles, [:mission_id, :provider_profile_id],
             name: :contact_provider_profiles_scope_idx
           ))

    create(index(:contact_provider_profiles, [:organization_id, :mission_id]))

    create table(:contact_transport_profiles, primary_key: false) do
      add(:transport_profile_id, :string, primary_key: true)
      add(:organization_id, :string)
      add(:mission_id, :string, null: false)
      add(:family_key, :string, null: false)
      add(:target_scope, :string, null: false)
      add(:configuration, :map, null: false, default: %{})
      add(:metadata, :map, null: false, default: %{})

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(unique_index(:contact_transport_profiles, [:mission_id, :transport_profile_id],
             name: :contact_transport_profiles_scope_idx
           ))

    create(index(:contact_transport_profiles, [:organization_id, :mission_id]))

    create table(:contact_path_templates, primary_key: false) do
      add(:path_template_id, :string, primary_key: true)
      add(:organization_id, :string)
      add(:mission_id, :string, null: false)
      add(:path_id, :string, null: false)
      add(:direction, :string, null: false)
      add(:selection_role, :string, null: false)
      add(:source_endpoint_ref, :string)
      add(:provider_path_ref, :string)
      add(:provider_profile_ids, {:array, :string}, null: false, default: [])
      add(:transport_profile_ids, {:array, :string}, null: false, default: [])
      add(:metadata, :map, null: false, default: %{})

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(unique_index(:contact_path_templates, [:mission_id, :path_template_id],
             name: :contact_path_templates_scope_idx
           ))

    create(index(:contact_path_templates, [:organization_id, :mission_id]))

    alter table(:scheduled_contacts) do
      add(:path_template_ids, {:array, :string}, null: false, default: [])
    end
  end
end
