defmodule Cadence.MissionDatabase.CommandContainerEntry do
  @moduledoc """
  An entry in a command container defining what goes at a specific location.

  Command container entries can be:
  - **argument_ref**: Reference to a command argument
  - **fixed_value**: Fixed binary value (e.g., opcode, sync word)
  - **parameter_ref**: Current telemetry value injected into command

  ## Example: Argument Entry

      %CommandContainerEntry{
        entry_type: :argument_ref,
        argument_id: target_temp_arg.id,
        bit_offset: 32
      }

  ## Example: Fixed Opcode

      %CommandContainerEntry{
        entry_type: :fixed_value,
        fixed_value: <<0x45>>,
        fixed_value_size_bits: 8,
        bit_offset: 0
      }

  ## Example: Parameter Injection

  Inject current telemetry value into command (useful for "increment" commands):

      %CommandContainerEntry{
        entry_type: :parameter_ref,
        parameter_ref: "CONFIG.CURRENT_VALUE",
        bit_offset: 16
      }
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Cadence.MissionDatabase.Argument

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @entry_types [:argument_ref, :fixed_value, :parameter_ref]

  schema "mdb_command_container_entries" do
    belongs_to :command_container, Cadence.MissionDatabase.CommandContainer

    field :entry_type, Ecto.Enum, values: @entry_types

    field :bit_offset, :integer

    # For argument_ref
    belongs_to :argument, Argument

    # For fixed_value
    field :fixed_value, :binary
    field :fixed_value_size_bits, :integer

    # For parameter_ref
    field :parameter_ref, :string

    field :display_order, :integer

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for a CommandContainerEntry.
  """
  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [
      :command_container_id,
      :entry_type,
      :bit_offset,
      :argument_id,
      :fixed_value,
      :fixed_value_size_bits,
      :parameter_ref,
      :display_order
    ])
    |> validate_required([:command_container_id, :entry_type])
    |> validate_inclusion(:entry_type, @entry_types)
    |> validate_entry_type_fields()
  end

  defp validate_entry_type_fields(changeset) do
    case get_field(changeset, :entry_type) do
      :argument_ref ->
        validate_argument_ref(changeset)

      :fixed_value ->
        validate_fixed_value(changeset)

      :parameter_ref ->
        validate_parameter_ref(changeset)

      _ ->
        changeset
    end
  end

  defp validate_argument_ref(changeset) do
    arg_id = get_field(changeset, :argument_id)

    if is_nil(arg_id) do
      add_error(changeset, :argument_id, "required for argument_ref entry type")
    else
      changeset
    end
  end

  defp validate_fixed_value(changeset) do
    value = get_field(changeset, :fixed_value)
    size = get_field(changeset, :fixed_value_size_bits)

    changeset
    |> then(fn cs ->
      if is_nil(value) do
        add_error(cs, :fixed_value, "required for fixed_value entry type")
      else
        cs
      end
    end)
    |> then(fn cs ->
      if is_nil(size) or size <= 0 do
        add_error(
          cs,
          :fixed_value_size_bits,
          "required and must be positive for fixed_value entry type"
        )
      else
        cs
      end
    end)
  end

  defp validate_parameter_ref(changeset) do
    ref = get_field(changeset, :parameter_ref)

    if is_nil(ref) or ref == "" do
      add_error(changeset, :parameter_ref, "required for parameter_ref entry type")
    else
      changeset
    end
  end

  @doc """
  Returns the list of valid entry types.
  """
  def valid_entry_types, do: @entry_types
end
