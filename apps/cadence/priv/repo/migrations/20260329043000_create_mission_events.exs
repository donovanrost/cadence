defmodule Cadence.Repo.Migrations.CreateMissionEvents do
  use Ecto.Migration

  def change do
    create table(:mission_events, primary_key: false) do
      add(:mission_event_id, :string, primary_key: true)
      add(:mission_id, :string, null: false)
      add(:occurred_at, :utc_datetime_usec, null: false)
      add(:category, :string, null: false)
      add(:kind, :string, null: false)
      add(:severity, :string)
      add(:status, :string)
      add(:title, :string, null: false)
      add(:summary, :string)
      add(:source_record_kind, :string, null: false)
      add(:source_record_id, :string, null: false)
      add(:subject_kind, :string)
      add(:subject_id, :string)
      add(:correlation_key, :string)
      add(:spacecraft_id, :string)
      add(:source_endpoint_ref, :string)
      add(:scheduled_contact_id, :string)
      add(:realized_contact_id, :string)
      add(:path_id, :string)
      add(:capability_instance_id, :string)
      add(:activation_id, :string)
      add(:actor_document, :map, null: false, default: %{})
      add(:metadata_document, :map, null: false, default: %{})

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(index(:mission_events, [:mission_id, :occurred_at, :mission_event_id]))
    create(index(:mission_events, [:mission_id, :category, :occurred_at]))
    create(index(:mission_events, [:mission_id, :kind, :occurred_at]))
    create(index(:mission_events, [:mission_id, :severity, :occurred_at]))
    create(index(:mission_events, [:mission_id, :spacecraft_id, :occurred_at]))
    create(index(:mission_events, [:mission_id, :source_endpoint_ref, :occurred_at]))
    create(index(:mission_events, [:mission_id, :scheduled_contact_id, :occurred_at]))
    create(index(:mission_events, [:mission_id, :realized_contact_id, :occurred_at]))
    create(index(:mission_events, [:mission_id, :path_id, :occurred_at]))
    create(index(:mission_events, [:mission_id, :capability_instance_id, :occurred_at]))
    create(unique_index(:mission_events, [:mission_id, :source_record_kind, :source_record_id]))
  end
end
