defmodule Cadence.Repo.Migrations.CreateContactPlanExecutionItems do
  use Ecto.Migration

  def up do
    alter table(:provider_reservations) do
      add(:contact_requirement_id, :string)
      add(:contact_requirement_version, :integer)
      add(:contact_plan_id, :string)
      add(:contact_plan_version, :integer)
      add(:contact_opportunity_snapshot_id, :string)
    end

    create(
      constraint(:provider_reservations, :provider_reservations_plan_binding_shape,
        check:
          "(contact_requirement_id IS NULL AND contact_requirement_version IS NULL AND " <>
            "contact_plan_id IS NULL AND contact_plan_version IS NULL AND " <>
            "contact_opportunity_snapshot_id IS NULL) OR " <>
            "(contact_requirement_id IS NOT NULL AND contact_requirement_version IS NOT NULL AND " <>
            "contact_plan_id IS NOT NULL AND contact_plan_version IS NOT NULL AND " <>
            "contact_opportunity_snapshot_id IS NOT NULL)"
      )
    )

    create(
      index(
        :provider_reservations,
        [:organization_id, :mission_id, :contact_plan_id, :contact_plan_version],
        name: :provider_reservations_contact_plan_idx,
        where: "contact_plan_id IS NOT NULL"
      )
    )

    execute("""
    ALTER TABLE provider_reservations
    ADD CONSTRAINT provider_reservations_contact_requirement_fk
    FOREIGN KEY (
      organization_id, mission_id, contact_requirement_id, contact_requirement_version
    )
    REFERENCES contact_requirement_versions (
      organization_id, mission_id, contact_requirement_id, version
    )
    """)

    execute("""
    ALTER TABLE provider_reservations
    ADD CONSTRAINT provider_reservations_contact_plan_fk
    FOREIGN KEY (organization_id, mission_id, contact_plan_id, contact_plan_version)
    REFERENCES contact_plan_versions (organization_id, mission_id, contact_plan_id, version)
    """)

    execute("""
    ALTER TABLE provider_reservations
    ADD CONSTRAINT provider_reservations_opportunity_snapshot_fk
    FOREIGN KEY (contact_opportunity_snapshot_id)
    REFERENCES contact_opportunity_snapshots (contact_opportunity_snapshot_id)
    """)

    create table(:contact_plan_execution_items, primary_key: false) do
      add(:contact_plan_execution_item_id, :string, primary_key: true)
      add(:organization_id, :string, null: false)
      add(:mission_id, :string, null: false)
      add(:contact_plan_id, :string, null: false)
      add(:contact_plan_version, :integer, null: false)
      add(:contact_opportunity_snapshot_id, :string, null: false)
      add(:idempotency_key, :string, null: false)
      add(:lifecycle_state, :string, null: false)
      add(:provider_reservation_id, :string)
      add(:attempt_count, :integer, null: false, default: 0)
      add(:last_error_document, :map, null: false, default: %{})
      add(:started_at, :utc_datetime_usec)
      add(:completed_at, :utc_datetime_usec)

      timestamps(type: :utc_datetime_usec)
    end

    create(
      unique_index(
        :contact_plan_execution_items,
        [:contact_plan_id, :contact_plan_version, :contact_opportunity_snapshot_id],
        name: :contact_plan_execution_items_selection_idx
      )
    )

    create(
      unique_index(:contact_plan_execution_items, [:mission_id, :idempotency_key],
        name: :contact_plan_execution_items_idempotency_idx
      )
    )

    create(
      index(
        :contact_plan_execution_items,
        [:organization_id, :mission_id, :lifecycle_state, :updated_at],
        name: :contact_plan_execution_items_state_idx
      )
    )

    create(
      constraint(:contact_plan_execution_items, :contact_plan_execution_items_state_check,
        check:
          "lifecycle_state IN ('pending', 'requesting', 'reserved', 'uncertain', " <>
            "'rejected', 'failed')"
      )
    )

    create(
      constraint(:contact_plan_execution_items, :contact_plan_execution_items_attempts_check,
        check: "attempt_count >= 0"
      )
    )

    execute("""
    ALTER TABLE contact_plan_execution_items
    ADD CONSTRAINT contact_plan_execution_items_plan_version_fk
    FOREIGN KEY (organization_id, mission_id, contact_plan_id, contact_plan_version)
    REFERENCES contact_plan_versions (organization_id, mission_id, contact_plan_id, version)
    """)

    execute("""
    ALTER TABLE contact_plan_execution_items
    ADD CONSTRAINT contact_plan_execution_items_snapshot_fk
    FOREIGN KEY (contact_opportunity_snapshot_id)
    REFERENCES contact_opportunity_snapshots (contact_opportunity_snapshot_id)
    """)

    execute("""
    ALTER TABLE contact_plan_execution_items
    ADD CONSTRAINT contact_plan_execution_items_reservation_fk
    FOREIGN KEY (provider_reservation_id)
    REFERENCES provider_reservations (provider_reservation_id)
    """)
  end

  def down do
    drop(table(:contact_plan_execution_items))

    execute("""
    ALTER TABLE provider_reservations
    DROP CONSTRAINT IF EXISTS provider_reservations_opportunity_snapshot_fk
    """)

    execute("""
    ALTER TABLE provider_reservations
    DROP CONSTRAINT IF EXISTS provider_reservations_contact_plan_fk
    """)

    execute("""
    ALTER TABLE provider_reservations
    DROP CONSTRAINT IF EXISTS provider_reservations_contact_requirement_fk
    """)

    drop_if_exists(
      index(
        :provider_reservations,
        [:organization_id, :mission_id, :contact_plan_id, :contact_plan_version],
        name: :provider_reservations_contact_plan_idx
      )
    )

    alter table(:provider_reservations) do
      remove(:contact_opportunity_snapshot_id)
      remove(:contact_plan_version)
      remove(:contact_plan_id)
      remove(:contact_requirement_version)
      remove(:contact_requirement_id)
    end
  end
end
