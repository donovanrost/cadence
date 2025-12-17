defmodule Cadence.Repo.Migrations.AddVerificationTrackingToCommandLogs do
  use Ecto.Migration

  def change do
    alter table(:command_logs) do
      # Track multi-stage verification progress
      add :current_verification_stage, :string
      add :verification_stages_completed, {:array, :string}, default: []
      add :verification_status, :string
    end
  end
end
