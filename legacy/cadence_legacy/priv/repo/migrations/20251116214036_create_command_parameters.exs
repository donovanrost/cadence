defmodule Cadence.Repo.Migrations.CreateCommandParameters do
  use Ecto.Migration

  def change do
    create table(:command_parameters, primary_key: false) do
      add :id, :binary_id, primary_key: true

      # Belongs to command definition
      add :command_definition_id,
          references(:command_definitions, type: :binary_id, on_delete: :delete_all),
          null: false

      # Parameter identification
      add :name, :string, null: false
      add :description, :text

      # Data type and validation
      # uint, int, float, string, boolean, enum
      add :data_type, :string, null: false
      add :required, :boolean, default: true, null: false

      # Default and constraints
      add :default_value, :string
      add :min_value, :float
      add :max_value, :float
      add :valid_values, {:array, :string}, default: []

      # Encoding configuration
      add :bit_offset, :integer
      add :bit_length, :integer

      # Display configuration
      add :display_order, :integer
      add :units, :string
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:command_parameters, [:command_definition_id])
    create unique_index(:command_parameters, [:command_definition_id, :name])
  end
end
