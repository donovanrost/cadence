defmodule Cadence.Repo.Migrations.CreateMdbDataTypes do
  use Ecto.Migration

  def change do
    create table(:mdb_data_types, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all), null: false
      add :mission_id, references(:missions, type: :binary_id, on_delete: :delete_all), null: false
      add :definition_set_id, references(:mdb_definition_sets, type: :binary_id, on_delete: :delete_all), null: false

      add :name, :string, null: false
      add :description, :text

      # What this type can be used for: parameter, argument, both
      add :usage, :string, default: "both"

      # Base type category
      # integer, float, string, binary, boolean, enumerated, aggregate, array, absolute_time, relative_time
      add :base_type, :string, null: false

      # Encoding configuration (embedded JSON)
      # Contains: encoding_type, size_in_bits, byte_order, signed, integer_encoding,
      #           float_encoding, charset, string_termination, string_length_prefix_bits,
      #           dynamic_size_ref, dynamic_size_linear_adjustment
      add :encoding, :map

      # For enumerated types: value -> label mappings
      # [{value: int, label: string, description: string, max_value: int}, ...]
      add :enumerations, {:array, :map}, default: []

      # For aggregate types: member definitions
      # [{name: string, type_ref: string, description: string, initial_value: string}, ...]
      add :members, {:array, :map}, default: []

      # For array types
      add :array_element_type_ref, :string
      # {dimensions: [int], dynamic_dimension_refs: [string], linear_adjustments: [map]}
      add :array_dimensions, :map

      # For time types
      add :epoch, :string  # unix, tai, gps, j2000, custom
      add :epoch_custom, :utc_datetime
      add :time_scale, :float
      add :time_offset, :float

      # Calibrator reference (raw -> engineering conversion)
      add :default_calibrator_id, references(:mdb_algorithms, type: :binary_id, on_delete: :nilify_all)

      # Alarm definitions (embedded JSON)
      # Contains nested ranges for watch, warning, distress, critical, severe
      # Plus change_per_second, delta, min_violations, alarm_actions
      add :default_alarm, :map

      # Valid range (for validation, separate from alarms)
      add :valid_range_min, :float
      add :valid_range_max, :float
      add :valid_range_applies_to_calibrated, :boolean, default: true

      # Unit reference
      add :unit_id, references(:mdb_units, type: :binary_id, on_delete: :nilify_all)

      # Initial/default value
      add :initial_value, :string

      add :extensions, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:mdb_data_types, [:organization_id])
    create index(:mdb_data_types, [:mission_id])
    create index(:mdb_data_types, [:definition_set_id])
    create index(:mdb_data_types, [:default_calibrator_id])
    create index(:mdb_data_types, [:unit_id])
    create unique_index(:mdb_data_types, [:definition_set_id, :name], name: :mdb_data_types_definition_set_name_index)
  end
end
