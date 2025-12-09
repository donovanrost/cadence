defmodule Cadence.Repo.Migrations.CreateProcedureVersionEvents do
  use Ecto.Migration

  def change do
    create table(:procedure_version_events, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :procedure_version_id,
          references(:procedure_versions, type: :binary_id, on_delete: :delete_all),
          null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :event_type, :string, null: false
      add :previous_state, :map
      add :new_state, :map
      add :note, :text
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:procedure_version_events, [:procedure_version_id, :inserted_at])
    create index(:procedure_version_events, [:user_id])
    create index(:procedure_version_events, [:event_type])
  end
end
