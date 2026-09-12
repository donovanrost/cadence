defmodule Cadence.Repo.Migrations.BoundDerivedDefinitionReceipts do
  use Ecto.Migration

  def up,
    do: replace_limit("CASE WHEN application_key = 'derived_telemetry' THEN 65536 ELSE 16384 END")

  def down, do: replace_limit("16384")

  defp replace_limit(limit) do
    drop(constraint(:federated_application_action_idempotencies, :faaid_response_state_check))

    create(
      constraint(:federated_application_action_idempotencies, :faaid_response_state_check,
        check:
          "((state = 'in_progress' AND claim_token IS NOT NULL AND lease_expires_at IS NOT NULL AND response_status IS NULL AND response_content_type IS NULL AND response_body IS NULL AND completed_at IS NULL) OR (state IN ('completed', 'failed', 'indeterminate') AND claim_token IS NULL AND lease_expires_at IS NULL AND response_status BETWEEN 100 AND 599 AND response_content_type = 'application/json; charset=utf-8' AND response_body IS NOT NULL AND octet_length(response_body) BETWEEN 1 AND (#{limit}) AND completed_at IS NOT NULL))"
      )
    )
  end
end
