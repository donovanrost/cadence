defmodule Cadence.Repo.Migrations.GeneralizeCommandVerifierMatchesAndTransportSignals do
  use Ecto.Migration

  def change do
    rename table(:command_verifier_instances), :matched_sample_id, to: :matched_record_id

    alter table(:command_verifier_instances) do
      add :matched_record_kind, :string
    end

    alter table(:transport_action_requests) do
      add :command_release_attempt_id, :string
      add :command_request_id, :string
      add :source_endpoint_ref, :string
      add :command_name, :string
      add :signal_phase, :string
    end

    create index(:transport_action_requests, [:mission_id, :command_release_attempt_id])
    create index(:transport_action_requests, [:mission_id, :command_request_id])
  end
end
