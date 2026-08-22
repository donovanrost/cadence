defmodule Cadence.Repo.Migrations.CreateOperationalEvents do
  use Ecto.Migration

  def change do
    create table(:operational_events, primary_key: false) do
      add(:event_id, :string, primary_key: true)
      add(:organization_id, :string)
      add(:mission_id, :string, null: false)
      add(:occurred_at, :utc_datetime_usec, null: false)
      add(:recorded_at, :utc_datetime_usec, null: false)
      add(:effective_at, :utc_datetime_usec)
      add(:category, :string, null: false)
      add(:kind, :string, null: false)
      add(:severity, :string)
      add(:subject_kind, :string)
      add(:subject_id, :string)
      add(:correlation_id, :string)
      add(:causation_event_id, :string)
      add(:source_record_kind, :string)
      add(:source_record_id, :string)
      add(:job_id, :string)
      add(:replay_run_id, :string)
      add(:import_run_id, :string)
      add(:actor_document, :map, null: false, default: %{})
      add(:scope_document, :map, null: false, default: %{})
      add(:causality_document, :map, null: false, default: %{})
      add(:payload_document, :map, null: false, default: %{})
      add(:previous_document, :map, null: false, default: %{})
      add(:current_document, :map, null: false, default: %{})
      add(:metadata_document, :map, null: false, default: %{})

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(
      index(:operational_events, [:organization_id, :mission_id, :occurred_at, :event_id],
        name: :operational_events_scope_time_idx
      )
    )

    create(
      index(:operational_events, [:organization_id, :mission_id, :category, :occurred_at],
        name: :operational_events_category_time_idx
      )
    )

    create(
      index(:operational_events, [:organization_id, :mission_id, :kind, :occurred_at],
        name: :operational_events_kind_time_idx
      )
    )

    create(
      index(:operational_events, [:organization_id, :mission_id, :subject_kind, :subject_id],
        name: :operational_events_subject_idx
      )
    )

    create(
      index(:operational_events, [:organization_id, :mission_id, :replay_run_id],
        name: :operational_events_replay_idx
      )
    )

    create(
      unique_index(:operational_events, [:mission_id, :source_record_kind, :source_record_id],
        name: :operational_events_source_record_idx,
        where: "source_record_kind IS NOT NULL AND source_record_id IS NOT NULL"
      )
    )
  end
end
