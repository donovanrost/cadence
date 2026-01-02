defmodule Cadence.Repo.Migrations.CreateProcedureReviewRequests do
  use Ecto.Migration

  def change do
    create table(:procedure_review_requests, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :procedure_version_id,
          references(:procedure_versions, type: :binary_id, on_delete: :delete_all),
          null: false

      # Who requested the review
      add :requester_id,
          references(:users, type: :binary_id, on_delete: :restrict),
          null: false

      # Who should review
      add :reviewer_id,
          references(:users, type: :binary_id, on_delete: :restrict),
          null: false

      # :pending, :completed, or :cancelled
      add :status, :string, default: "pending", null: false

      # Optional message from requester
      add :message, :text

      add :completed_at, :utc_datetime_usec

      timestamps(type: :utc_datetime)
    end

    # For the reviewer's inbox - find pending requests for a user
    create index(:procedure_review_requests, [:reviewer_id, :status])

    create index(:procedure_review_requests, [:procedure_version_id])
    create index(:procedure_review_requests, [:requester_id])
  end
end
