defmodule Cadence.Repo.Migrations.TrackSemanticRuntimeProjection do
  use Ecto.Migration

  def change do
    alter table(:semantic_runtime_commits) do
      add(:projected_at, :utc_datetime_usec)
    end

    create(
      index(
        :semantic_runtime_commits,
        [
          :organization_scope_id,
          :mission_id,
          :partition_id,
          :runtime_basis_sha256,
          :projected_at
        ],
        name: :semantic_runtime_commits_projection_idx
      )
    )
  end
end
