defmodule Cadence.Repo.Migrations.CreateAlarmEpisodes do
  use Ecto.Migration

  def up do
    create table(:alarm_episodes, primary_key: false) do
      add(:episode_id, :string, primary_key: true)
      add(:organization_id, :string, null: false)
      add(:mission_id, :string, null: false)
      add(:spacecraft_id, :string)
      add(:spacecraft_scope_id, :string, null: false)
      add(:source, :string, null: false)
      add(:subject_key, :string, null: false)
      add(:parameter_ref, :string, null: false)
      add(:point_name, :string)
      add(:context, :map, null: false, default: %{})
      add(:severity, :string, null: false)
      add(:peak_severity, :string, null: false)
      add(:source_state, :string, null: false)
      add(:state, :string, null: false)
      add(:opened_at, :utc_datetime_usec, null: false)
      add(:opened_by_ref, :string)
      add(:first_value, :map)
      add(:last_value, :map)
      add(:last_observed_at, :utc_datetime_usec, null: false)
      add(:last_evaluated_at, :utc_datetime_usec, null: false)
      add(:cleared_at, :utc_datetime_usec)
      add(:cleared_by_ref, :string)
      add(:cleared_unacknowledged, :boolean, null: false, default: false)
      add(:acknowledged_at, :utc_datetime_usec)
      add(:acknowledged_by, :map)
      add(:assignee, :map)
      add(:assigned_at, :utc_datetime_usec)
      timestamps(type: :utc_datetime_usec)
    end

    create(
      unique_index(
        :alarm_episodes,
        [:mission_id, :spacecraft_scope_id, :source, :subject_key],
        where: "state = 'active'",
        name: :alarm_episodes_one_active_idx
      )
    )

    create(index(:alarm_episodes, [:mission_id, :state, :severity]))
    create(index(:alarm_episodes, [:mission_id, :spacecraft_id, :opened_at]))

    create table(:alarm_episode_events, primary_key: false) do
      add(:event_id, :string, primary_key: true)

      add(
        :episode_id,
        references(:alarm_episodes, column: :episode_id, type: :string, on_delete: :delete_all),
        null: false
      )

      add(:organization_id, :string, null: false)
      add(:mission_id, :string, null: false)
      add(:kind, :string, null: false)
      add(:actor, :map)
      add(:at, :utc_datetime_usec, null: false)
      add(:source_ref, :string)
      add(:payload, :map, null: false, default: %{})
    end

    create(index(:alarm_episode_events, [:episode_id, :at]))

    create(
      unique_index(:alarm_episode_events, [:mission_id, :source_ref],
        where: "source_ref IS NOT NULL",
        name: :alarm_episode_events_source_ref_idx
      )
    )

    for table <- [:alarm_episodes, :alarm_episode_events] do
      execute("""
      ALTER TABLE #{table}
      ADD CONSTRAINT #{table}_org_mission_fk
      FOREIGN KEY (organization_id, mission_id)
      REFERENCES missions (organization_id, mission_id)
      """)
    end
  end

  def down do
    drop(table(:alarm_episode_events))
    drop(table(:alarm_episodes))
  end
end
