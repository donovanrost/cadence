defmodule Cadence.Repo.Migrations.BindingSetMembershipStorage do
  use Ecto.Migration

  # #447 (mission-model overhaul phase 4a; config-materialization-model.md §4 step 1): a binding-set
  # version can be stored as content-addressed artifacts (one template per distinct configuration,
  # the source endpoint as a parameter) plus a membership list, instead of the craft × packet rows.
  # Additive: every existing version keeps storage_form 'rows' and reads exactly as before, so no
  # backfill and no reset.
  #
  # api-ops' conditions (11-19):
  # - artifacts are insert-only, and can't be deleted while a member references them;
  # - a member resolves its artifact by (organization, mission, sha), never across tenants, and its
  #   own organization and mission are its binding set's;
  # - one member per endpoint per version, the mission-scoped (null endpoint) one included;
  # - a version's storage_form, stored content_sha256, member_count and members_sha256 are written
  #   with it and never change.
  def up do
    alter table(:governed_binding_sets) do
      add(:storage_form, :string, null: false, default: "rows")
      add(:content_sha256, :string)
      # Commanding (#450): what admission recomputes from the members it reads, so a member added
      # after the version was written (or an artifact swapped under one) is refused closed.
      add(:member_count, :integer)
      add(:members_sha256, :string, collation: "C")
    end

    create(
      constraint(:governed_binding_sets, :governed_binding_sets_storage_form,
        check:
          "(storage_form = 'rows' AND content_sha256 IS NULL AND member_count IS NULL " <>
            "AND members_sha256 IS NULL) OR " <>
            "(storage_form = 'membership' AND content_sha256 IS NOT NULL " <>
            "AND member_count IS NOT NULL AND members_sha256 IS NOT NULL " <>
            "AND organization_id IS NOT NULL)"
      )
    )

    create(
      unique_index(:governed_binding_sets, [:id, :organization_id, :mission_id],
        name: :governed_binding_sets_tenant_idx
      )
    )

    create table(:governed_binding_artifacts, primary_key: false) do
      add(:organization_id, :string, null: false, primary_key: true, collation: "C")
      add(:mission_id, :string, null: false, primary_key: true, collation: "C")
      add(:artifact_sha256, :string, null: false, primary_key: true, collation: "C")
      add(:template, :map, null: false)

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create table(:governed_binding_set_members) do
      add(:binding_set_row_id, :bigint, null: false)
      add(:organization_id, :string, null: false, collation: "C")
      add(:mission_id, :string, null: false, collation: "C")
      add(:artifact_sha256, :string, null: false, collation: "C")
      add(:source_endpoint_ref, :string, collation: "C")

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    # RESTRICT on the set too (fe-setup, #475): unlike the rows form's children, which CASCADE, a
    # version's members are never deleted (trigger below), so pruning a membership version is a
    # deliberate later change, not a side effect of deleting its row.
    execute("""
    ALTER TABLE governed_binding_set_members
      ADD CONSTRAINT governed_binding_set_members_set_fkey
        FOREIGN KEY (binding_set_row_id, organization_id, mission_id)
        REFERENCES governed_binding_sets (id, organization_id, mission_id) ON DELETE RESTRICT,
      ADD CONSTRAINT governed_binding_set_members_artifact_fkey
        FOREIGN KEY (organization_id, mission_id, artifact_sha256)
        REFERENCES governed_binding_artifacts (organization_id, mission_id, artifact_sha256)
        ON DELETE RESTRICT
    """)

    # Null-safe: a version has one mission-scoped member at most (laptop Postgres is 14, so no
    # NULLS NOT DISTINCT). Source endpoint ids are never empty.
    execute("""
    CREATE UNIQUE INDEX governed_binding_set_members_endpoint_idx
      ON governed_binding_set_members (binding_set_row_id, COALESCE(source_endpoint_ref, ''))
    """)

    execute("""
    CREATE FUNCTION governed_binding_insert_only() RETURNS trigger AS $$
    BEGIN
      RAISE EXCEPTION '% is insert-only (#447)', TG_TABLE_NAME;
    END;
    $$ LANGUAGE plpgsql
    """)

    # Artifacts: no UPDATE (a referenced one can't be deleted either: RESTRICT; an unreferenced
    # one may be collected later). Members: no UPDATE or DELETE, so a version's membership is
    # exactly what was written with it (api-ops, #475).
    execute("""
    CREATE TRIGGER governed_binding_artifacts_insert_only BEFORE UPDATE ON governed_binding_artifacts
      FOR EACH ROW EXECUTE FUNCTION governed_binding_insert_only()
    """)

    execute("""
    CREATE TRIGGER governed_binding_set_members_insert_only
      BEFORE UPDATE OR DELETE ON governed_binding_set_members
      FOR EACH ROW EXECUTE FUNCTION governed_binding_insert_only()
    """)

    execute("""
    CREATE FUNCTION governed_binding_set_storage_immutable() RETURNS trigger AS $$
    BEGIN
      IF NEW.storage_form IS DISTINCT FROM OLD.storage_form
         OR NEW.content_sha256 IS DISTINCT FROM OLD.content_sha256
         OR NEW.member_count IS DISTINCT FROM OLD.member_count
         OR NEW.members_sha256 IS DISTINCT FROM OLD.members_sha256 THEN
        RAISE EXCEPTION 'a binding set version''s storage_form, content_sha256, member_count and members_sha256 are immutable (#447)';
      END IF;
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql
    """)

    execute("""
    CREATE TRIGGER governed_binding_sets_storage_immutable BEFORE UPDATE ON governed_binding_sets
      FOR EACH ROW EXECUTE FUNCTION governed_binding_set_storage_immutable()
    """)
  end

  def down do
    execute("DROP TRIGGER governed_binding_sets_storage_immutable ON governed_binding_sets")

    execute("DROP FUNCTION governed_binding_set_storage_immutable()")
    drop(table(:governed_binding_set_members))
    drop(table(:governed_binding_artifacts))
    execute("DROP FUNCTION governed_binding_insert_only()")

    drop(
      index(:governed_binding_sets, [:id, :organization_id, :mission_id],
        name: :governed_binding_sets_tenant_idx
      )
    )

    drop(constraint(:governed_binding_sets, :governed_binding_sets_storage_form))

    alter table(:governed_binding_sets) do
      remove(:members_sha256)
      remove(:member_count)
      remove(:content_sha256)
      remove(:storage_form)
    end
  end
end
