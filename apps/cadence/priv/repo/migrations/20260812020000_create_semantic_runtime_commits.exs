defmodule Cadence.Repo.Migrations.CreateSemanticRuntimeCommits do
  use Ecto.Migration

  def change do
    create table(:semantic_runtime_commits, primary_key: false) do
      add(:commit_sequence, :bigserial, primary_key: true)
      add(:commit_id, :string, null: false)

      add(:organization_scope_id, :string,
        null: false,
        default: "__unscoped_organization__"
      )

      add(:organization_id, :string)
      add(:mission_id, :string, null: false)
      add(:partition_id, :string, null: false)
      add(:mission_model_revision_id, :string, null: false)
      add(:runtime_basis_sha256, :string, null: false)
      add(:input_term, :binary, null: false)
      add(:result_term, :binary, null: false)
      add(:state_term, :binary, null: false)

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(
      unique_index(
        :semantic_runtime_commits,
        [
          :organization_scope_id,
          :mission_id,
          :partition_id,
          :runtime_basis_sha256,
          :commit_id
        ],
        name: :semantic_runtime_commits_identity_idx
      )
    )

    create(
      index(
        :semantic_runtime_commits,
        [
          :organization_scope_id,
          :mission_id,
          :partition_id,
          :runtime_basis_sha256,
          :commit_sequence
        ],
        name: :semantic_runtime_commits_recovery_idx
      )
    )
  end
end
