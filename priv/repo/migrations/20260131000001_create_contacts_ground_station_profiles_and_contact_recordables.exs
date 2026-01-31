defmodule Cadence.Repo.Migrations.CreateContactsGroundStationProfilesAndContactRecordables do
  use Ecto.Migration

  def change do
    create table(:contacts, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id,
          references(:organizations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :mission_id, references(:missions, type: :binary_id, on_delete: :delete_all),
        null: false

      add :spacecraft_target_id,
          references(:targets, type: :binary_id, on_delete: :restrict),
          null: false

      add :ground_station_target_id,
          references(:targets, type: :binary_id, on_delete: :restrict),
          null: false

      add :antenna_id, :string, null: false
      add :start_time, :utc_datetime_usec, null: false
      add :end_time, :utc_datetime_usec, null: false
      add :direction, :string, null: false
      add :state, :string, null: false, default: "planned"
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:contacts, [:mission_id, :start_time])
    create index(:contacts, [:mission_id, :end_time])
    create index(:contacts, [:ground_station_target_id])
    create index(:contacts, [:spacecraft_target_id])

    create table(:ground_station_profiles, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id,
          references(:organizations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :mission_id, references(:missions, type: :binary_id, on_delete: :delete_all),
        null: false

      add :ground_station_target_id,
          references(:targets, type: :binary_id, on_delete: :restrict),
          null: false

      add :name, :string, null: false
      add :enabled, :boolean, default: true
      add :resources, :map, default: %{}, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:ground_station_profiles, [:mission_id, :ground_station_target_id])

    create table(:contact_starteds, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :mission_id, :binary_id, null: false
      add :contact_id, :binary_id, null: false
      add :spacecraft_target_id, :binary_id, null: false
      add :ground_station_target_id, :binary_id, null: false
      add :antenna_id, :string, null: false
      add :direction, :string, null: false
      add :resolved_transport_ids, {:array, :binary_id}, default: []
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:contact_starteds, [:mission_id, :contact_id])

    create table(:contact_endeds, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :mission_id, :binary_id, null: false
      add :contact_id, :binary_id, null: false
      add :spacecraft_target_id, :binary_id, null: false
      add :ground_station_target_id, :binary_id, null: false
      add :antenna_id, :string, null: false
      add :direction, :string, null: false
      add :reason, :string, null: false, default: "completed"
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:contact_endeds, [:mission_id, :contact_id])

    create table(:contact_activation_faileds, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :mission_id, :binary_id, null: false
      add :contact_id, :binary_id, null: false
      add :spacecraft_target_id, :binary_id, null: false
      add :ground_station_target_id, :binary_id, null: false
      add :antenna_id, :string, null: false
      add :direction, :string, null: false
      add :error_code, :string, null: false
      add :error_message, :string
      add :details, :map, default: %{}
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:contact_activation_faileds, [:mission_id, :contact_id])
  end
end
