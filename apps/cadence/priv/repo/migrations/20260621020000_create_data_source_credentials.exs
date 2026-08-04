defmodule Cadence.Repo.Migrations.CreateDataSourceCredentials do
  use Ecto.Migration

  def up do
    create table(:data_source_credential_references, primary_key: false) do
      add(:credentials_ref, :string, primary_key: true)
      add(:organization_id, :string, null: false)
      add(:mission_id, :string)
      add(:data_source_id, :string)
      add(:owner, :string, null: false)
      add(:kind, :string, null: false)
      add(:provider, :string)
      add(:status, :string, null: false)
      add(:credential_version, :integer, null: false, default: 1)
      add(:current_event_id, :string)
      add(:last_rotated_at, :utc_datetime_usec)
      add(:disabled_at, :utc_datetime_usec)
      add(:metadata, :map, null: false, default: %{})

      timestamps(type: :utc_datetime_usec)
    end

    create(
      index(:data_source_credential_references, [:organization_id, :mission_id],
        name: :data_source_credentials_scope_idx
      )
    )

    create(
      index(:data_source_credential_references, [:data_source_id],
        name: :data_source_credentials_data_source_idx
      )
    )

    create table(:data_source_credential_events, primary_key: false) do
      add(:source_credential_event_id, :string, primary_key: true)
      add(:credentials_ref, :string, null: false)
      add(:organization_id, :string, null: false)
      add(:mission_id, :string)
      add(:data_source_id, :string)
      add(:event_type, :string, null: false)
      add(:previous_status, :string)
      add(:current_status, :string, null: false)
      add(:previous_credential_version, :integer)
      add(:current_credential_version, :integer, null: false)
      add(:actor_id, :string)
      add(:occurred_at, :utc_datetime_usec, null: false)
      add(:payload, :map, null: false, default: %{})

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(
      index(:data_source_credential_events, [:credentials_ref, :occurred_at],
        name: :data_source_credential_events_ref_time_idx
      )
    )

    create(
      index(:data_source_credential_events, [:organization_id, :mission_id, :event_type],
        name: :data_source_credential_events_scope_type_idx
      )
    )

    execute("""
    ALTER TABLE data_source_credential_references
    ADD CONSTRAINT data_source_credentials_org_fk
    FOREIGN KEY (organization_id)
    REFERENCES organizations (organization_id)
    """)

    execute("""
    ALTER TABLE data_source_credential_references
    ADD CONSTRAINT data_source_credentials_org_mission_fk
    FOREIGN KEY (organization_id, mission_id)
    REFERENCES missions (organization_id, mission_id)
    """)

    execute("""
    ALTER TABLE data_source_credential_events
    ADD CONSTRAINT data_source_credential_events_ref_fk
    FOREIGN KEY (credentials_ref)
    REFERENCES data_source_credential_references (credentials_ref)
    """)

    execute("""
    ALTER TABLE data_source_credential_events
    ADD CONSTRAINT data_source_credential_events_org_fk
    FOREIGN KEY (organization_id)
    REFERENCES organizations (organization_id)
    """)

    execute("""
    ALTER TABLE data_source_credential_events
    ADD CONSTRAINT data_source_credential_events_org_mission_fk
    FOREIGN KEY (organization_id, mission_id)
    REFERENCES missions (organization_id, mission_id)
    """)
  end

  def down do
    execute("""
    ALTER TABLE data_source_credential_events
    DROP CONSTRAINT IF EXISTS data_source_credential_events_org_mission_fk
    """)

    execute("""
    ALTER TABLE data_source_credential_events
    DROP CONSTRAINT IF EXISTS data_source_credential_events_org_fk
    """)

    execute("""
    ALTER TABLE data_source_credential_events
    DROP CONSTRAINT IF EXISTS data_source_credential_events_ref_fk
    """)

    drop_if_exists(
      index(:data_source_credential_events, [:organization_id, :mission_id, :event_type],
        name: :data_source_credential_events_scope_type_idx
      )
    )

    drop_if_exists(
      index(:data_source_credential_events, [:credentials_ref, :occurred_at],
        name: :data_source_credential_events_ref_time_idx
      )
    )

    drop(table(:data_source_credential_events))

    execute("""
    ALTER TABLE data_source_credential_references
    DROP CONSTRAINT IF EXISTS data_source_credentials_org_mission_fk
    """)

    execute("""
    ALTER TABLE data_source_credential_references
    DROP CONSTRAINT IF EXISTS data_source_credentials_org_fk
    """)

    drop_if_exists(
      index(:data_source_credential_references, [:data_source_id],
        name: :data_source_credentials_data_source_idx
      )
    )

    drop_if_exists(
      index(:data_source_credential_references, [:organization_id, :mission_id],
        name: :data_source_credentials_scope_idx
      )
    )

    drop(table(:data_source_credential_references))
  end
end
