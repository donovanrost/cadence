defmodule Cadence.Commands.CommandParameter do
  @moduledoc """
  Defines a parameter within a command definition.

  Command parameters specify the arguments that can be passed to a command,
  including their data types, constraints, and encoding configuration.

  ## Data Types

  - `uint` - Unsigned integer
  - `int` - Signed integer
  - `float` - Floating point number
  - `string` - Text string
  - `boolean` - True/false
  - `enum` - One of a set of valid values

  ## Constraints

  Parameters can have validation constraints:

  - `required` - Must be provided (no default)
  - `min_value` / `max_value` - Numeric range limits
  - `valid_values` - Allowed values (for enum types)

  ## Encoding

  Binary encoding is specified via:

  - `bit_offset` - Position in command packet
  - `bit_length` - Size in bits

  ## Example

      %CommandParameter{
        name: "target_temperature",
        data_type: "float",
        required: true,
        min_value: -40.0,
        max_value: 85.0,
        units: "°C",
        bit_offset: 16,
        bit_length: 32
      }
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Cadence.Commands.CommandDefinition

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @data_types ["uint", "int", "float", "string", "boolean", "enum"]

  schema "command_parameters" do
    belongs_to :command_definition, CommandDefinition

    # Parameter identification
    field :name, :string
    field :description, :string

    # Data type and validation
    field :data_type, :string
    field :required, :boolean, default: true

    # Default and constraints
    field :default_value, :string
    field :min_value, :float
    field :max_value, :float
    field :valid_values, {:array, :string}, default: []

    # Encoding configuration
    field :bit_offset, :integer
    field :bit_length, :integer

    # Display configuration
    field :display_order, :integer
    field :units, :string
    field :metadata, :map, default: %{}

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for a new or existing command parameter.
  """
  def changeset(command_parameter, attrs) do
    command_parameter
    |> cast(attrs, [
      :command_definition_id,
      :name,
      :description,
      :data_type,
      :required,
      :default_value,
      :min_value,
      :max_value,
      :valid_values,
      :bit_offset,
      :bit_length,
      :display_order,
      :units,
      :metadata
    ])
    |> validate_required([:command_definition_id, :name, :data_type])
    |> validate_inclusion(:data_type, @data_types)
    |> validate_number(:bit_offset, greater_than_or_equal_to: 0)
    |> validate_number(:bit_length, greater_than: 0)
    |> validate_min_max()
    |> validate_enum_values()
    |> validate_default_value()
    |> unique_constraint([:command_definition_id, :name])
  end

  # Validate min_value <= max_value if both present
  defp validate_min_max(changeset) do
    min_value = get_field(changeset, :min_value)
    max_value = get_field(changeset, :max_value)

    if min_value && max_value && min_value > max_value do
      add_error(changeset, :min_value, "must be less than or equal to max_value")
    else
      changeset
    end
  end

  # Validate enum types have valid_values
  defp validate_enum_values(changeset) do
    data_type = get_field(changeset, :data_type)
    valid_values = get_field(changeset, :valid_values)

    if data_type == "enum" && (is_nil(valid_values) || valid_values == []) do
      add_error(changeset, :valid_values, "is required for enum data type")
    else
      changeset
    end
  end

  # Validate default_value matches constraints
  defp validate_default_value(changeset) do
    default_value = get_field(changeset, :default_value)

    if is_nil(default_value) || default_value == "" do
      changeset
    else
      changeset
      |> validate_default_in_range()
      |> validate_default_in_valid_values()
    end
  end

  defp validate_default_in_range(changeset) do
    default_value = get_field(changeset, :default_value)
    min_value = get_field(changeset, :min_value)
    max_value = get_field(changeset, :max_value)
    data_type = get_field(changeset, :data_type)

    if data_type in ["uint", "int", "float"] && default_value do
      case Float.parse(default_value) do
        {num, _} ->
          cond do
            min_value && num < min_value ->
              add_error(changeset, :default_value, "must be >= #{min_value}")

            max_value && num > max_value ->
              add_error(changeset, :default_value, "must be <= #{max_value}")

            true ->
              changeset
          end

        :error ->
          add_error(changeset, :default_value, "must be a valid number")
      end
    else
      changeset
    end
  end

  defp validate_default_in_valid_values(changeset) do
    default_value = get_field(changeset, :default_value)
    valid_values = get_field(changeset, :valid_values)
    data_type = get_field(changeset, :data_type)

    if data_type == "enum" && default_value && valid_values != [] do
      if default_value in valid_values do
        changeset
      else
        add_error(changeset, :default_value, "must be one of: #{Enum.join(valid_values, ", ")}")
      end
    else
      changeset
    end
  end

  @doc """
  Returns true if this parameter is required.
  """
  def required?(%__MODULE__{required: true}), do: true
  def required?(_), do: false

  @doc """
  Validates a parameter value against its constraints.
  Returns :ok or {:error, reason}.
  """
  def validate_value(%__MODULE__{} = param, value) do
    with :ok <- validate_type(param, value),
         :ok <- validate_range(param, value),
         :ok <- validate_valid_values(param, value) do
      :ok
    end
  end

  defp validate_type(%__MODULE__{data_type: "uint"}, value) when is_integer(value) and value >= 0,
    do: :ok

  defp validate_type(%__MODULE__{data_type: "int"}, value) when is_integer(value), do: :ok
  defp validate_type(%__MODULE__{data_type: "float"}, value) when is_number(value), do: :ok
  defp validate_type(%__MODULE__{data_type: "string"}, value) when is_binary(value), do: :ok
  defp validate_type(%__MODULE__{data_type: "boolean"}, value) when is_boolean(value), do: :ok
  defp validate_type(%__MODULE__{data_type: "enum"}, value) when is_binary(value), do: :ok

  defp validate_type(%__MODULE__{data_type: type}, _value),
    do: {:error, "invalid type for #{type}"}

  defp validate_range(%__MODULE__{min_value: nil, max_value: nil}, _value), do: :ok

  defp validate_range(%__MODULE__{min_value: min, max_value: max}, value) when is_number(value) do
    cond do
      min && value < min -> {:error, "value must be >= #{min}"}
      max && value > max -> {:error, "value must be <= #{max}"}
      true -> :ok
    end
  end

  defp validate_range(_, _), do: :ok

  defp validate_valid_values(%__MODULE__{valid_values: []}, _value), do: :ok

  defp validate_valid_values(%__MODULE__{valid_values: valid_values}, value)
       when is_binary(value) do
    if value in valid_values do
      :ok
    else
      {:error, "value must be one of: #{Enum.join(valid_values, ", ")}"}
    end
  end

  defp validate_valid_values(_, _), do: :ok

  @doc """
  Returns the list of valid data types.
  """
  def valid_data_types, do: @data_types
end
