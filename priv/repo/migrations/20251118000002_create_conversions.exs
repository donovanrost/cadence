defmodule Cadence.Repo.Migrations.CreateConversions do
  use Ecto.Migration

  def change do
    # Base conversions table
    create table(:conversions, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :mission_id, references(:missions, type: :uuid, on_delete: :delete_all), null: false
      add :name, :text, null: false
      add :conversion_type, :text, null: false
      add :description, :text

      timestamps()
    end

    create index(:conversions, [:mission_id])
    create unique_index(:conversions, [:mission_id, :name])

    create constraint(:conversions, :conversion_type_must_be_valid,
             check: "conversion_type IN ('polynomial', 'state_table', 'generic')"
           )

    # Polynomial conversions (y = c0 + c1*x + c2*x^2 + ...)
    create table(:polynomial_conversions, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :conversion_id, references(:conversions, type: :uuid, on_delete: :delete_all),
        null: false

      # Coefficients stored as JSON array: [c0, c1, c2, ...]
      # Example: [0.0, 0.1, 0.001] means y = 0.0 + 0.1*x + 0.001*x^2
      add :coefficients, :jsonb, null: false

      timestamps()
    end

    create unique_index(:polynomial_conversions, [:conversion_id])

    # State table conversions (maps raw value → state string)
    create table(:state_table_conversions, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :conversion_id, references(:conversions, type: :uuid, on_delete: :delete_all),
        null: false

      # States stored as JSON: {"0": "DISABLED", "1": "ENABLED", "2": "FAULT"}
      add :states, :jsonb, null: false

      # Default state for unmapped values
      add :default_state, :text

      timestamps()
    end

    create unique_index(:state_table_conversions, [:conversion_id])

    # Generic conversions (custom Elixir module)
    create table(:generic_conversions, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :conversion_id, references(:conversions, type: :uuid, on_delete: :delete_all),
        null: false

      # Module name (e.g., "MyApp.Conversions.CustomTemp")
      add :module_name, :text, null: false

      # Optional configuration JSON passed to the module
      add :config, :jsonb

      timestamps()
    end

    create unique_index(:generic_conversions, [:conversion_id])

    # Link packet items to conversions
    alter table(:packet_items) do
      add :conversion_id, references(:conversions, type: :uuid, on_delete: :nilify_all)
    end

    create index(:packet_items, [:conversion_id])
  end
end
