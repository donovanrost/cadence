defmodule Cadence.Repo.Migrations.CreateCommandReleaseAttempts do
  use Ecto.Migration

  def change do
    create table(:command_release_attempts, primary_key: false) do
      add :command_release_attempt_id, :string, primary_key: true
      add :organization_id, :string
      add :mission_id, :string, null: false
      add :command_queue_entry_id, :string, null: false
      add :command_request_id, :string, null: false
      add :source_endpoint_ref, :string, null: false
      add :realized_contact_id, :string, null: false
      add :path_id, :string
      add :transport_binding_id, :string
      add :command_snapshot_id, :string, null: false
      add :command_id, :string, null: false
      add :command_name, :string
      add :layout_kind, :string
      add :preferred_uplink_service, :string
      add :apid, :integer
      add :service_type, :integer
      add :service_subtype, :integer
      add :opcode_document, :map, null: false, default: %{}
      add :encoded_binary_base64, :text
      add :encoded_size_bytes, :integer
      add :lifecycle_state, :string, null: false
      add :failure_reason, :text
      add :released_by_document, :map, null: false, default: %{}
      add :attempted_at, :utc_datetime_usec, null: false
      add :released_at, :utc_datetime_usec
      add :metadata_document, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:command_release_attempts, [:mission_id, :command_release_attempt_id],
             name: :command_release_attempts_scope_idx
           )

    create index(:command_release_attempts, [:organization_id, :mission_id, :command_queue_entry_id],
             name: :command_release_attempts_queue_entry_org_scope_idx
           )

    create index(:command_release_attempts, [:organization_id, :mission_id, :command_request_id],
             name: :command_release_attempts_request_org_scope_idx
           )

    create index(:command_release_attempts, [:organization_id, :mission_id, :realized_contact_id],
             name: :command_release_attempts_contact_org_scope_idx
           )
  end
end
