defmodule Cadence.Repo.Migrations.CreateDerivedItems do
  @moduledoc """
  Creates the derived_items table as a mission-scoped runtime overlay.

  Derived items are computed telemetry values that exist outside the immutable
  DefinitionSet. This allows users to add/modify derived items without creating
  new database versions, which is important when flight software auto-generates
  the C&T database on each upload.

  Unlike packet_items which belong to a DefinitionSet, derived_items are:
  - Mission-scoped (persist across DefinitionSet versions)
  - Mutable at runtime
  - Not tied to any specific packet (can reference items from any packet)
  """
  use Ecto.Migration

  def change do
    create table(:derived_items, primary_key: false) do
      add :id, :binary_id, primary_key: true

      # Mission-scoped (NOT definition_set_scoped)
      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :mission_id, references(:missions, type: :binary_id, on_delete: :delete_all),
        null: false

      # Item identification
      add :name, :string, null: false
      add :description, :text

      # Expression configuration
      # Expression uses item names that are resolved at runtime from the active DefinitionSet
      add :expression, :string, null: false

      # Source items referenced in the expression (for dependency tracking)
      # Format: ["PACKET1.ITEM1", "PACKET2.ITEM2"] or ["ITEM1", "ITEM2"] for same-packet refs
      add :source_items, {:array, :string}, default: []

      # Cross-packet item references (for CVT lookups)
      # Format: [%{"target" => "SC1", "packet" => "POWER", "item" => "VOLTAGE"}]
      add :cross_packet_items, {:array, :map}, default: []

      # Output configuration
      add :units, :string
      add :format_string, :string
      add :data_type, :string, default: "float"

      # Display configuration
      add :display_order, :integer
      add :metadata, :map, default: %{}

      # Enabled flag (allows disabling without deletion)
      add :enabled, :boolean, default: true, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:derived_items, [:organization_id])
    create index(:derived_items, [:mission_id])
    create index(:derived_items, [:enabled])
    create unique_index(:derived_items, [:mission_id, :name])
  end
end
