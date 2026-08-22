defmodule Cadence.Repo.Migrations.HardenSemanticAlarmObservations do
  use Ecto.Migration

  def up do
    alter table(:semantic_latest_alarm_states) do
      add(:generation_time, :utc_datetime_usec)
    end

    create(
      index(
        :semantic_alarm_transitions,
        [:organization_id, :mission_id, :transition_id],
        name: :semantic_alarm_transitions_scope_idx
      )
    )
  end

  def down do
    drop(index(:semantic_alarm_transitions, [], name: :semantic_alarm_transitions_scope_idx))

    alter table(:semantic_latest_alarm_states) do
      remove(:generation_time)
    end
  end
end
