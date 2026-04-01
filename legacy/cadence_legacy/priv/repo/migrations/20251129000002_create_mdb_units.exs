defmodule Cadence.Repo.Migrations.CreateMdbUnits do
  use Ecto.Migration

  def change do
    create table(:mdb_units, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :mission_id, references(:missions, type: :binary_id, on_delete: :delete_all),
        null: false

      add :definition_set_id,
          references(:mdb_definition_sets, type: :binary_id, on_delete: :delete_all),
          null: false

      add :name, :string, null: false
      add :symbol, :string
      add :description, :text

      # SI conversion (value_in_si = value * factor + offset)
      add :si_conversion_factor, :float
      add :si_conversion_offset, :float
      add :si_unit, :string

      add :extensions, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:mdb_units, [:organization_id])
    create index(:mdb_units, [:mission_id])
    create index(:mdb_units, [:definition_set_id])

    create unique_index(:mdb_units, [:definition_set_id, :name],
             name: :mdb_units_definition_set_name_index
           )
  end
end
