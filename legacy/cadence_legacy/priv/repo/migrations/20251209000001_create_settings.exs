defmodule Cadence.Repo.Migrations.CreateSettings do
  use Ecto.Migration

  def change do
    create table(:settings, primary_key: false) do
      add :id, :binary_id, primary_key: true

      # Scoping - settings can be at organization or mission level
      add :scope_type, :string, null: false
      add :scope_id, :binary_id, null: false

      # Setting identification
      add :namespace, :string, null: false
      add :key, :string, null: false

      # Flexible value storage with type information
      add :value, :map, null: false

      timestamps(type: :utc_datetime)
    end

    # Unique constraint: one setting per scope/namespace/key combination
    create unique_index(:settings, [:scope_type, :scope_id, :namespace, :key])

    # Index for efficient namespace lookups within a scope
    create index(:settings, [:scope_type, :scope_id, :namespace])
  end
end
