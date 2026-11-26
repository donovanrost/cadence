defmodule Cadence.Repo.Migrations.ServiceIdentityAccountablesAppendOnly do
  use Ecto.Migration

  # #436 (ca-security's review of #280): who counts as "self" for every approval kind under
  # 'independent' comes from service_identity_accountables, so its rows are INSERT-ONLY, as the
  # decision records are (#116, migration 20261117160000): row triggers refuse UPDATE and DELETE,
  # a statement trigger refuses TRUNCATE, with #116's own function and its test-only purge (a
  # cadence_test database only). Removing an accountable person would let them approve their
  # service's work; deleting an issued row would force everyone into authors_unknown.
  #
  # The foreign key to service_identities restricts, so deleting an identity can't take its
  # accountable rows with it. Existing rows are kept and read as before; no data changes.
  @fk "service_identity_accountables_service_identity_id_fkey"

  def up do
    execute("""
    ALTER TABLE service_identity_accountables DROP CONSTRAINT #{@fk},
      ADD CONSTRAINT #{@fk} FOREIGN KEY (service_identity_id)
      REFERENCES service_identities (service_identity_id) ON DELETE RESTRICT;
    """)

    execute("""
    CREATE TRIGGER service_identity_accountables_append_only_rows
      BEFORE UPDATE OR DELETE ON service_identity_accountables
      FOR EACH ROW EXECUTE FUNCTION cadence_decision_record_append_only();
    """)

    execute("""
    CREATE TRIGGER service_identity_accountables_append_only_truncate
      BEFORE TRUNCATE ON service_identity_accountables
      FOR EACH STATEMENT EXECUTE FUNCTION cadence_decision_record_append_only();
    """)
  end

  def down do
    execute(
      "DROP TRIGGER IF EXISTS service_identity_accountables_append_only_truncate ON service_identity_accountables;"
    )

    execute(
      "DROP TRIGGER IF EXISTS service_identity_accountables_append_only_rows ON service_identity_accountables;"
    )

    execute("""
    ALTER TABLE service_identity_accountables DROP CONSTRAINT #{@fk},
      ADD CONSTRAINT #{@fk} FOREIGN KEY (service_identity_id)
      REFERENCES service_identities (service_identity_id);
    """)
  end
end
