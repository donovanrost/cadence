defmodule Cadence.MissionDatabase.DerivedItem do
  @moduledoc """
  Mission-scoped derived telemetry item (runtime overlay).

  Derived items are computed telemetry values based on expressions that
  reference other telemetry parameters. They exist OUTSIDE the versioned
  DefinitionSet to allow operators to add calculations without modifying
  the C&T database.

  ## Key Design Decision

  Derived items are mission-scoped, NOT definition_set-scoped. This means:
  - They persist across DefinitionSet version updates
  - Operators can add/modify them without creating a new DB version
  - They reference parameters by fully qualified name (PACKET.ITEM)

  ## Expression Syntax

  Expressions support:
  - **Arithmetic**: `+`, `-`, `*`, `/`
  - **Pure Functions**: `abs()`, `sqrt()`, `min()`, `max()`, `pow()`, `round()`, `floor()`, `ceil()`, `clamp()`
  - **Stateful Functions**: `rolling_avg(x, window)`, `rolling_min()`, `rolling_max()`, `stddev()`, `rate()`, `delta()`, `count()`, `elapsed()`
  - **Conditionals**: `if CONDITION then VALUE_TRUE else VALUE_FALSE`
  - **Comparisons**: `<`, `>`, `<=`, `>=`, `==`, `!=`
  - **Variables**: Must use fully qualified names: `PACKET.ITEM`

  ## Example: Simple Calculation

      %DerivedItem{
        name: "TOTAL_POWER",
        expression: "POWER.BUS_VOLTAGE * POWER.BUS_CURRENT",
        units: "W",
        source_items: ["POWER.BUS_VOLTAGE", "POWER.BUS_CURRENT"]
      }

  ## Example: Rolling Average

      %DerivedItem{
        name: "CPU_TEMP_AVG",
        expression: "rolling_avg(HEALTH.CPU_TEMP, 10)",
        units: "°C",
        source_items: ["HEALTH.CPU_TEMP"]
      }

  ## Example: Conditional

      %DerivedItem{
        name: "BATTERY_STATUS",
        expression: "if POWER.BATTERY_PCT > 50 then 1 else 0",
        data_type: "int",
        source_items: ["POWER.BATTERY_PCT"]
      }
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @data_types ["float", "int", "uint", "string", "boolean"]

  schema "mdb_derived_items" do
    belongs_to :organization, Cadence.Organizations.Organization
    belongs_to :mission, Cadence.Missions.Mission

    # Note: No definition_set_id - derived items are mission-scoped

    field :name, :string
    field :description, :string

    # Expression configuration
    field :expression, :string
    field :source_items, {:array, :string}, default: []
    field :cross_packet_items, {:array, :map}, default: []

    # Output configuration
    field :units, :string
    field :format_string, :string
    field :data_type, :string, default: "float"

    # Control
    field :enabled, :boolean, default: true
    field :display_order, :integer

    field :metadata, :map, default: %{}

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for a DerivedItem.
  """
  def changeset(derived_item, attrs) do
    derived_item
    |> cast(attrs, [
      :organization_id,
      :mission_id,
      :name,
      :description,
      :expression,
      :source_items,
      :cross_packet_items,
      :units,
      :format_string,
      :data_type,
      :enabled,
      :display_order,
      :metadata
    ])
    |> validate_required([:organization_id, :mission_id, :name, :expression])
    |> validate_inclusion(:data_type, @data_types)
    |> validate_expression()
    |> extract_source_items()
    |> unique_constraint([:mission_id, :name],
      name: :mdb_derived_items_mission_name_index
    )
  end

  defp validate_expression(changeset) do
    expression = get_field(changeset, :expression)

    if is_nil(expression) or String.trim(expression) == "" do
      add_error(changeset, :expression, "cannot be blank")
    else
      # Basic validation - could be enhanced with actual parser
      changeset
    end
  end

  defp extract_source_items(changeset) do
    expression = get_field(changeset, :expression)
    source_items = get_field(changeset, :source_items)

    # If source_items not explicitly set, extract from expression
    if is_nil(source_items) or source_items == [] do
      extracted = extract_parameter_refs(expression)
      put_change(changeset, :source_items, extracted)
    else
      changeset
    end
  end

  # Extract parameter references (PACKET.ITEM format) from expression
  defp extract_parameter_refs(nil), do: []
  defp extract_parameter_refs(expression) do
    # Match patterns like PACKET.ITEM or PACKET.ITEM.SUBITEM
    ~r/[A-Z][A-Z0-9_]*\.[A-Z][A-Z0-9_]*/
    |> Regex.scan(expression)
    |> List.flatten()
    |> Enum.uniq()
  end

  @doc """
  Returns true if this derived item is enabled.
  """
  def enabled?(%__MODULE__{enabled: true}), do: true
  def enabled?(_), do: false

  @doc """
  Returns the list of valid data types.
  """
  def valid_data_types, do: @data_types
end
