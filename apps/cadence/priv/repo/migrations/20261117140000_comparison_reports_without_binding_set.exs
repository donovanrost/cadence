defmodule Cadence.Repo.Migrations.ComparisonReportsWithoutBindingSet do
  use Ecto.Migration

  # A mission's first model revision is compared before the mission has any configuration
  # (lead's gate finding, director 11-17): such a report names no binding set. The pair is null
  # together or set together. The existing identity index never dedupes nulls (they're distinct in
  # PG 14), so a partial unique index dedupes a no-configuration report per revision and content.
  # Small table, plain DDL in the migration's transaction, run at a restart.
  @table :mission_model_comparison_reports

  def up do
    alter table(@table) do
      modify(:binding_set_id, :string, null: true, from: {:string, null: false})
      modify(:binding_set_version, :integer, null: true, from: {:integer, null: false})
    end

    create(
      constraint(@table, :mission_model_comparison_reports_binding_set_pair,
        check: "(binding_set_id IS NULL) = (binding_set_version IS NULL)"
      )
    )

    create(
      unique_index(
        @table,
        [:organization_id, :mission_id, :candidate_revision_id, :report_sha256],
        name: :mission_model_comparison_reports_no_binding_identity_idx,
        where: "binding_set_id IS NULL"
      )
    )
  end

  # Restores NOT NULL only when no report lacks a binding set; otherwise refuses, naming why.
  def down do
    execute("""
    DO $$
    BEGIN
      IF EXISTS (SELECT 1 FROM mission_model_comparison_reports WHERE binding_set_id IS NULL) THEN
        RAISE EXCEPTION 'mission_model_comparison_reports has reports without a binding set (a mission''s first revision); delete or keep them before restoring NOT NULL';
      END IF;
    END
    $$;
    """)

    drop(index(@table, [], name: :mission_model_comparison_reports_no_binding_identity_idx))
    drop(constraint(@table, :mission_model_comparison_reports_binding_set_pair))

    alter table(@table) do
      modify(:binding_set_id, :string, null: false, from: {:string, null: true})
      modify(:binding_set_version, :integer, null: false, from: {:integer, null: true})
    end
  end
end
