defmodule Cadence.Repo.Migrations.CreateOrganizationMissionAndServiceIdentityFoundation do
  use Ecto.Migration

  def change do
    create table(:organizations, primary_key: false) do
      add :organization_id, :string, primary_key: true
      add :slug, :string, null: false
      add :display_name, :string, null: false
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:organizations, [:slug], name: :organizations_slug_idx)

    create table(:missions, primary_key: false) do
      add :mission_id, :string, primary_key: true
      add :organization_id, references(:organizations, column: :organization_id, type: :string),
        null: false

      add :slug, :string, null: false
      add :display_name, :string, null: false
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:missions, [:organization_id, :slug], name: :missions_org_slug_idx)

    create table(:service_identities, primary_key: false) do
      add :service_identity_id, :string, primary_key: true

      add :organization_id,
          references(:organizations, column: :organization_id, type: :string),
          null: false

      add :mission_id, references(:missions, column: :mission_id, type: :string)
      add :display_name, :string, null: false
      add :capabilities, {:array, :string}, null: false, default: []
      add :lifecycle_state, :string, null: false
      add :token_digest, :string, null: false
      add :token_hint, :string, null: false
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:service_identities, [:token_digest],
             name: :service_identities_token_digest_idx
           )
  end
end
