defmodule Cadence.Repo.Migrations.CreateContactPlanSubmissions do
  @moduledoc """
  U36 (qa #40): one row per contact plan submit, so a resubmitted plan keeps its rounds: who
  submitted which version, with what note, whether the server cut the version unchanged after
  a send back, and the gap acknowledgements the author gave.
  """
  use Ecto.Migration

  def change do
    create table(:contact_plan_submissions, primary_key: false) do
      add(:contact_plan_submission_id, :string, primary_key: true)
      add(:organization_id, :string, null: false)
      add(:mission_id, :string, null: false)
      add(:contact_plan_id, :string, null: false)
      add(:contact_plan_version, :integer, null: false)
      add(:round, :integer, null: false)
      add(:actor_document, :map, null: false)
      add(:note, :text)
      add(:unchanged, :boolean, null: false, default: false)
      add(:acknowledgements_document, {:array, :map}, null: false, default: [])
      add(:submitted_at, :utc_datetime_usec, null: false)
    end

    # Named explicitly: the generated name exceeds Postgres' 63 characters.
    create(
      unique_index(
        :contact_plan_submissions,
        [:organization_id, :mission_id, :contact_plan_id, :round],
        name: :contact_plan_submissions_round_index
      )
    )
  end
end
