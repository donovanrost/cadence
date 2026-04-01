defmodule Cadence.MissionDatabase.Parameter do
  @moduledoc """
  A telemetry parameter definition.

  Parameters are standalone entities that reference a DataType for their
  type information. They are then placed in Containers via ContainerEntry.

  ## Parameter Sources

  - **telemetry**: Extracted from spacecraft telemetry packets
  - **derived**: Computed from other parameters
  - **constant**: Fixed value defined in the database
  - **local**: Ground-side parameter (not from spacecraft)

  ## Example: Telemetry Parameter

      %Parameter{
        name: "CPU_TEMP",
        description: "CPU temperature",
        data_type_ref: "Temperature_C",
        parameter_source: :telemetry
      }

  ## Example: Derived Parameter

      %Parameter{
        name: "TOTAL_POWER",
        description: "Total power consumption",
        parameter_source: :derived,
        derivation_expression: "BUS_VOLTAGE * BUS_CURRENT",
        derivation_trigger: :on_parameter_update,
        derivation_trigger_refs: ["POWER.BUS_VOLTAGE", "POWER.BUS_CURRENT"]
      }
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Cadence.MissionDatabase.DataType

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @parameter_sources [:telemetry, :derived, :constant, :local]
  @derivation_triggers [:on_parameter_update, :on_container_update, :periodic]
  @significance_levels [:none, :watch, :warning, :distress, :critical, :severe]

  schema "mdb_parameters" do
    belongs_to :organization, Cadence.Organizations.Organization
    belongs_to :mission, Cadence.Missions.Mission
    belongs_to :definition_set, Cadence.MissionDatabase.DefinitionSet

    field :name, :string
    field :description, :string
    field :short_description, :string

    # Type reference
    belongs_to :data_type, DataType
    field :data_type_ref, :string

    # Parameter source
    field :parameter_source, Ecto.Enum, values: @parameter_sources, default: :telemetry

    # Derived parameter configuration
    field :derivation_expression, :string
    field :derivation_trigger, Ecto.Enum, values: @derivation_triggers
    field :derivation_trigger_refs, {:array, :string}, default: []

    # System parameter flag
    field :system_parameter, :boolean, default: false

    # Staleness configuration
    field :persistence, :integer
    field :stale_timeout_ms, :integer

    # Significance
    field :significance, Ecto.Enum, values: @significance_levels, default: :none

    # Recording
    field :record_to_archive, :boolean, default: true
    field :record_rate_limit_hz, :float

    field :extensions, :map, default: %{}

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for a Parameter.
  """
  def changeset(parameter, attrs) do
    parameter
    |> cast(attrs, [
      :organization_id,
      :mission_id,
      :definition_set_id,
      :name,
      :description,
      :short_description,
      :data_type_id,
      :data_type_ref,
      :parameter_source,
      :derivation_expression,
      :derivation_trigger,
      :derivation_trigger_refs,
      :system_parameter,
      :persistence,
      :stale_timeout_ms,
      :significance,
      :record_to_archive,
      :record_rate_limit_hz,
      :extensions
    ])
    |> validate_required([:organization_id, :mission_id, :definition_set_id, :name])
    |> validate_inclusion(:parameter_source, @parameter_sources)
    |> validate_inclusion(:significance, @significance_levels)
    |> validate_derived_fields()
    |> validate_type_reference()
    |> unique_constraint([:definition_set_id, :name],
      name: :mdb_parameters_definition_set_name_index
    )
  end

  defp validate_derived_fields(changeset) do
    source = get_field(changeset, :parameter_source)

    if source == :derived do
      expression = get_field(changeset, :derivation_expression)

      if is_nil(expression) or expression == "" do
        add_error(changeset, :derivation_expression, "required for derived parameters")
      else
        changeset
      end
    else
      changeset
    end
  end

  defp validate_type_reference(changeset) do
    source = get_field(changeset, :parameter_source)
    type_id = get_field(changeset, :data_type_id)
    type_ref = get_field(changeset, :data_type_ref)

    # Telemetry parameters should have a type reference (either ID or name)
    if source == :telemetry and is_nil(type_id) and is_nil(type_ref) do
      add_error(changeset, :data_type_ref, "required for telemetry parameters")
    else
      changeset
    end
  end

  @doc """
  Returns true if this parameter is derived (computed from other parameters).
  """
  def derived?(%__MODULE__{parameter_source: :derived}), do: true
  def derived?(_), do: false

  @doc """
  Returns the list of valid parameter sources.
  """
  def valid_parameter_sources, do: @parameter_sources

  @doc """
  Returns the list of valid significance levels.
  """
  def valid_significance_levels, do: @significance_levels
end
