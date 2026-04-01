defmodule Cadence.MissionDatabase.Argument do
  @moduledoc """
  Command argument definition.

  Arguments define the input parameters for commands. They reference
  a DataType for type information and can have additional constraints.

  ## Value Sources

  - **User input**: Operator provides value (default)
  - **Default value**: Used if operator doesn't provide value
  - **Fixed value**: Cannot be changed by operator
  - **Assigned value**: Inherited from base command with fixed value

  ## Example

      %Argument{
        name: "target_temp",
        description: "Target temperature setpoint",
        data_type_ref: "Temperature_C",
        required: true,
        min_value: -40.0,
        max_value: 85.0,
        default_value: "25.0"
      }

  ## Hazardous States

  Specific argument values can be marked as hazardous:

      %Argument{
        name: "mode",
        hazardous_states: [
          %HazardousState{value: "ARM", description: "Arms the system"},
          %HazardousState{value: "FIRE", description: "Fires the system"}
        ]
      }
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Cadence.MissionDatabase.{DataType, HazardousState}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "mdb_arguments" do
    belongs_to :meta_command, Cadence.MissionDatabase.MetaCommand

    field :name, :string
    field :description, :string

    # Type reference
    belongs_to :data_type, DataType
    field :data_type_ref, :string

    # Position in command
    field :bit_offset, :integer
    field :bit_length, :integer

    # Value constraints
    field :required, :boolean, default: true
    field :default_value, :string
    field :fixed_value, :string
    field :assigned_value, :string

    # Range overrides
    field :min_value, :float
    field :max_value, :float
    field :valid_values, {:array, :string}, default: []

    # Display
    field :display_order, :integer
    field :hidden, :boolean, default: false

    # Hazardous states
    embeds_many :hazardous_states, HazardousState, on_replace: :delete

    field :extensions, :map, default: %{}

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for an Argument.
  """
  def changeset(argument, attrs) do
    argument
    |> cast(attrs, [
      :meta_command_id,
      :name,
      :description,
      :data_type_id,
      :data_type_ref,
      :bit_offset,
      :bit_length,
      :required,
      :default_value,
      :fixed_value,
      :assigned_value,
      :min_value,
      :max_value,
      :valid_values,
      :display_order,
      :hidden,
      :extensions
    ])
    |> cast_embed(:hazardous_states)
    |> validate_required([:meta_command_id, :name])
    |> validate_value_constraints()
    |> validate_range()
    |> unique_constraint([:meta_command_id, :name],
      name: :mdb_arguments_command_name_index
    )
  end

  defp validate_value_constraints(changeset) do
    fixed = get_field(changeset, :fixed_value)
    default = get_field(changeset, :default_value)
    required = get_field(changeset, :required)

    cond do
      not is_nil(fixed) and not is_nil(default) ->
        add_error(changeset, :default_value, "cannot have both fixed_value and default_value")

      required and not is_nil(default) ->
        # This is allowed - required with default means operator must confirm
        changeset

      true ->
        changeset
    end
  end

  defp validate_range(changeset) do
    min = get_field(changeset, :min_value)
    max = get_field(changeset, :max_value)

    if not is_nil(min) and not is_nil(max) and min > max do
      add_error(changeset, :max_value, "must be greater than or equal to min_value")
    else
      changeset
    end
  end

  @doc """
  Returns true if this argument has a fixed value.
  """
  def fixed?(%__MODULE__{fixed_value: nil}), do: false
  def fixed?(%__MODULE__{fixed_value: ""}), do: false
  def fixed?(_), do: true

  @doc """
  Returns true if any value of this argument is hazardous.
  """
  def has_hazardous_states?(%__MODULE__{hazardous_states: []}), do: false
  def has_hazardous_states?(%__MODULE__{hazardous_states: nil}), do: false
  def has_hazardous_states?(_), do: true

  @doc """
  Checks if a specific value is hazardous.
  """
  def value_hazardous?(%__MODULE__{hazardous_states: states}, value) when is_list(states) do
    Enum.any?(states, fn state -> state.value == value end)
  end

  def value_hazardous?(_, _), do: false

  @doc """
  Returns the effective value for this argument.
  Priority: assigned_value > fixed_value > provided value > default_value
  """
  def effective_value(%__MODULE__{assigned_value: v}, _provided) when not is_nil(v), do: v
  def effective_value(%__MODULE__{fixed_value: v}, _provided) when not is_nil(v), do: v
  def effective_value(%__MODULE__{default_value: v}, nil) when not is_nil(v), do: v
  def effective_value(_, provided), do: provided
end
