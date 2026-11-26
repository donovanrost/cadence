defmodule Cadence.Repo.Migrations.CreateSpacecraftConfigurationReviews do
  use Ecto.Migration

  # Review evidence out of activation metadata (#734). A configuration review's per-spacecraft
  # evidence (which saved version was reviewed, under which token) is stored once per set, by its
  # hash, like the fleet (activation_fleets); the activation metadata carries only the reference.
  def up do
    create table(:spacecraft_configuration_reviews, primary_key: false) do
      add(:mission_id, :string, primary_key: true)
      add(:review_sha256, :string, primary_key: true)
      add(:organization_id, :string)
      add(:spacecraft_count, :integer, null: false)
      add(:inserted_at, :utc_datetime_usec, null: false)
    end

    create table(:spacecraft_configuration_review_members, primary_key: false) do
      add(:mission_id, :string, primary_key: true)
      add(:review_sha256, :string, primary_key: true)
      add(:spacecraft_id, :string, primary_key: true)
      add(:organization_id, :string)
      add(:configuration_revision_id, :string, null: false)
      add(:configuration_token, :string, null: false)
    end

    # "The latest review of this spacecraft" joins through here instead of scanning request metadata.
    create(
      index(:spacecraft_configuration_review_members, [:mission_id, :spacecraft_id],
        name: :spacecraft_configuration_review_members_spacecraft_idx
      )
    )

    for table <- [:spacecraft_configuration_reviews, :spacecraft_configuration_review_members] do
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
  end

  def down do
    drop(table(:spacecraft_configuration_review_members))
    drop(table(:spacecraft_configuration_reviews))
  end
end
