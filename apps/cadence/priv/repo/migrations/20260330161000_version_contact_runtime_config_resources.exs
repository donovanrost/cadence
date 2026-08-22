defmodule Cadence.Repo.Migrations.VersionContactRuntimeConfigResources do
  use Ecto.Migration

  def up do
    execute("ALTER TABLE contact_provider_profiles DROP CONSTRAINT contact_provider_profiles_pkey")

    alter table(:contact_provider_profiles) do
      add(:version, :integer, null: false, default: 1)
      add(:lifecycle_state, :string, null: false, default: "active")
    end

    drop_if_exists(unique_index(:contact_provider_profiles, [:mission_id, :provider_profile_id],
                     name: :contact_provider_profiles_scope_idx
                   ))

    create(unique_index(:contact_provider_profiles, [:mission_id, :provider_profile_id, :version],
             name: :contact_provider_profiles_scope_idx
           ))

    execute("ALTER TABLE contact_transport_profiles DROP CONSTRAINT contact_transport_profiles_pkey")

    alter table(:contact_transport_profiles) do
      add(:version, :integer, null: false, default: 1)
      add(:lifecycle_state, :string, null: false, default: "active")
    end

    drop_if_exists(unique_index(:contact_transport_profiles, [:mission_id, :transport_profile_id],
                     name: :contact_transport_profiles_scope_idx
                   ))

    create(unique_index(:contact_transport_profiles, [:mission_id, :transport_profile_id, :version],
             name: :contact_transport_profiles_scope_idx
           ))

    execute("ALTER TABLE contact_path_templates DROP CONSTRAINT contact_path_templates_pkey")

    alter table(:contact_path_templates) do
      add(:version, :integer, null: false, default: 1)
      add(:lifecycle_state, :string, null: false, default: "active")
      add(:provider_profile_ref_documents, :map, null: false, default: %{})
      add(:transport_profile_ref_documents, :map, null: false, default: %{})
    end

    drop_if_exists(unique_index(:contact_path_templates, [:mission_id, :path_template_id],
                     name: :contact_path_templates_scope_idx
                   ))

    create(unique_index(:contact_path_templates, [:mission_id, :path_template_id, :version],
             name: :contact_path_templates_scope_idx
           ))

    alter table(:scheduled_contacts) do
      add(:path_template_ref_documents, :map, null: false, default: %{})
    end
  end

  def down do
    alter table(:scheduled_contacts) do
      remove(:path_template_ref_documents)
    end

    drop_if_exists(unique_index(:contact_path_templates, [:mission_id, :path_template_id, :version],
                     name: :contact_path_templates_scope_idx
                   ))

    alter table(:contact_path_templates) do
      remove(:transport_profile_ref_documents)
      remove(:provider_profile_ref_documents)
      remove(:lifecycle_state)
      remove(:version)
    end

    create(unique_index(:contact_path_templates, [:mission_id, :path_template_id],
             name: :contact_path_templates_scope_idx
           ))

    execute(
      "ALTER TABLE contact_path_templates ADD CONSTRAINT contact_path_templates_pkey PRIMARY KEY (path_template_id)"
    )

    drop_if_exists(unique_index(:contact_transport_profiles, [:mission_id, :transport_profile_id, :version],
                     name: :contact_transport_profiles_scope_idx
                   ))

    alter table(:contact_transport_profiles) do
      remove(:lifecycle_state)
      remove(:version)
    end

    create(unique_index(:contact_transport_profiles, [:mission_id, :transport_profile_id],
             name: :contact_transport_profiles_scope_idx
           ))

    execute(
      "ALTER TABLE contact_transport_profiles ADD CONSTRAINT contact_transport_profiles_pkey PRIMARY KEY (transport_profile_id)"
    )

    drop_if_exists(unique_index(:contact_provider_profiles, [:mission_id, :provider_profile_id, :version],
                     name: :contact_provider_profiles_scope_idx
                   ))

    alter table(:contact_provider_profiles) do
      remove(:lifecycle_state)
      remove(:version)
    end

    create(unique_index(:contact_provider_profiles, [:mission_id, :provider_profile_id],
             name: :contact_provider_profiles_scope_idx
           ))

    execute(
      "ALTER TABLE contact_provider_profiles ADD CONSTRAINT contact_provider_profiles_pkey PRIMARY KEY (provider_profile_id)"
    )
  end
end
