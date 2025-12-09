defmodule Cadence.Repo.Migrations.AddApprovalFieldsToProcedureVersions do
  use Ecto.Migration

  def change do
    alter table(:procedure_versions) do
      add :submitted_at, :utc_datetime
      add :submitted_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :rejected_at, :utc_datetime
      add :rejected_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :rejection_reason, :text
    end

    create index(:procedure_versions, [:submitted_by_id])
  end
end
