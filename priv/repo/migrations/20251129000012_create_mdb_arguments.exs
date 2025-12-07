defmodule Cadence.Repo.Migrations.CreateMdbArguments do
  use Ecto.Migration

  def change do
    create table(:mdb_arguments, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :meta_command_id,
          references(:mdb_meta_commands, type: :binary_id, on_delete: :delete_all),
          null: false

      add :name, :string, null: false
      add :description, :text

      # Type reference
      add :data_type_id, references(:mdb_data_types, type: :binary_id, on_delete: :restrict)
      add :data_type_ref, :string

      # Position in command
      add :bit_offset, :integer
      add :bit_length, :integer

      # Value constraints
      add :required, :boolean, default: true
      add :default_value, :string
      add :fixed_value, :string

      # Argument assignment from base command
      add :assigned_value, :string

      # Range overrides
      add :min_value, :float
      add :max_value, :float
      add :valid_values, {:array, :string}, default: []

      # Display
      add :display_order, :integer
      add :hidden, :boolean, default: false

      # Hazardous states (embedded JSON array)
      add :hazardous_states, {:array, :map}, default: []

      add :extensions, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:mdb_arguments, [:meta_command_id])
    create index(:mdb_arguments, [:data_type_id])

    create unique_index(:mdb_arguments, [:meta_command_id, :name],
             name: :mdb_arguments_command_name_index
           )
  end
end
