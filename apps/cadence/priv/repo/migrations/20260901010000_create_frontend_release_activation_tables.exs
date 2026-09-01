defmodule Cadence.Repo.Migrations.CreateFrontendReleaseActivationTables do
  use Ecto.Migration

  def up do
    alter table(:frontend_release_catalog_publications) do
      add(:transition, :string, null: true)
      add(:identity_count, :integer, null: true)
      add(:snapshot_digest, :string, null: true)
    end

    create(
      constraint(
        :frontend_release_catalog_publications,
        :frcp_v2_transition_fields_check,
        check:
          "(transition IS NULL AND identity_count IS NULL AND snapshot_digest IS NULL) OR (transition IS NOT NULL AND identity_count IS NOT NULL AND snapshot_digest IS NOT NULL AND transition IN ('initial', 'legacy_successor', 'promotion', 'rollback') AND identity_count > 0 AND snapshot_digest ~ '^sha256:[0-9a-f]{64}$')"
      )
    )

    create table(:frontend_release_activation_controls, primary_key: false) do
      add(:control_id, :integer, primary_key: true)
      add(:cutover_epoch, :bigint, null: false, default: 0)
      add(:cutover_at, :utc_datetime_usec)

      add(
        :legacy_catalog_publication_id,
        references(:frontend_release_catalog_publications,
          column: :publication_id,
          type: :string,
          on_delete: :restrict
        )
      )
    end

    create(
      constraint(
        :frontend_release_activation_controls,
        :frontend_release_activation_controls_singleton_check,
        check: "control_id = 1"
      )
    )

    create(
      constraint(
        :frontend_release_activation_controls,
        :frontend_release_activation_controls_cutover_check,
        check:
          "(cutover_epoch = 0 AND cutover_at IS NULL AND legacy_catalog_publication_id IS NULL) OR (cutover_epoch > 0 AND cutover_at IS NOT NULL)"
      )
    )

    execute("""
    CREATE FUNCTION cadence_guard_frontend_release_activation_control()
    RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    BEGIN
      IF OLD.cutover_epoch = 0 THEN
        IF NEW.cutover_epoch <> 1 OR NEW.cutover_at IS NULL THEN
          RAISE EXCEPTION 'frontend release activation control can only cut over from epoch zero to one';
        END IF;
      ELSE
        IF NEW.cutover_epoch <> OLD.cutover_epoch
           OR NEW.cutover_at IS DISTINCT FROM OLD.cutover_at
           OR NEW.legacy_catalog_publication_id IS DISTINCT FROM OLD.legacy_catalog_publication_id THEN
          RAISE EXCEPTION 'frontend release activation control is immutable after cutover';
        END IF;
      END IF;

      RETURN NEW;
    END;
    $$
    """)

    execute("""
    CREATE TRIGGER frontend_release_activation_controls_transition_guard
    BEFORE UPDATE ON frontend_release_activation_controls
    FOR EACH ROW
    EXECUTE FUNCTION cadence_guard_frontend_release_activation_control()
    """)

    execute("""
    CREATE TRIGGER frontend_release_activation_controls_delete_guard
    BEFORE DELETE ON frontend_release_activation_controls
    FOR EACH ROW
    EXECUTE FUNCTION cadence_reject_frontend_release_publication_mutation()
    """)

    execute("""
    CREATE TRIGGER frontend_release_activation_controls_truncate_protection
    BEFORE TRUNCATE ON frontend_release_activation_controls
    FOR EACH STATEMENT
    EXECUTE FUNCTION cadence_reject_frontend_release_publication_mutation()
    """)

    execute("""
    INSERT INTO frontend_release_activation_controls
      (control_id, cutover_epoch, cutover_at, legacy_catalog_publication_id)
    VALUES (1, 0, NULL, NULL)
    """)

    create table(:frontend_release_catalog_generations, primary_key: false) do
      add(:generation_id, :string, primary_key: true)

      add(
        :catalog_publication_id,
        references(:frontend_release_catalog_publications,
          column: :publication_id,
          type: :string,
          on_delete: :restrict
        ),
        null: false
      )

      add(:sequence, :bigint, null: false)
      add(:identity_count, :integer, null: false)
      add(:predecessor_kind, :string, null: false)

      add(
        :predecessor_catalog_publication_id,
        references(:frontend_release_catalog_publications,
          column: :publication_id,
          type: :string,
          on_delete: :restrict
        )
      )

      add(:inserted_at, :utc_datetime_usec, null: false)
    end

    create(
      unique_index(:frontend_release_catalog_generations, [:catalog_publication_id],
        name: :frcg_catalog_publication_idx
      )
    )

    create(
      unique_index(:frontend_release_catalog_generations, [:sequence], name: :frcg_sequence_idx)
    )

    create(
      constraint(:frontend_release_catalog_generations, :frcg_sequence_check,
        check: "sequence > 0"
      )
    )

    create(
      constraint(:frontend_release_catalog_generations, :frcg_identity_count_check,
        check: "identity_count > 0"
      )
    )

    create(
      constraint(:frontend_release_catalog_generations, :frcg_predecessor_check,
        check:
          "(predecessor_kind = 'none' AND predecessor_catalog_publication_id IS NULL) OR (predecessor_kind IN ('legacy', 'generation') AND predecessor_catalog_publication_id IS NOT NULL)"
      )
    )

    create table(:frontend_release_catalog_bindings, primary_key: false) do
      add(
        :generation_id,
        references(:frontend_release_catalog_generations,
          column: :generation_id,
          type: :string,
          on_delete: :restrict
        ),
        null: false
      )

      add(:application_id, :string, null: false)
      add(:application_version, :integer, null: false)
      add(:package_id, :string, null: false)
      add(:package_version, :integer, null: false)
      add(:surface_id, :string, null: false)
      add(:surface_version, :integer, null: false)
      add(:current_publication_id, :string, null: false)
      add(:current_release_id, :string, null: false)
      add(:previous_publication_id, :string)
      add(:previous_release_id, :string)
      add(:inserted_at, :utc_datetime_usec, null: false)
    end

    create(
      index(:frontend_release_catalog_bindings, [:generation_id], name: :frcb_generation_idx)
    )

    execute("""
    ALTER TABLE frontend_release_catalog_bindings
    ADD CONSTRAINT frcb_current_release_fk
    FOREIGN KEY (current_publication_id, current_release_id)
    REFERENCES frontend_release_publications (publication_id, release_id)
    MATCH FULL
    ON UPDATE RESTRICT
    ON DELETE RESTRICT
    """)

    execute("""
    ALTER TABLE frontend_release_catalog_bindings
    ADD CONSTRAINT frcb_previous_release_fk
    FOREIGN KEY (previous_publication_id, previous_release_id)
    REFERENCES frontend_release_publications (publication_id, release_id)
    MATCH FULL
    ON UPDATE RESTRICT
    ON DELETE RESTRICT
    """)

    create(
      constraint(:frontend_release_catalog_bindings, :frcb_current_pair_check,
        check: "current_publication_id IS NOT NULL AND current_release_id IS NOT NULL"
      )
    )

    create(
      constraint(:frontend_release_catalog_bindings, :frcb_previous_pair_check,
        check:
          "(previous_publication_id IS NULL AND previous_release_id IS NULL) OR (previous_publication_id IS NOT NULL AND previous_release_id IS NOT NULL)"
      )
    )

    create(
      constraint(:frontend_release_catalog_bindings, :frcb_identity_version_check,
        check: "application_version > 0 AND package_version > 0 AND surface_version > 0"
      )
    )

    create table(:frontend_release_activation_requests, primary_key: false) do
      add(:request_id, :string, primary_key: true)
      add(:idempotency_key_digest, :string, null: false)
      add(:document_digest, :string, null: false)
      add(:outcome, :string, null: false)
      add(:response_status, :integer, null: false)
      add(:response_body, :binary, null: false)

      add(
        :catalog_publication_id,
        references(:frontend_release_catalog_publications,
          column: :publication_id,
          type: :string,
          on_delete: :restrict
        )
      )

      add(
        :generation_id,
        references(:frontend_release_catalog_generations,
          column: :generation_id,
          type: :string,
          on_delete: :restrict
        )
      )

      add(:publisher_identity, :string)
      add(:inserted_at, :utc_datetime_usec, null: false)
    end

    create(
      unique_index(:frontend_release_activation_requests, [:idempotency_key_digest],
        name: :frar_idempotency_key_idx
      )
    )

    create(
      unique_index(:frontend_release_activation_requests, [:catalog_publication_id],
        name: :frar_catalog_publication_idx
      )
    )

    create(
      unique_index(:frontend_release_activation_requests, [:generation_id],
        name: :frar_generation_idx
      )
    )

    create(
      constraint(:frontend_release_activation_requests, :frar_idempotency_key_digest_check,
        check: "idempotency_key_digest ~ '^sha256:[0-9a-f]{64}$'"
      )
    )

    create(
      constraint(:frontend_release_activation_requests, :frar_document_digest_check,
        check: "document_digest ~ '^sha256:[0-9a-f]{64}$'"
      )
    )

    create(
      constraint(:frontend_release_activation_requests, :frar_outcome_check,
        check: "outcome IN ('initial', 'legacy_successor', 'promotion', 'rollback', 'rejected')"
      )
    )

    create(
      constraint(:frontend_release_activation_requests, :frar_response_status_check,
        check: "response_status IN (201, 422)"
      )
    )

    create(
      constraint(:frontend_release_activation_requests, :frar_response_body_check,
        check: "octet_length(response_body) > 0 AND octet_length(response_body) <= 16384"
      )
    )

    create(
      constraint(:frontend_release_activation_requests, :frar_outcome_response_check,
        check:
          "((outcome = 'rejected' AND response_status = 422 AND catalog_publication_id IS NULL AND generation_id IS NULL) OR (outcome IN ('initial', 'legacy_successor', 'promotion', 'rollback') AND response_status = 201 AND catalog_publication_id IS NOT NULL AND generation_id IS NOT NULL))"
      )
    )

    create(
      constraint(:frontend_release_activation_requests, :frar_publisher_identity_check,
        check:
          "publisher_identity IS NULL OR (octet_length(publisher_identity) > 0 AND octet_length(publisher_identity) <= 128)"
      )
    )

    protect_immutable(:frontend_release_catalog_generations)
    protect_immutable(:frontend_release_catalog_bindings)
    protect_immutable(:frontend_release_activation_requests)

    execute("""
    CREATE FUNCTION cadence_require_frontend_release_catalog_generation()
    RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    DECLARE
      cutover bigint;
    BEGIN
      SELECT cutover_epoch INTO cutover
      FROM frontend_release_activation_controls
      WHERE control_id = 1;

      IF cutover > 0 AND NOT EXISTS (
        SELECT 1 FROM frontend_release_catalog_generations
        WHERE catalog_publication_id = NEW.publication_id
      ) THEN
        RAISE EXCEPTION 'accepted frontend release catalog publication requires a generation after cutover';
      END IF;

      RETURN NEW;
    END;
    $$
    """)

    execute("""
    CREATE CONSTRAINT TRIGGER frontend_release_catalog_publications_generation_guard
    AFTER INSERT ON frontend_release_catalog_publications
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW
    WHEN (NEW.acceptance_state = 'accepted')
    EXECUTE FUNCTION cadence_require_frontend_release_catalog_generation()
    """)
  end

  def down do
    refuse_if_populated()

    execute(
      "DROP TRIGGER IF EXISTS frontend_release_catalog_publications_generation_guard ON frontend_release_catalog_publications"
    )

    execute("DROP FUNCTION IF EXISTS cadence_require_frontend_release_catalog_generation()")

    drop_protection(:frontend_release_activation_requests)
    drop_protection(:frontend_release_catalog_bindings)
    drop_protection(:frontend_release_catalog_generations)

    drop(table(:frontend_release_activation_requests))
    drop(table(:frontend_release_catalog_bindings))
    drop(table(:frontend_release_catalog_generations))

    execute(
      "DROP TRIGGER IF EXISTS frontend_release_activation_controls_transition_guard ON frontend_release_activation_controls"
    )

    execute(
      "DROP TRIGGER IF EXISTS frontend_release_activation_controls_delete_guard ON frontend_release_activation_controls"
    )

    execute(
      "DROP TRIGGER IF EXISTS frontend_release_activation_controls_truncate_protection ON frontend_release_activation_controls"
    )

    execute("DROP FUNCTION IF EXISTS cadence_guard_frontend_release_activation_control()")
    drop(table(:frontend_release_activation_controls))

    drop(constraint(:frontend_release_catalog_publications, :frcp_v2_transition_fields_check))

    alter table(:frontend_release_catalog_publications) do
      remove(:snapshot_digest)
      remove(:identity_count)
      remove(:transition)
    end
  end

  defp protect_immutable(table) do
    execute("""
    CREATE TRIGGER #{table}_immutable
    BEFORE UPDATE OR DELETE ON #{table}
    FOR EACH ROW
    EXECUTE FUNCTION cadence_reject_frontend_release_publication_mutation()
    """)

    execute("""
    CREATE TRIGGER #{table}_truncate_protection
    BEFORE TRUNCATE ON #{table}
    FOR EACH STATEMENT
    EXECUTE FUNCTION cadence_reject_frontend_release_publication_mutation()
    """)
  end

  defp drop_protection(table) do
    execute("DROP TRIGGER IF EXISTS #{table}_immutable ON #{table}")
    execute("DROP TRIGGER IF EXISTS #{table}_truncate_protection ON #{table}")
  end

  defp refuse_if_populated do
    migration_repo = repo()

    [[epoch]] =
      migration_repo.query!(
        "SELECT cutover_epoch FROM frontend_release_activation_controls WHERE control_id = 1"
      ).rows

    if epoch != 0 do
      migration_failure!(:nonzero_cutover_epoch)
    end

    for {table, predicate} <- [
          {"frontend_release_catalog_publications",
           "transition IS NOT NULL OR identity_count IS NOT NULL OR snapshot_digest IS NOT NULL"},
          {"frontend_release_catalog_generations", "TRUE"},
          {"frontend_release_catalog_bindings", "TRUE"},
          {"frontend_release_activation_requests", "TRUE"}
        ] do
      %{rows: [[count]]} =
        migration_repo.query!("SELECT COUNT(*) FROM #{table} WHERE #{predicate}")

      if count != 0, do: migration_failure!({table, count})
    end
  end

  defp migration_failure!(reason) do
    raise Ecto.MigrationError,
          "cannot reverse frontend release activation state: #{inspect(reason)}"
  end
end
