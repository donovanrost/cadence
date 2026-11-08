defmodule Cadence.Repo.Migrations.AddAttemptResolutionEvidence do
  use Ecto.Migration

  def change do
    alter table(:command_release_attempts) do
      add(:resolution_evidence, :map, null: false, default: %{})
    end

    alter table(:provider_reservations) do
      add(:resolution_evidence, :map, null: false, default: %{})
    end
  end
end
