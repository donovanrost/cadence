defmodule Cadence.Repo.Migrations.CreateFederatedApplicationActionIdempotency do
  use Ecto.Migration

  def change do
    create table(:federated_application_action_idempotencies) do
      add(:organization_id, :string, null: false)
      add(:actor_kind, :string, null: false)
      add(:actor_id, :string, null: false)
      add(:mission_id, :string, null: false)
      add(:scope_kind, :string, null: false)
      add(:scope_id, :string, null: false)
      add(:application_key, :string, null: false)
      add(:application_version, :integer, null: false)
      add(:surface_id, :string, null: false)
      add(:surface_version, :integer, null: false)
      add(:operation, :string, null: false)
      add(:operation_version, :integer, null: false)
      add(:generation_id, :string, null: false)
      add(:release_id, :string, null: false)
      add(:idempotency_key_digest, :string, null: false)
      add(:request_digest, :string, null: false)
      add(:state, :string, null: false)
      add(:claim_token, :string)
      add(:lease_expires_at, :utc_datetime_usec)
      add(:response_status, :integer)
      add(:response_content_type, :string)
      add(:response_body, :binary)
      add(:completed_at, :utc_datetime_usec)

      add(:retention_expires_at, :utc_datetime_usec, null: false)
      add(:retention_reference, :string, null: false)

      timestamps(type: :utc_datetime_usec)
    end

    create(
      unique_index(
        :federated_application_action_idempotencies,
        [
          :organization_id,
          :actor_kind,
          :actor_id,
          :mission_id,
          :scope_kind,
          :scope_id,
          :application_key,
          :application_version,
          :surface_id,
          :surface_version,
          :operation,
          :operation_version,
          :generation_id,
          :release_id,
          :idempotency_key_digest
        ],
        name: :faaid_logical_identity_idx
      )
    )

    create(index(:federated_application_action_idempotencies, [:generation_id]))
    create(index(:federated_application_action_idempotencies, [:retention_reference]))

    create(
      constraint(
        :federated_application_action_idempotencies,
        :faaid_identity_bounds_check,
        check:
          "octet_length(organization_id) BETWEEN 1 AND 255 AND " <>
            "octet_length(actor_kind) BETWEEN 1 AND 32 AND " <>
            "octet_length(actor_id) BETWEEN 1 AND 255 AND " <>
            "octet_length(mission_id) BETWEEN 1 AND 255 AND " <>
            "octet_length(scope_kind) BETWEEN 1 AND 32 AND " <>
            "octet_length(scope_id) BETWEEN 1 AND 255 AND " <>
            "octet_length(application_key) BETWEEN 1 AND 255 AND " <>
            "octet_length(surface_id) BETWEEN 1 AND 255 AND " <>
            "octet_length(operation) BETWEEN 1 AND 255 AND " <>
            "octet_length(generation_id) BETWEEN 1 AND 255 AND " <>
            "octet_length(release_id) BETWEEN 1 AND 255 AND " <>
            "octet_length(retention_reference) BETWEEN 1 AND 512"
      )
    )

    create(
      constraint(
        :federated_application_action_idempotencies,
        :faaid_version_bounds_check,
        check: "application_version > 0 AND surface_version > 0 AND operation_version > 0"
      )
    )

    create(
      constraint(
        :federated_application_action_idempotencies,
        :faaid_digest_format_check,
        check:
          "idempotency_key_digest ~ '^hmac-sha256:[0-9a-f]{64}$' AND request_digest ~ '^hmac-sha256:[0-9a-f]{64}$'"
      )
    )

    create(
      constraint(
        :federated_application_action_idempotencies,
        :faaid_state_check,
        check: "state IN ('in_progress', 'completed', 'failed', 'indeterminate')"
      )
    )

    create(
      constraint(
        :federated_application_action_idempotencies,
        :faaid_response_state_check,
        check:
          "((state = 'in_progress' AND claim_token IS NOT NULL AND lease_expires_at IS NOT NULL AND response_status IS NULL AND response_content_type IS NULL AND response_body IS NULL AND completed_at IS NULL) OR (state IN ('completed', 'failed', 'indeterminate') AND claim_token IS NULL AND lease_expires_at IS NULL AND response_status BETWEEN 100 AND 599 AND response_content_type = 'application/json; charset=utf-8' AND response_body IS NOT NULL AND octet_length(response_body) BETWEEN 1 AND 16384 AND completed_at IS NOT NULL))"
      )
    )
  end
end
