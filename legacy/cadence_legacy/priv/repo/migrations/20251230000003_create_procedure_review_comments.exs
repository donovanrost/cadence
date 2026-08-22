defmodule Cadence.Repo.Migrations.CreateProcedureReviewComments do
  use Ecto.Migration

  def change do
    create table(:procedure_review_comments, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :thread_id,
          references(:procedure_review_threads, type: :binary_id, on_delete: :delete_all),
          null: false

      add :user_id,
          references(:users, type: :binary_id, on_delete: :restrict),
          null: false

      add :body, :text, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:procedure_review_comments, [:thread_id])
    create index(:procedure_review_comments, [:user_id])
  end
end
