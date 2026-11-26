defmodule Cadence.Repo.Migrations.CreateSemanticRuntimeSnapshots do
  use Ecto.Migration

  # DECISIONS #94/#96: one snapshot per partition (and runtime basis), replaced in place, holding
  # the semantic state and the journal offset of every stream it covers (`resume`: stream id =>
  # offset). One row per partition, rewritten about once a minute, never appended to.
  def change do
    create table(:semantic_runtime_snapshots, primary_key: false) do
      add(:organization_scope_id, :string, primary_key: true)
      add(:mission_id, :string, primary_key: true)
      add(:partition_id, :string, primary_key: true)
      add(:runtime_basis_sha256, :string, primary_key: true)
      add(:version, :integer, null: false)
      add(:ownership_epoch, :bigint, null: false)
      add(:state_term, :binary, null: false)
      add(:resume, :map, null: false, default: %{})
      add(:integrity_sha256, :string, null: false)
      add(:snapshotted_at, :utc_datetime_usec, null: false)
    end
  end
end
