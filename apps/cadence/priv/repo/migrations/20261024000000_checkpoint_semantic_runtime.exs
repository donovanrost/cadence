defmodule Cadence.Repo.Migrations.CheckpointSemanticRuntime do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    # Additive: older writers can keep appending; recovery verifies their suffix.
    create table(:semantic_runtime_checkpoints, primary_key: false) do
      add(:organization_scope_id, :string, primary_key: true)
      add(:mission_id, :string, primary_key: true)
      add(:partition_id, :string, primary_key: true)
      add(:runtime_basis_sha256, :string, primary_key: true)
      add(:version, :integer, null: false)

      add(
        :commit_sequence,
        references(:semantic_runtime_commits,
          column: :commit_sequence,
          type: :bigint,
          on_delete: :delete_all
        ),
        null: false
      )

      add(:integrity_sha256, :string, null: false)
    end

    alter table(:semantic_runtime_commits) do
      # NULL identifies historical / older-binary rows, not ordinary updates.
      add(:input_kind, :string)
      add(:timer_key, :string)
      add(:timer_at, :utc_datetime_usec)
    end

    create(
      index(
        :semantic_runtime_commits,
        [
          :organization_scope_id,
          :mission_id,
          :partition_id,
          :runtime_basis_sha256,
          :timer_key,
          :commit_sequence
        ],
        where: "input_kind = 'timer'",
        name: :semantic_runtime_timer_cursor_idx,
        concurrently: true
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
          :timer_key,
          :timer_at
        ],
        where: "input_kind = 'timer' AND projected_at IS NULL",
        name: :semantic_runtime_pending_timer_idx,
        concurrently: true
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
        where: "input_kind IS NULL",
        name: :semantic_runtime_legacy_input_idx,
        concurrently: true
      )
    )
  end
end
