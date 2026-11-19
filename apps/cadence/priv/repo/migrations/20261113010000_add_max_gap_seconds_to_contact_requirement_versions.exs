defmodule Cadence.Repo.Migrations.AddMaxGapSecondsToContactRequirementVersions do
  use Ecto.Migration

  # DECISIONS #74: an optional gap limit; null (every existing version) means no limit.
  def change do
    alter table(:contact_requirement_versions) do
      add(:max_gap_seconds, :integer, null: true)
    end
  end
end
