defmodule Cadence.Repo.Migrations.CreateContactBlockedAndSkippedRecordables do
  use Ecto.Migration

  def change do
    create table(:contact_blockeds, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :mission_id, :binary_id, null: false
      add :contact_id, :binary_id, null: false
      add :spacecraft_target_id, :binary_id, null: false
      add :ground_station_target_id, :binary_id, null: false
      add :antenna_id, :string, null: false
      add :direction, :string, null: false
      add :blocked_by_contact_id, :binary_id, null: false
      add :policy, :string, null: false
      add :message, :string
      add :details, :map, default: %{}
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:contact_blockeds, [:mission_id, :contact_id])

    create table(:contact_skippeds, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :mission_id, :binary_id, null: false
      add :contact_id, :binary_id, null: false
      add :spacecraft_target_id, :binary_id, null: false
      add :ground_station_target_id, :binary_id, null: false
      add :antenna_id, :string, null: false
      add :direction, :string, null: false
      add :reason, :string, null: false, default: "resource_unavailable"
      add :details, :map, default: %{}
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:contact_skippeds, [:mission_id, :contact_id])
  end
end
