defmodule Cadence.Repo.Migrations.CreatePartitionStreamKeys do
  use Ecto.Migration

  # DECISIONS #99: the stream ordinal in replay-safe effect ids. One row per (mission, runtime
  # partition, journal stream), allocated once and never reused, so two streams never share an
  # ordinal. Additive; nothing reads it but the partition that allocates it.
  def change do
    create table(:partition_stream_keys, primary_key: false) do
      add(:ordinal, :bigserial, primary_key: true)
      add(:mission_id, :string, null: false)
      add(:partition_id, :string, null: false)
      add(:stream_key, :string, null: false)
      add(:inserted_at, :utc_datetime_usec, null: false, default: fragment("now()"))
    end

    create(
      unique_index(:partition_stream_keys, [:mission_id, :partition_id, :stream_key],
        name: :partition_stream_keys_stream_idx
      )
    )
  end
end
