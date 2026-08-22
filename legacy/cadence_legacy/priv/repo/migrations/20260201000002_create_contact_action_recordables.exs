defmodule Cadence.Repo.Migrations.CreateContactActionRecordables do
  use Ecto.Migration

  def change do
    create table(:contact_readies, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :mission_id, :binary_id, null: false
      add :contact_id, :binary_id, null: false
      add :gate, :string, null: false
      add :details, :map, default: %{}
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:contact_readies, [:mission_id, :contact_id])

    create table(:contact_action_dispatcheds, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :mission_id, :binary_id, null: false
      add :contact_id, :binary_id, null: false
      add :contact_action_id, :binary_id, null: false
      add :gate, :string, null: false
      add :command_ref, :map, null: false
      add :details, :map, default: %{}
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:contact_action_dispatcheds, [:contact_action_id])
    create index(:contact_action_dispatcheds, [:mission_id, :contact_id])

    create table(:contact_action_completeds, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :mission_id, :binary_id, null: false
      add :contact_id, :binary_id, null: false
      add :contact_action_id, :binary_id, null: false
      add :result, :map, default: %{}
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:contact_action_completeds, [:mission_id, :contact_id])

    create table(:contact_action_faileds, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :mission_id, :binary_id, null: false
      add :contact_id, :binary_id, null: false
      add :contact_action_id, :binary_id, null: false
      add :error_code, :string, null: false
      add :error_message, :string
      add :details, :map, default: %{}
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:contact_action_faileds, [:mission_id, :contact_id])

    create table(:contact_action_skippeds, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :mission_id, :binary_id, null: false
      add :contact_id, :binary_id, null: false
      add :contact_action_id, :binary_id, null: false
      add :reason, :string, null: false
      add :details, :map, default: %{}
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:contact_action_skippeds, [:mission_id, :contact_id])
  end
end
