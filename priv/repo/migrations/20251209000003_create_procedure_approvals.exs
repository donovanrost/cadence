defmodule Cadence.Repo.Migrations.CreateProcedureApprovals do
  use Ecto.Migration

  def change do
    create table(:procedure_approvals, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :procedure_version_id,
          references(:procedure_versions, type: :binary_id, on_delete: :delete_all),
          null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :nilify_all), null: false
      add :decision, :string, null: false
      add :comment, :text

      timestamps(type: :utc_datetime)
    end

    # Each user can only approve/reject once per version
    create unique_index(:procedure_approvals, [:procedure_version_id, :user_id])
    create index(:procedure_approvals, [:procedure_version_id])
    create index(:procedure_approvals, [:user_id])
  end
end
