defmodule Cadence.Repo.Migrations.CreateSpacecraftConfigurationReviews do
  use Ecto.Migration

  # Review evidence and a change set's changed spacecraft out of activation metadata (#734). A
  # configuration review's per-spacecraft evidence (which saved version was reviewed, under which
  # token) is stored once per set, by its hash, like the fleet (activation_fleets); a change set's
  # generation names its changed spacecraft in a table keyed by change set id and revision. The
  # activation metadata carries only the reference, so it stays constant-size.
  # The evidence an approval rests on is insert-only and never deleted (DECISIONS #107), with the
  # decision records' own function and test-only purge (migration 20261117160000).
  @append_only ~w(
    spacecraft_configuration_reviews
    spacecraft_configuration_review_members
    activation_change_set_spacecraft
  )

  def up do
    create table(:spacecraft_configuration_reviews, primary_key: false) do
      add(:mission_id, :string, primary_key: true)
      add(:review_sha256, :string, primary_key: true)
      add(:organization_id, :string, null: false)
      add(:spacecraft_count, :integer, null: false)
      add(:inserted_at, :utc_datetime_usec, null: false)
    end

    create table(:spacecraft_configuration_review_members, primary_key: false) do
      add(:mission_id, :string, primary_key: true)
      add(:review_sha256, :string, primary_key: true)
      add(:spacecraft_id, :string, primary_key: true)
      add(:organization_id, :string, null: false)
      add(:configuration_revision_id, :string, null: false)
      add(:configuration_token, :string, null: false)
    end

    create table(:activation_change_set_spacecraft, primary_key: false) do
      add(:mission_id, :string, primary_key: true)
      add(:change_set_id, :string, primary_key: true)
      add(:revision, :integer, primary_key: true)
      add(:spacecraft_id, :string, primary_key: true)
      add(:organization_id, :string, null: false)
    end

    # "The latest review of this spacecraft" joins through here instead of scanning request metadata.
    create(
      index(
        :spacecraft_configuration_review_members,
        [:organization_id, :mission_id, :spacecraft_id],
        name: :spacecraft_configuration_review_members_spacecraft_idx
      )
    )

    create(
      index(:activation_change_set_spacecraft, [:organization_id, :mission_id, :spacecraft_id],
        name: :activation_change_set_spacecraft_spacecraft_idx
      )
    )

    # ...and a request is found from a review by this expression, not by a scan.
    execute("""
    CREATE INDEX activation_requests_review_sha256_idx
    ON activation_requests (organization_id, mission_id,
      ((metadata #>> '{value,configuration_review,review,sha256}')))
    WHERE (metadata #>> '{value,configuration_review,review,sha256}') IS NOT NULL
    """)

    for table <- [
          :spacecraft_configuration_reviews,
          :spacecraft_configuration_review_members,
          :activation_change_set_spacecraft
        ] do
      execute("""
      ALTER TABLE #{table}
      ADD CONSTRAINT #{table}_org_mission_fk
      FOREIGN KEY (organization_id, mission_id)
      REFERENCES missions (organization_id, mission_id)
      """)

      execute("""
      CREATE TRIGGER sync_organization_id_from_mission
      BEFORE INSERT OR UPDATE OF mission_id, organization_id ON #{table}
      FOR EACH ROW
      EXECUTE FUNCTION cadence_sync_organization_id_from_mission()
      """)
    end

    for table <- @append_only do
      execute("""
      CREATE TRIGGER #{table}_append_only_rows
        BEFORE UPDATE OR DELETE ON #{table}
        FOR EACH ROW EXECUTE FUNCTION cadence_decision_record_append_only();
      """)

      execute("""
      CREATE TRIGGER #{table}_append_only_truncate
        BEFORE TRUNCATE ON #{table}
        FOR EACH STATEMENT EXECUTE FUNCTION cadence_decision_record_append_only();
      """)
    end
  end

  def down do
    for table <- @append_only do
      execute("DROP TRIGGER IF EXISTS #{table}_append_only_truncate ON #{table};")
      execute("DROP TRIGGER IF EXISTS #{table}_append_only_rows ON #{table};")
    end

    execute("DROP INDEX activation_requests_review_sha256_idx")
    drop(table(:activation_change_set_spacecraft))
    drop(table(:spacecraft_configuration_review_members))
    drop(table(:spacecraft_configuration_reviews))
  end
end
