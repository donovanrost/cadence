defmodule Cadence.Repo.Migrations.CreateMdbDerivedItems do
  use Ecto.Migration

  def change do
    create table(:mdb_derived_items, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :mission_id, references(:missions, type: :binary_id, on_delete: :delete_all),
        null: false

      # Note: Derived items are NOT part of DefinitionSet - they are a mission-scoped runtime overlay
      # This allows operators to add calculations without modifying the C&T database version

      add :name, :string, null: false
      add :description, :text

      # Expression to compute value
      add :expression, :text, null: false

      # Source items extracted from expression
      add :source_items, {:array, :string}, default: []

      # Cross-packet item references for CVT lookups
      add :cross_packet_items, {:array, :map}, default: []

      # Output configuration
      add :units, :string
      add :format_string, :string
      add :data_type, :string, default: "float"

      # Control
      add :enabled, :boolean, default: true
      add :display_order, :integer

      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:mdb_derived_items, [:organization_id])
    create index(:mdb_derived_items, [:mission_id])

    create unique_index(:mdb_derived_items, [:mission_id, :name],
             name: :mdb_derived_items_mission_name_index
           )
  end
end
