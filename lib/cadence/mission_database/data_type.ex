defmodule Cadence.MissionDatabase.DataType do
  @moduledoc """
  Shared data type definition that can be referenced by parameters and arguments.

  DataTypes are the foundation of the type system. They define:
  - How values are encoded in binary (via DataEncoding)
  - How raw values are converted to engineering units (via Algorithm)
  - What alarm thresholds apply (via AlarmDefinition)
  - Valid ranges for the values

  XTCE separates ParameterType and ArgumentType, but they share the same structure.
  We unify them with a `usage` field to indicate applicability.

  ## Base Types

  - **integer**: Signed or unsigned integers
  - **float**: IEEE754 or MIL-STD-1750A floating point
  - **string**: Text with various encodings
  - **binary**: Raw bytes
  - **boolean**: True/false
  - **enumerated**: Integer → label mapping
  - **aggregate**: Struct-like composition
  - **array**: Homogeneous collection
  - **absolute_time**: Timestamp
  - **relative_time**: Duration

  ## Example: Integer Type

      %DataType{
        name: "UInt16",
        base_type: :integer,
        usage: :both,
        encoding: %DataEncoding{
          encoding_type: :integer,
          size_in_bits: 16,
          byte_order: :big_endian,
          signed: false
        }
      }

  ## Example: Calibrated Float Type

      %DataType{
        name: "Temperature_C",
        base_type: :float,
        encoding: %DataEncoding{
          encoding_type: :integer,
          size_in_bits: 12,
          signed: false
        },
        default_calibrator: polynomial_algorithm,
        unit: celsius_unit,
        default_alarm: %AlarmDefinition{
          warning_range: %{min_inclusive: -10.0, max_inclusive: 85.0},
          critical_range: %{min_inclusive: -40.0, max_inclusive: 125.0}
        }
      }
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Cadence.MissionDatabase.{
    DataEncoding,
    EnumerationValue,
    AggregateMember,
    ArrayDimensions,
    AlarmDefinition,
    Algorithm,
    Unit
  }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @base_types [
    :integer,
    :float,
    :string,
    :binary,
    :boolean,
    :enumerated,
    :aggregate,
    :array,
    :absolute_time,
    :relative_time
  ]

  @usages [:parameter, :argument, :both]

  @epochs [:unix, :tai, :gps, :j2000, :custom]

  schema "mdb_data_types" do
    belongs_to :organization, Cadence.Organizations.Organization
    belongs_to :mission, Cadence.Missions.Mission
    belongs_to :definition_set, Cadence.MissionDatabase.DefinitionSet

    field :name, :string
    field :description, :string

    field :usage, Ecto.Enum, values: @usages, default: :both
    field :base_type, Ecto.Enum, values: @base_types

    # Encoding
    embeds_one :encoding, DataEncoding, on_replace: :update

    # Enumerated type values
    embeds_many :enumerations, EnumerationValue, on_replace: :delete

    # Aggregate type members
    embeds_many :members, AggregateMember, on_replace: :delete

    # Array type configuration
    field :array_element_type_ref, :string
    embeds_one :array_dimensions, ArrayDimensions, on_replace: :update

    # Time type configuration
    field :epoch, Ecto.Enum, values: @epochs
    field :epoch_custom, :utc_datetime
    field :time_scale, :float
    field :time_offset, :float

    # Calibration
    belongs_to :default_calibrator, Algorithm, foreign_key: :default_calibrator_id
    has_many :context_calibrators, Cadence.MissionDatabase.ContextCalibrator

    # Alarms
    embeds_one :default_alarm, AlarmDefinition, on_replace: :update
    has_many :context_alarms, Cadence.MissionDatabase.ContextAlarm

    # Validation range
    field :valid_range_min, :float
    field :valid_range_max, :float
    field :valid_range_applies_to_calibrated, :boolean, default: true

    # Unit
    belongs_to :unit, Unit

    # Default/initial value
    field :initial_value, :string

    field :extensions, :map, default: %{}

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for a DataType.
  """
  def changeset(data_type, attrs) do
    data_type
    |> cast(attrs, [
      :organization_id,
      :mission_id,
      :definition_set_id,
      :name,
      :description,
      :usage,
      :base_type,
      :array_element_type_ref,
      :epoch,
      :epoch_custom,
      :time_scale,
      :time_offset,
      :default_calibrator_id,
      :valid_range_min,
      :valid_range_max,
      :valid_range_applies_to_calibrated,
      :unit_id,
      :initial_value,
      :extensions
    ])
    |> cast_embed(:encoding)
    |> cast_embed(:enumerations)
    |> cast_embed(:members)
    |> cast_embed(:array_dimensions)
    |> cast_embed(:default_alarm)
    |> validate_required([:organization_id, :mission_id, :definition_set_id, :name, :base_type])
    |> validate_inclusion(:base_type, @base_types)
    |> validate_inclusion(:usage, @usages)
    |> validate_base_type_fields()
    |> validate_valid_range()
    |> unique_constraint([:definition_set_id, :name],
      name: :mdb_data_types_definition_set_name_index
    )
  end

  defp validate_base_type_fields(changeset) do
    case get_field(changeset, :base_type) do
      :enumerated ->
        validate_enumerated(changeset)

      :aggregate ->
        validate_aggregate(changeset)

      :array ->
        validate_array(changeset)

      :absolute_time ->
        validate_time(changeset)

      :relative_time ->
        validate_time(changeset)

      _ ->
        changeset
    end
  end

  defp validate_enumerated(changeset) do
    enums = get_field(changeset, :enumerations)

    if is_nil(enums) or enums == [] do
      add_error(changeset, :enumerations, "required for enumerated type")
    else
      changeset
    end
  end

  defp validate_aggregate(changeset) do
    members = get_field(changeset, :members)

    if is_nil(members) or members == [] do
      add_error(changeset, :members, "required for aggregate type")
    else
      changeset
    end
  end

  defp validate_array(changeset) do
    element_ref = get_field(changeset, :array_element_type_ref)
    dims = get_field(changeset, :array_dimensions)

    changeset
    |> then(fn cs ->
      if is_nil(element_ref) or element_ref == "" do
        add_error(cs, :array_element_type_ref, "required for array type")
      else
        cs
      end
    end)
    |> then(fn cs ->
      if is_nil(dims) do
        add_error(cs, :array_dimensions, "required for array type")
      else
        cs
      end
    end)
  end

  defp validate_time(changeset) do
    epoch = get_field(changeset, :epoch)

    if is_nil(epoch) do
      add_error(changeset, :epoch, "required for time types")
    else
      changeset
    end
  end

  defp validate_valid_range(changeset) do
    min = get_field(changeset, :valid_range_min)
    max = get_field(changeset, :valid_range_max)

    if not is_nil(min) and not is_nil(max) and min > max do
      add_error(changeset, :valid_range_max, "must be greater than or equal to valid_range_min")
    else
      changeset
    end
  end

  @doc """
  Returns true if the value is within the valid range.
  """
  def valid_value?(%__MODULE__{valid_range_min: nil, valid_range_max: nil}, _value), do: true

  def valid_value?(%__MODULE__{valid_range_min: min, valid_range_max: nil}, value),
    do: value >= min

  def valid_value?(%__MODULE__{valid_range_min: nil, valid_range_max: max}, value),
    do: value <= max

  def valid_value?(%__MODULE__{valid_range_min: min, valid_range_max: max}, value) do
    value >= min and value <= max
  end

  @doc """
  Returns the list of valid base types.
  """
  def valid_base_types, do: @base_types

  @doc """
  Returns the list of valid usages.
  """
  def valid_usages, do: @usages

  @doc """
  Returns the list of valid epochs.
  """
  def valid_epochs, do: @epochs
end
