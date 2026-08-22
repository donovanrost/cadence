defmodule Cadence.Repo.Migrations.CreateMdbAlgorithms do
  use Ecto.Migration

  def change do
    create table(:mdb_algorithms, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :mission_id, references(:missions, type: :binary_id, on_delete: :delete_all),
        null: false

      add :definition_set_id,
          references(:mdb_definition_sets, type: :binary_id, on_delete: :delete_all),
          null: false

      add :name, :string, null: false
      add :description, :text

      # Algorithm type: polynomial, spline, math_operation, state_table, custom
      add :algorithm_type, :string, null: false

      # Polynomial: y = sum(coefficients[i] * x^i)
      add :polynomial_coefficients, {:array, :float}

      # Spline: interpolation points stored as embedded JSON
      # [{raw: float, calibrated: float}, ...]
      add :spline_points, {:array, :map}, default: []
      # 0=step, 1=linear, 2=quadratic
      add :spline_order, :integer, default: 1
      add :spline_extrapolate, :boolean, default: false

      # MathOperation: RPN expression
      add :math_operation_expression, :text
      add :math_operation_postfix, {:array, :string}

      # StateTable: value -> string mapping
      add :state_table, :map
      add :state_table_default, :string

      # Custom: Elixir module
      add :custom_module, :string
      add :custom_config, :map, default: %{}

      # Input parameter references (for algorithms that reference other params)
      add :input_parameter_refs, {:array, :string}, default: []

      add :extensions, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:mdb_algorithms, [:organization_id])
    create index(:mdb_algorithms, [:mission_id])
    create index(:mdb_algorithms, [:definition_set_id])

    create unique_index(:mdb_algorithms, [:definition_set_id, :name],
             name: :mdb_algorithms_definition_set_name_index
           )
  end
end
