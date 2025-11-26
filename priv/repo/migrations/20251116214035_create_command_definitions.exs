defmodule Cadence.Repo.Migrations.CreateCommandDefinitions do
  use Ecto.Migration

  def change do
    create table(:command_definitions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      # Multi-tenancy scoping
      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :mission_id, references(:missions, type: :binary_id, on_delete: :delete_all),
        null: false

      # Command identification
      add :name, :string, null: false
      add :description, :text
      add :opcode, :integer

      # Safety configuration (ADR-004)
      add :is_hazardous, :boolean, default: false, null: false
      add :hazard_description, :text
      add :requires_confirmation, :boolean, default: false, null: false

      # Allowed mission phases
      add :allowed_phases, {:array, :string}, default: []

      # Encoding configuration
      add :encoding_format, :string # binary, ascii, json
      add :encoding_config, :map, default: %{}

      # Verification configuration
      add :has_verification, :boolean, default: false
      add :verification_item, :string # CVT item name to watch
      add :verification_timeout_ms, :integer, default: 5000

      # Metadata
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:command_definitions, [:organization_id])
    create index(:command_definitions, [:mission_id])
    create index(:command_definitions, [:opcode])
    create index(:command_definitions, [:is_hazardous])
    create unique_index(:command_definitions, [:mission_id, :name])
  end
end
