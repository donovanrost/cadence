defmodule Cadence.Repo.Migrations.CreateContactRequirementTemplates do
  use Ecto.Migration

  def up do
    create table(:contact_requirement_templates, primary_key: false) do
      add(:contact_requirement_template_id, :string, primary_key: true)
      add(:organization_id, :string, null: false)
      add(:mission_id, :string, null: false)
      add(:current_version, :integer, null: false)
      add(:lifecycle_state, :string, null: false)
      add(:created_by, :string, null: false)
      add(:lifecycle_changed_by, :string, null: false)
      add(:lifecycle_changed_at, :utc_datetime_usec, null: false)
      add(:lifecycle_reason, :text, null: false, default: "")

      timestamps(type: :utc_datetime_usec)
    end

    create(
      unique_index(
        :contact_requirement_templates,
        [:organization_id, :mission_id, :contact_requirement_template_id],
        name: :contact_requirement_templates_scope_idx
      )
    )

    create(
      index(:contact_requirement_templates, [:organization_id, :mission_id, :lifecycle_state],
        name: :contact_requirement_templates_mission_state_idx
      )
    )

    create(
      constraint(
        :contact_requirement_templates,
        :contact_requirement_templates_current_version_positive,
        check: "current_version > 0"
      )
    )

    create(
      constraint(
        :contact_requirement_templates,
        :contact_requirement_templates_lifecycle_state_check,
        check: "lifecycle_state IN ('active', 'paused', 'closed')"
      )
    )

    execute("""
    ALTER TABLE contact_requirement_templates
    ADD CONSTRAINT contact_requirement_templates_scope_uniq
    UNIQUE USING INDEX contact_requirement_templates_scope_idx
    """)

    execute("""
    ALTER TABLE contact_requirement_templates
    ADD CONSTRAINT contact_requirement_templates_mission_fk
    FOREIGN KEY (organization_id, mission_id)
    REFERENCES missions (organization_id, mission_id)
    """)

    create table(:contact_requirement_template_versions, primary_key: false) do
      add(:contact_requirement_template_version_id, :string, primary_key: true)
      add(:contact_requirement_template_id, :string, null: false)
      add(:organization_id, :string, null: false)
      add(:mission_id, :string, null: false)
      add(:version, :integer, null: false)
      add(:spacecraft_id, :string, null: false)
      add(:schedule_document, :map, null: false)
      add(:requirement_document, :map, null: false)
      add(:catch_up_policy_document, :map, null: false)
      add(:content_sha256, :string, null: false)
      add(:created_by, :string, null: false)
      add(:created_at, :utc_datetime_usec, null: false)
    end

    create(
      unique_index(
        :contact_requirement_template_versions,
        [:organization_id, :mission_id, :contact_requirement_template_id, :version],
        name: :contact_requirement_template_versions_scope_idx
      )
    )

    create(
      index(
        :contact_requirement_template_versions,
        [:organization_id, :mission_id, :spacecraft_id],
        name: :contact_requirement_template_versions_spacecraft_idx
      )
    )

    create(
      constraint(
        :contact_requirement_template_versions,
        :contact_requirement_template_versions_version_positive,
        check: "version > 0"
      )
    )

    execute("""
    ALTER TABLE contact_requirement_template_versions
    ADD CONSTRAINT contact_requirement_template_versions_scope_uniq
    UNIQUE USING INDEX contact_requirement_template_versions_scope_idx
    """)

    execute("""
    ALTER TABLE contact_requirement_template_versions
    ADD CONSTRAINT contact_requirement_template_versions_template_fk
    FOREIGN KEY (organization_id, mission_id, contact_requirement_template_id)
    REFERENCES contact_requirement_templates (
      organization_id, mission_id, contact_requirement_template_id
    )
    """)

    execute("""
    ALTER TABLE contact_requirement_template_versions
    ADD CONSTRAINT contact_requirement_template_versions_spacecraft_fk
    FOREIGN KEY (organization_id, mission_id, spacecraft_id)
    REFERENCES mission_spacecraft (organization_id, mission_id, spacecraft_id)
    """)

    execute("""
    ALTER TABLE contact_requirement_templates
    ADD CONSTRAINT contact_requirement_templates_current_version_fk
    FOREIGN KEY (
      organization_id, mission_id, contact_requirement_template_id, current_version
    )
    REFERENCES contact_requirement_template_versions (
      organization_id, mission_id, contact_requirement_template_id, version
    )
    DEFERRABLE INITIALLY DEFERRED
    """)

    create table(:contact_requirement_occurrences, primary_key: false) do
      add(:contact_requirement_occurrence_id, :string, primary_key: true)
      add(:organization_id, :string, null: false)
      add(:mission_id, :string, null: false)
      add(:contact_requirement_template_id, :string, null: false)
      add(:contact_requirement_template_version, :integer, null: false)
      add(:occurrence_at, :utc_datetime_usec, null: false)
      add(:generation_state, :string, null: false)
      add(:generated_contact_requirement_id, :string)
      add(:generated_contact_requirement_version, :integer)
      add(:error_document, :map, null: false, default: %{})
      add(:materialized_by, :string, null: false)
      add(:materialized_at, :utc_datetime_usec, null: false)

      timestamps(type: :utc_datetime_usec)
    end

    create(
      unique_index(
        :contact_requirement_occurrences,
        [
          :organization_id,
          :mission_id,
          :contact_requirement_template_id,
          :contact_requirement_template_version,
          :occurrence_at
        ],
        name: :contact_requirement_occurrences_identity_uniq
      )
    )

    create(
      index(
        :contact_requirement_occurrences,
        [:organization_id, :mission_id, :occurrence_at, :generation_state],
        name: :contact_requirement_occurrences_horizon_idx
      )
    )

    create(
      constraint(
        :contact_requirement_occurrences,
        :contact_requirement_occurrences_version_positive,
        check:
          "contact_requirement_template_version > 0 AND " <>
            "(generated_contact_requirement_version IS NULL OR " <>
            "generated_contact_requirement_version > 0)"
      )
    )

    create(
      constraint(
        :contact_requirement_occurrences,
        :contact_requirement_occurrences_state_check,
        check: "generation_state IN ('materializing', 'generated', 'failed')"
      )
    )

    create(
      constraint(
        :contact_requirement_occurrences,
        :contact_requirement_occurrences_generated_binding_check,
        check:
          "(generation_state <> 'generated') OR " <>
            "(generated_contact_requirement_id IS NOT NULL AND " <>
            "generated_contact_requirement_version IS NOT NULL)"
      )
    )

    execute("""
    ALTER TABLE contact_requirement_occurrences
    ADD CONSTRAINT contact_requirement_occurrences_template_version_fk
    FOREIGN KEY (
      organization_id,
      mission_id,
      contact_requirement_template_id,
      contact_requirement_template_version
    )
    REFERENCES contact_requirement_template_versions (
      organization_id,
      mission_id,
      contact_requirement_template_id,
      version
    )
    """)

    execute("""
    ALTER TABLE contact_requirement_occurrences
    ADD CONSTRAINT contact_requirement_occurrences_requirement_version_fk
    FOREIGN KEY (
      organization_id,
      mission_id,
      generated_contact_requirement_id,
      generated_contact_requirement_version
    )
    REFERENCES contact_requirement_versions (
      organization_id,
      mission_id,
      contact_requirement_id,
      version
    )
    """)
  end

  def down do
    drop(table(:contact_requirement_occurrences))

    execute("""
    ALTER TABLE contact_requirement_templates
    DROP CONSTRAINT IF EXISTS contact_requirement_templates_current_version_fk
    """)

    drop(table(:contact_requirement_template_versions))
    drop(table(:contact_requirement_templates))
  end
end
