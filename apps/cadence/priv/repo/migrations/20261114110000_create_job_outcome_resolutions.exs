defmodule Cadence.Repo.Migrations.CreateJobOutcomeResolutions do
  use Ecto.Migration

  # U54 (job_outcome_unknown): an operator's decision on one run of a job whose outcome is
  # unknown. The primary key is the item id (job and attempt), so two operators deciding at once
  # can't both win, and a later attempt cut off again is a new item.
  def change do
    create table(:job_outcome_resolutions, primary_key: false) do
      add(:item_id, :string, primary_key: true)
      add(:job_id, :string, null: false)
      add(:attempt, :integer, null: false)
      add(:mission_id, :string, null: false)
      add(:job_type, :string, null: false)
      add(:action, :string, null: false)
      add(:actor, :map, null: false)
      add(:note, :text)
      add(:resolved_at, :utc_datetime_usec, null: false)

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(index(:job_outcome_resolutions, [:mission_id, :resolved_at]))
    create(index(:job_outcome_resolutions, [:job_id]))
  end
end
