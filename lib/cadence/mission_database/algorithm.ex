defmodule Cadence.MissionDatabase.Algorithm do
  @moduledoc """
  Calibration/conversion algorithm for transforming raw values to engineering units.

  Supports multiple algorithm types:

  - **polynomial**: `y = c0 + c1*x + c2*x² + ...`
  - **spline**: Piecewise interpolation (linear, quadratic)
  - **math_operation**: Reverse Polish Notation expression
  - **state_table**: Discrete value mapping (raw integer → string label)
  - **custom**: Elixir module implementation

  ## Polynomial Example

      %Algorithm{
        name: "TEMP_CAL",
        algorithm_type: :polynomial,
        polynomial_coefficients: [-40.0, 0.01, 0.000001]  # -40 + 0.01*x + 0.000001*x²
      }

  ## Spline Example

      %Algorithm{
        name: "PRESSURE_CAL",
        algorithm_type: :spline,
        spline_points: [
          %{raw: 0.0, calibrated: 0.0},
          %{raw: 1000.0, calibrated: 50.0},
          %{raw: 4095.0, calibrated: 100.0}
        ],
        spline_order: 1  # Linear interpolation
      }

  ## State Table Example

      %Algorithm{
        name: "MODE_STATES",
        algorithm_type: :state_table,
        state_table: %{0 => "OFF", 1 => "STANDBY", 2 => "ACTIVE"},
        state_table_default: "UNKNOWN"
      }
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Cadence.MissionDatabase.SplinePoint

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @algorithm_types [:polynomial, :spline, :math_operation, :state_table, :custom]

  schema "mdb_algorithms" do
    belongs_to :organization, Cadence.Organizations.Organization
    belongs_to :mission, Cadence.Missions.Mission
    belongs_to :definition_set, Cadence.MissionDatabase.DefinitionSet

    field :name, :string
    field :description, :string

    field :algorithm_type, Ecto.Enum, values: @algorithm_types

    # Polynomial coefficients [c0, c1, c2, ...]
    field :polynomial_coefficients, {:array, :float}

    # Spline points
    embeds_many :spline_points, SplinePoint, on_replace: :delete
    field :spline_order, :integer, default: 1
    field :spline_extrapolate, :boolean, default: false

    # MathOperation (RPN expression)
    field :math_operation_expression, :string
    field :math_operation_postfix, {:array, :string}

    # StateTable
    field :state_table, :map
    field :state_table_default, :string

    # Custom module
    field :custom_module, :string
    field :custom_config, :map, default: %{}

    # Input parameter references
    field :input_parameter_refs, {:array, :string}, default: []

    field :extensions, :map, default: %{}

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for an Algorithm.
  """
  def changeset(algorithm, attrs) do
    algorithm
    |> cast(attrs, [
      :organization_id,
      :mission_id,
      :definition_set_id,
      :name,
      :description,
      :algorithm_type,
      :polynomial_coefficients,
      :spline_order,
      :spline_extrapolate,
      :math_operation_expression,
      :math_operation_postfix,
      :state_table,
      :state_table_default,
      :custom_module,
      :custom_config,
      :input_parameter_refs,
      :extensions
    ])
    |> cast_embed(:spline_points)
    |> validate_required([
      :organization_id,
      :mission_id,
      :definition_set_id,
      :name,
      :algorithm_type
    ])
    |> validate_inclusion(:algorithm_type, @algorithm_types)
    |> validate_algorithm_type_fields()
    |> unique_constraint([:definition_set_id, :name],
      name: :mdb_algorithms_definition_set_name_index
    )
  end

  defp validate_algorithm_type_fields(changeset) do
    case get_field(changeset, :algorithm_type) do
      :polynomial ->
        validate_polynomial(changeset)

      :spline ->
        validate_spline(changeset)

      :state_table ->
        validate_state_table(changeset)

      :custom ->
        validate_custom(changeset)

      _ ->
        changeset
    end
  end

  defp validate_polynomial(changeset) do
    coeffs = get_field(changeset, :polynomial_coefficients)

    if is_nil(coeffs) or coeffs == [] do
      add_error(changeset, :polynomial_coefficients, "required for polynomial algorithm")
    else
      changeset
    end
  end

  defp validate_spline(changeset) do
    points = get_field(changeset, :spline_points)
    order = get_field(changeset, :spline_order) || 1

    cond do
      is_nil(points) or length(points) < 2 ->
        add_error(changeset, :spline_points, "must have at least 2 points")

      order == 2 and length(points) < 3 ->
        add_error(changeset, :spline_points, "quadratic interpolation requires at least 3 points")

      true ->
        changeset
    end
  end

  defp validate_state_table(changeset) do
    table = get_field(changeset, :state_table)

    if is_nil(table) or table == %{} do
      add_error(changeset, :state_table, "required for state_table algorithm")
    else
      changeset
    end
  end

  defp validate_custom(changeset) do
    module = get_field(changeset, :custom_module)

    if is_nil(module) or module == "" do
      add_error(changeset, :custom_module, "required for custom algorithm")
    else
      changeset
    end
  end

  @doc """
  Applies the algorithm to convert a raw value to calibrated value.
  """
  def apply(%__MODULE__{algorithm_type: :polynomial} = alg, raw_value) do
    apply_polynomial(alg.polynomial_coefficients, raw_value)
  end

  def apply(%__MODULE__{algorithm_type: :spline} = alg, raw_value) do
    apply_spline(alg.spline_points, alg.spline_order, alg.spline_extrapolate, raw_value)
  end

  def apply(%__MODULE__{algorithm_type: :state_table} = alg, raw_value) do
    key = to_string(raw_value)
    Map.get(alg.state_table, key, alg.state_table_default)
  end

  def apply(%__MODULE__{algorithm_type: :custom} = alg, raw_value) do
    module = String.to_existing_atom("Elixir.#{alg.custom_module}")
    module.convert(raw_value, alg.custom_config)
  end

  def apply(_, raw_value), do: raw_value

  defp apply_polynomial(coefficients, x) do
    coefficients
    |> Enum.with_index()
    |> Enum.reduce(0.0, fn {coeff, power}, acc ->
      acc + coeff * :math.pow(x, power)
    end)
  end

  defp apply_spline(points, order, extrapolate, x) do
    sorted = Enum.sort_by(points, & &1.raw)

    case order do
      0 -> apply_step_spline(sorted, x)
      1 -> apply_linear_spline(sorted, extrapolate, x)
      # Default to linear
      _ -> apply_linear_spline(sorted, extrapolate, x)
    end
  end

  defp apply_step_spline(points, x) do
    point = Enum.find(Enum.reverse(points), fn p -> p.raw <= x end)
    if point, do: point.calibrated, else: hd(points).calibrated
  end

  defp apply_linear_spline(points, extrapolate, x) do
    first = hd(points)
    last = List.last(points)

    cond do
      x <= first.raw ->
        if extrapolate do
          interpolate_linear(first, Enum.at(points, 1), x)
        else
          first.calibrated
        end

      x >= last.raw ->
        if extrapolate do
          interpolate_linear(Enum.at(points, -2), last, x)
        else
          last.calibrated
        end

      true ->
        {p1, p2} = find_bracketing_points(points, x)
        interpolate_linear(p1, p2, x)
    end
  end

  defp find_bracketing_points(points, x) do
    points
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.find(fn [p1, p2] -> p1.raw <= x and x <= p2.raw end)
    |> case do
      [p1, p2] -> {p1, p2}
      nil -> {hd(points), Enum.at(points, 1)}
    end
  end

  defp interpolate_linear(p1, p2, x) do
    slope = (p2.calibrated - p1.calibrated) / (p2.raw - p1.raw)
    p1.calibrated + slope * (x - p1.raw)
  end

  @doc """
  Returns the list of valid algorithm types.
  """
  def valid_algorithm_types, do: @algorithm_types
end
