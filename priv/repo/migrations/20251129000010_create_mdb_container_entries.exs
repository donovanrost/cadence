defmodule Cadence.Repo.Migrations.CreateMdbContainerEntries do
  use Ecto.Migration

  def change do
    create table(:mdb_container_entries, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :container_id, references(:mdb_containers, type: :binary_id, on_delete: :delete_all), null: false

      # Entry type: parameter_ref, fixed_value, container_ref, array_parameter_ref
      add :entry_type, :string, null: false

      # Position in container
      add :bit_offset, :integer
      add :bit_offset_from, :string, default: "container_start"

      # For parameter_ref
      add :parameter_id, references(:mdb_parameters, type: :binary_id, on_delete: :restrict)
      add :parameter_ref, :string

      # For fixed_value
      add :fixed_value, :binary
      add :fixed_value_size_bits, :integer

      # For container_ref
      add :container_ref, :string

      # For array_parameter_ref
      add :array_size, :integer
      add :array_size_ref, :string

      # Inclusion condition (MatchCriteria embedded JSON)
      add :include_condition, :map

      # Display order
      add :display_order, :integer

      timestamps(type: :utc_datetime)
    end

    create index(:mdb_container_entries, [:container_id])
    create index(:mdb_container_entries, [:parameter_id])
  end
end
