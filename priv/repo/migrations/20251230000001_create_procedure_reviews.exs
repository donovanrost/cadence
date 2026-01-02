defmodule Cadence.Repo.Migrations.CreateProcedureReviews do
  use Ecto.Migration

  def change do
    # Add submission tracking fields to procedure_versions
    alter table(:procedure_versions) do
      add :submitted_at, :utc_datetime
      add :submitted_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      # Legacy rejection fields (kept for backwards compatibility)
      add :rejected_at, :utc_datetime
      add :rejected_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :rejection_reason, :text
    end

    create index(:procedure_versions, [:submitted_by_id])

    # Create the reviews table
    create table(:procedure_reviews, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :procedure_version_id,
          references(:procedure_versions, type: :binary_id, on_delete: :delete_all),
          null: false

      add :user_id,
          references(:users, type: :binary_id, on_delete: :restrict),
          null: false

      # :approve or :request_changes
      add :decision, :string, null: false

      # Comment body - required for request_changes, optional for approve
      add :body, :text

      # When a user submits a new review, their previous reviews are marked superseded
      add :superseded, :boolean, default: false, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:procedure_reviews, [:procedure_version_id])
    create index(:procedure_reviews, [:user_id])

    # Index for finding a user's active (non-superseded) review for a version
    create index(:procedure_reviews, [:procedure_version_id, :user_id, :superseded])
  end
end
