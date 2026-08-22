defmodule Cadence.Repo.Migrations.CreateProcedureReviewThreads do
  use Ecto.Migration

  def change do
    create table(:procedure_review_threads, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :procedure_version_id,
          references(:procedure_versions, type: :binary_id, on_delete: :delete_all),
          null: false

      # Who started the thread
      add :author_id,
          references(:users, type: :binary_id, on_delete: :restrict),
          null: false

      # Optional link to the review that created this thread
      # (threads created from request_changes reviews will have this set)
      add :review_id,
          references(:procedure_reviews, type: :binary_id, on_delete: :nilify_all)

      # Thread status: :open or :resolved
      add :status, :string, default: "open", null: false

      # Resolution tracking
      add :resolved_by_id,
          references(:users, type: :binary_id, on_delete: :nilify_all)

      add :resolved_at, :utc_datetime_usec

      # Anchor fields for attaching threads to specific content
      # :version = general thread on the version (default)
      # :section, :step, :block = thread on specific content element
      add :anchor_type, :string, default: "version", null: false
      add :anchor_id, :binary_id

      timestamps(type: :utc_datetime)
    end

    create index(:procedure_review_threads, [:procedure_version_id])
    create index(:procedure_review_threads, [:author_id])
    create index(:procedure_review_threads, [:review_id])

    # Index for finding open threads for a version
    create index(:procedure_review_threads, [:procedure_version_id, :status])

    # Index for finding threads by anchor (for inline comment display)
    create index(:procedure_review_threads, [:procedure_version_id, :anchor_type, :anchor_id])
  end
end
