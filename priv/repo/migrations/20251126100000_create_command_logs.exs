defmodule Cadence.Repo.Migrations.CreateCommandLogs do
  use Ecto.Migration

  def change do
    create table(:command_logs, primary_key: false) do
      add :id, :binary_id, primary_key: true

      # Multi-tenancy scoping
      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :mission_id, references(:missions, type: :binary_id, on_delete: :delete_all),
        null: false

      # Routing
      add :target_id, references(:targets, type: :binary_id, on_delete: :nilify_all)

      add :command_definition_id,
          references(:command_definitions, type: :binary_id, on_delete: :nilify_all)

      add :user_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      # Command identification
      add :command_name, :string, null: false
      add :opcode, :integer

      # What was sent
      add :parameters, :map, default: %{}
      add :encoded_binary, :binary

      # Status and result
      add :status, :string, null: false, default: "pending"
      add :error_reason, :text

      # Verification tracking
      add :verification_item, :string
      add :verification_expected, :string
      add :verification_actual, :string
      add :verification_result, :map

      # Precise timestamps
      add :sent_at, :utc_datetime_usec
      add :verified_at, :utc_datetime_usec

      # Metadata
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:command_logs, [:organization_id])
    create index(:command_logs, [:mission_id])
    create index(:command_logs, [:target_id])
    create index(:command_logs, [:command_definition_id])
    create index(:command_logs, [:user_id])
    create index(:command_logs, [:status])
    create index(:command_logs, [:sent_at])
    create index(:command_logs, [:command_name])

    # Composite index for querying command history by mission and time
    create index(:command_logs, [:mission_id, :sent_at])
  end
end
