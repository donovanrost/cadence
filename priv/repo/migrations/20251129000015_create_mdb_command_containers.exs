defmodule Cadence.Repo.Migrations.CreateMdbCommandContainers do
  use Ecto.Migration

  def change do
    create table(:mdb_command_containers, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :meta_command_id, references(:mdb_meta_commands, type: :binary_id, on_delete: :delete_all), null: false

      add :name, :string
      add :description, :text

      # Inheritance
      add :base_container_ref, :string

      # Layout
      add :byte_order, :string

      # Fixed header/trailer
      add :header, :binary
      add :trailer, :binary

      # Size
      add :size_in_bits, :integer
      add :max_size_in_bits, :integer

      timestamps(type: :utc_datetime)
    end

    create index(:mdb_command_containers, [:meta_command_id])

    # Command container entries
    create table(:mdb_command_container_entries, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :command_container_id, references(:mdb_command_containers, type: :binary_id, on_delete: :delete_all), null: false

      # Entry type: argument_ref, fixed_value, parameter_ref
      add :entry_type, :string, null: false

      add :bit_offset, :integer

      # For argument_ref
      add :argument_id, references(:mdb_arguments, type: :binary_id, on_delete: :restrict)

      # For fixed_value
      add :fixed_value, :binary
      add :fixed_value_size_bits, :integer

      # For parameter_ref (parameter value injected into command)
      add :parameter_ref, :string

      add :display_order, :integer

      timestamps(type: :utc_datetime)
    end

    create index(:mdb_command_container_entries, [:command_container_id])
    create index(:mdb_command_container_entries, [:argument_id])
  end
end
