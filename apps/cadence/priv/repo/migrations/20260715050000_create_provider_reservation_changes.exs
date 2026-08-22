defmodule Cadence.Repo.Migrations.CreateProviderReservationChanges do
  use Ecto.Migration

  def up do
    alter table(:provider_reservations) do
      add(:provider_revision, :integer)
      add(:requested_snapshot_document, :map, null: false, default: %{})
      add(:provider_confirmed_snapshot_document, :map, null: false, default: %{})
      add(:cadence_accepted_snapshot_document, :map, null: false, default: %{})
    end

    execute("""
    UPDATE provider_reservations
    SET provider_revision = CASE
          WHEN response_document->>'provider_revision' ~ '^[1-9][0-9]*$'
            THEN (response_document->>'provider_revision')::integer
          ELSE 1
        END,
        requested_snapshot_document = COALESCE(request_document->'provider_request', request_document, '{}'::jsonb),
        provider_confirmed_snapshot_document = CASE
          WHEN response_document = '{}'::jsonb
            THEN COALESCE(request_document->'provider_request', request_document, '{}'::jsonb)
          ELSE response_document
        END,
        cadence_accepted_snapshot_document = CASE
          WHEN response_document = '{}'::jsonb
            THEN COALESCE(request_document->'provider_request', request_document, '{}'::jsonb)
          ELSE response_document
        END
    """)

    alter table(:provider_reservations) do
      modify(:provider_revision, :integer, null: false, default: 1)
    end

    create(
      constraint(:provider_reservations, :provider_reservations_provider_revision_positive,
        check: "provider_revision > 0"
      )
    )

    alter table(:scheduled_contacts) do
      add(:current_revision, :integer, null: false, default: 1)
    end

    create(
      constraint(:scheduled_contacts, :scheduled_contacts_current_revision_positive,
        check: "current_revision > 0"
      )
    )

    create table(:provider_reservation_changes, primary_key: false) do
      add(:provider_reservation_change_id, :string, primary_key: true)
      add(:organization_id, :string, null: false)
      add(:mission_id, :string, null: false)
      add(:provider_reservation_id, :string, null: false)
      add(:provider_account_id, :string)
      add(:provider_account_version, :integer)
      add(:provider_revision, :integer, null: false)
      add(:from_provider_revision, :integer, null: false)
      add(:change_identity, :string, null: false)
      add(:proposal_hash, :string, null: false)
      add(:before_snapshot_document, :map, null: false)
      add(:after_snapshot_document, :map, null: false)
      add(:changed_fields_document, :map, null: false)
      add(:classification, :string, null: false)
      add(:lifecycle_state, :string, null: false)
      add(:policy_version, :integer, null: false)
      add(:policy_document, :map, null: false)
      add(:decision_document, :map, null: false)
      add(:actionable, :boolean, null: false, default: false)
      add(:already_effective, :boolean, null: false, default: false)
      add(:deadline_at, :utc_datetime_usec)
      add(:provider_evidence_id, :string)
      add(:decided_at, :utc_datetime_usec)
      add(:decided_by, :string)
      timestamps(type: :utc_datetime_usec)
    end

    create(
      unique_index(
        :provider_reservation_changes,
        [:provider_reservation_id, :change_identity],
        name: :provider_reservation_changes_identity_idx
      )
    )

    create(
      index(:provider_reservation_changes, [:organization_id, :mission_id, :lifecycle_state],
        name: :provider_reservation_changes_queue_idx
      )
    )

    create(
      index(:provider_reservation_changes, [:provider_reservation_id, :provider_revision],
        name: :provider_reservation_changes_revision_idx
      )
    )

    create(
      constraint(:provider_reservation_changes, :provider_reservation_changes_state_check,
        check:
          "lifecycle_state IN ('observed', 'pending_approval', 'policy_accepted', 'approved', 'rejected', 'acknowledgment_required', 'acknowledged', 'configuration_failure', 'superseded', 'apply_failed')"
      )
    )

    create(
      constraint(:provider_reservation_changes, :provider_reservation_changes_revision_check,
        check: "provider_revision > from_provider_revision AND from_provider_revision > 0"
      )
    )

    create table(:provider_change_approvals, primary_key: false) do
      add(:provider_change_approval_id, :string, primary_key: true)
      add(:organization_id, :string, null: false)
      add(:mission_id, :string, null: false)
      add(:provider_reservation_change_id, :string, null: false)
      add(:decision, :string, null: false)
      add(:proposal_hash, :string, null: false)
      add(:policy_version, :integer, null: false)
      add(:reason, :string, null: false)
      add(:actor_user_id, :string, null: false)
      add(:actor_document, :map, null: false)
      add(:decided_at, :utc_datetime_usec, null: false)
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(
      unique_index(:provider_change_approvals, [:provider_reservation_change_id],
        name: :provider_change_approvals_change_idx
      )
    )

    create(
      constraint(:provider_change_approvals, :provider_change_approvals_decision_check,
        check: "decision IN ('approved', 'rejected', 'acknowledged')"
      )
    )

    create table(:scheduled_contact_revisions, primary_key: false) do
      add(:scheduled_contact_revision_id, :string, primary_key: true)
      add(:organization_id, :string, null: false)
      add(:mission_id, :string, null: false)
      add(:scheduled_contact_id, :string, null: false)
      add(:revision, :integer, null: false)
      add(:provider_reservation_change_id, :string)
      add(:snapshot_document, :map, null: false)
      add(:reason_document, :map, null: false)
      add(:created_by, :string, null: false)
      add(:created_at, :utc_datetime_usec, null: false)
    end

    create(
      unique_index(:scheduled_contact_revisions, [:scheduled_contact_id, :revision],
        name: :scheduled_contact_revisions_revision_idx
      )
    )

    create(
      unique_index(:scheduled_contact_revisions, [:provider_reservation_change_id],
        name: :scheduled_contact_revisions_change_idx,
        where: "provider_reservation_change_id IS NOT NULL"
      )
    )

    create(
      constraint(:scheduled_contact_revisions, :scheduled_contact_revisions_positive,
        check: "revision > 0"
      )
    )

    execute("""
    INSERT INTO scheduled_contact_revisions (
      scheduled_contact_revision_id,
      organization_id,
      mission_id,
      scheduled_contact_id,
      revision,
      snapshot_document,
      reason_document,
      created_by,
      created_at
    )
    SELECT
      'scheduled_contact_revision_' || md5(mission_id || ':' || scheduled_contact_id || ':1'),
      organization_id,
      mission_id,
      scheduled_contact_id,
      1,
      jsonb_build_object(
        'starts_at', starts_at,
        'ends_at', ends_at,
        'provider_contact_ref', provider_contact_ref,
        'source_endpoint_refs', source_endpoint_refs,
        'path_template_ids', path_template_ids,
        'lifecycle_state', lifecycle_state,
        'metadata', metadata
      ),
      jsonb_build_object('kind', 'stage_3_backfill'),
      'stage_3_migration',
      inserted_at
    FROM scheduled_contacts
    """)

    execute("""
    ALTER TABLE provider_reservation_changes
    ADD CONSTRAINT provider_reservation_changes_reservation_fk
    FOREIGN KEY (provider_reservation_id)
    REFERENCES provider_reservations (provider_reservation_id)
    """)

    execute("""
    ALTER TABLE provider_change_approvals
    ADD CONSTRAINT provider_change_approvals_change_fk
    FOREIGN KEY (provider_reservation_change_id)
    REFERENCES provider_reservation_changes (provider_reservation_change_id)
    """)

    execute("""
    ALTER TABLE scheduled_contact_revisions
    ADD CONSTRAINT scheduled_contact_revisions_contact_fk
    FOREIGN KEY (scheduled_contact_id)
    REFERENCES scheduled_contacts (scheduled_contact_id)
    """)

    execute("""
    ALTER TABLE scheduled_contact_revisions
    ADD CONSTRAINT scheduled_contact_revisions_change_fk
    FOREIGN KEY (provider_reservation_change_id)
    REFERENCES provider_reservation_changes (provider_reservation_change_id)
    """)
  end

  def down do
    drop(table(:scheduled_contact_revisions))
    drop(table(:provider_change_approvals))
    drop(table(:provider_reservation_changes))

    alter table(:scheduled_contacts) do
      remove(:current_revision)
    end

    alter table(:provider_reservations) do
      remove(:provider_revision)
      remove(:requested_snapshot_document)
      remove(:provider_confirmed_snapshot_document)
      remove(:cadence_accepted_snapshot_document)
    end
  end
end
