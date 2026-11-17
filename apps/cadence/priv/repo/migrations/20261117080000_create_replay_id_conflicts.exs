defmodule Cadence.Repo.Migrations.CreateReplayIdConflicts do
  use Ecto.Migration

  # #99 follow-up (director GO 11-17): a tripped unit's durable record. One OPEN row per (mission,
  # path, unit, effect); a later trip of the same effect bumps it. Written after the failing
  # transaction returns, read by the Now attention item and devops' poller. Additive.
  def change do
    create table(:replay_id_conflicts, primary_key: false) do
      add(:id, :text, primary_key: true)
      add(:mission_id, :text, null: false)
      # storage (ingress persistence projector) | processing (journal consumer) | timer (owner)
      add(:path, :text, null: false)
      # The stalled unit: "stream:<contact>:<path>:<binding>" or "partition:<partition id>".
      add(:unit_key, :text, null: false)
      add(:effect_kind, :text, null: false)
      add(:effect_id, :text, null: false)
      add(:partition_id, :text)
      add(:realized_contact_id, :text)
      add(:path_id, :text)
      add(:provider_binding_id, :text)
      add(:stream_key, :text)
      add(:partition_stopped, :boolean, null: false, default: false)
      # starting | applying: why a stopped partition is down (until its next start).
      add(:stopped_while, :text)
      add(:first_seen_at, :utc_datetime_usec, null: false)
      add(:last_conflict_at, :utc_datetime_usec, null: false)
      add(:conflict_count, :bigint, null: false, default: 1)
      add(:buffer_retained_bytes, :bigint)
      add(:buffer_max_bytes, :bigint)
      add(:buffer_full_count, :bigint)
      add(:buffer_sampled_at, :utc_datetime_usec)
      add(:dropping_since, :utc_datetime_usec)
      add(:acknowledged_at, :utc_datetime_usec)
      add(:acknowledged_by, :map)
      add(:acknowledged_note, :text)
      add(:resolved_at, :utc_datetime_usec)
      timestamps(type: :utc_datetime_usec)
    end

    # The open-row key the record upserts on, and devops' poller's open-row scan.
    create(
      unique_index(:replay_id_conflicts, [:mission_id, :path, :unit_key, :effect_id],
        name: :replay_id_conflicts_open_idx,
        where: "resolved_at IS NULL"
      )
    )

    create(index(:replay_id_conflicts, [:mission_id, :resolved_at]))
  end
end
