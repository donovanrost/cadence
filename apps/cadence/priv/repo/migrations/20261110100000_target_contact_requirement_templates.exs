defmodule Cadence.Repo.Migrations.TargetContactRequirementTemplates do
  @moduledoc """
  CP3 targeted templates (DECISIONS #37, docs/apogee/domain/contact-templates.md):
  a template version gains `name` and `target_document`, `spacecraft_id`
  becomes legacy (nullable), and occurrences gain `spacecraft_id` so one
  occurrence fans out per targeted spacecraft. Existing templates become an
  explicit one-spacecraft list, so behavior is unchanged.
  """
  use Ecto.Migration

  def up do
    alter table(:contact_requirement_template_versions) do
      add(:name, :text)
      add(:target_document, :map)
    end

    execute("""
    ALTER TABLE contact_requirement_template_versions ALTER COLUMN spacecraft_id DROP NOT NULL
    """)

    # Map columns hold {"value": document} (JsonDocument.wrap_value/1).
    execute("""
    UPDATE contact_requirement_template_versions AS v
    SET target_document = jsonb_build_object(
          'value',
          jsonb_build_object('kind', 'spacecraft_ids', 'spacecraft_ids', jsonb_build_array(v.spacecraft_id))
        ),
        name = left(coalesce(nullif(s.display_name, ''), v.spacecraft_id) || ' recurring', 120)
    FROM mission_spacecraft AS s
    WHERE s.organization_id = v.organization_id
      AND s.mission_id = v.mission_id
      AND s.spacecraft_id = v.spacecraft_id
    """)

    execute("""
    UPDATE contact_requirement_template_versions
    SET target_document = jsonb_build_object(
          'value',
          jsonb_build_object('kind', 'spacecraft_ids', 'spacecraft_ids', jsonb_build_array(spacecraft_id))
        ),
        name = left(spacecraft_id || ' recurring', 120)
    WHERE target_document IS NULL
    """)

    execute("ALTER TABLE contact_requirement_template_versions ALTER COLUMN name SET NOT NULL")

    execute(
      "ALTER TABLE contact_requirement_template_versions ALTER COLUMN target_document SET NOT NULL"
    )

    alter table(:contact_requirement_occurrences) do
      add(:spacecraft_id, :string)
    end

    execute("""
    UPDATE contact_requirement_occurrences AS o
    SET spacecraft_id = v.spacecraft_id
    FROM contact_requirement_template_versions AS v
    WHERE v.organization_id = o.organization_id
      AND v.mission_id = o.mission_id
      AND v.contact_requirement_template_id = o.contact_requirement_template_id
      AND v.version = o.contact_requirement_template_version
    """)

    execute("ALTER TABLE contact_requirement_occurrences ALTER COLUMN spacecraft_id SET NOT NULL")

    # Build the new identity before dropping the old one: never a window without uniqueness.
    create(
      unique_index(
        :contact_requirement_occurrences,
        [
          :organization_id,
          :mission_id,
          :contact_requirement_template_id,
          :contact_requirement_template_version,
          :occurrence_at,
          :spacecraft_id
        ],
        name: :contact_requirement_occurrences_spacecraft_identity_uniq
      )
    )

    drop(
      index(:contact_requirement_occurrences, [],
        name: :contact_requirement_occurrences_identity_uniq
      )
    )

    execute("""
    ALTER TABLE contact_requirement_occurrences
    ADD CONSTRAINT contact_requirement_occurrences_spacecraft_fk
    FOREIGN KEY (organization_id, mission_id, spacecraft_id)
    REFERENCES mission_spacecraft (organization_id, mission_id, spacecraft_id)
    """)
  end

  # Irreversible: once a template fans out, one occurrence row per spacecraft can't fold back into
  # the old (template, version, occurrence) identity, and multi-target versions have no
  # spacecraft_id to restore. (domain review 9)
  def down do
    raise Ecto.MigrationError,
          "20261110100000 is irreversible: targeted templates can't fold back to one spacecraft"
  end
end
