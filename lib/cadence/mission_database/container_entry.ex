defmodule Cadence.MissionDatabase.ContainerEntry do
  @moduledoc """
  An entry in a container - defines what data appears at a specific location.

  Container entries can be:
  - **parameter_ref**: Reference to a parameter
  - **fixed_value**: Fixed binary value (e.g., sync word)
  - **container_ref**: Nested container reference
  - **array_parameter_ref**: Array of parameters

  ## Bit Offset Modes

  - **container_start**: Offset from start of this container
  - **previous_entry**: Offset from end of previous entry
  - **base_container_end**: Offset from end of inherited base container

  ## Example: Parameter Entry

      %ContainerEntry{
        entry_type: :parameter_ref,
        parameter_ref: "CPU_TEMP",
        bit_offset: 128,
        bit_offset_from: :container_start
      }

  ## Example: Fixed Value (Sync Word)

      %ContainerEntry{
        entry_type: :fixed_value,
        fixed_value: <<0xDE, 0xAD, 0xBE, 0xEF>>,
        fixed_value_size_bits: 32,
        bit_offset: 0
      }

  ## Example: Conditional Entry

      %ContainerEntry{
        entry_type: :parameter_ref,
        parameter_ref: "OPTIONAL_DATA",
        bit_offset: 0,
        bit_offset_from: :previous_entry,
        include_condition: %MatchCriteria{
          parameter_ref: "FLAGS.HAS_OPTIONAL",
          comparison: :equal,
          value: "1"
        }
      }
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Cadence.MissionDatabase.{Container, Parameter, MatchCriteria}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @entry_types [:parameter_ref, :fixed_value, :container_ref, :array_parameter_ref]
  @bit_offset_modes [:container_start, :previous_entry, :base_container_end]

  schema "mdb_container_entries" do
    belongs_to :container, Container

    field :entry_type, Ecto.Enum, values: @entry_types

    # Position
    field :bit_offset, :integer
    field :bit_offset_from, Ecto.Enum, values: @bit_offset_modes, default: :container_start

    # For parameter_ref
    belongs_to :parameter, Parameter
    field :parameter_ref, :string

    # For fixed_value
    field :fixed_value, :binary
    field :fixed_value_size_bits, :integer

    # For container_ref
    field :container_ref, :string

    # For array_parameter_ref
    field :array_size, :integer
    field :array_size_ref, :string

    # Conditional inclusion
    embeds_one :include_condition, MatchCriteria, on_replace: :update

    # Display
    field :display_order, :integer

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for a ContainerEntry.
  """
  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [
      :container_id,
      :entry_type,
      :bit_offset,
      :bit_offset_from,
      :parameter_id,
      :parameter_ref,
      :fixed_value,
      :fixed_value_size_bits,
      :container_ref,
      :array_size,
      :array_size_ref,
      :display_order
    ])
    |> cast_embed(:include_condition)
    |> validate_required([:container_id, :entry_type])
    |> validate_inclusion(:entry_type, @entry_types)
    |> validate_inclusion(:bit_offset_from, @bit_offset_modes)
    |> validate_entry_type_fields()
  end

  defp validate_entry_type_fields(changeset) do
    case get_field(changeset, :entry_type) do
      :parameter_ref ->
        validate_parameter_ref(changeset)

      :fixed_value ->
        validate_fixed_value(changeset)

      :container_ref ->
        validate_container_ref(changeset)

      :array_parameter_ref ->
        validate_array_parameter_ref(changeset)

      _ ->
        changeset
    end
  end

  defp validate_parameter_ref(changeset) do
    param_id = get_field(changeset, :parameter_id)
    param_ref = get_field(changeset, :parameter_ref)

    if is_nil(param_id) and (is_nil(param_ref) or param_ref == "") do
      add_error(changeset, :parameter_ref, "required for parameter_ref entry type")
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
        add_error(cs, :fixed_value_size_bits, "required and must be positive for fixed_value entry type")
      else
        cs
      end
    end)
  end

  defp validate_container_ref(changeset) do
    ref = get_field(changeset, :container_ref)

    if is_nil(ref) or ref == "" do
      add_error(changeset, :container_ref, "required for container_ref entry type")
    else
      changeset
    end
  end

  defp validate_array_parameter_ref(changeset) do
    param_id = get_field(changeset, :parameter_id)
    param_ref = get_field(changeset, :parameter_ref)
    array_size = get_field(changeset, :array_size)
    array_size_ref = get_field(changeset, :array_size_ref)

    changeset
    |> then(fn cs ->
      if is_nil(param_id) and (is_nil(param_ref) or param_ref == "") do
        add_error(cs, :parameter_ref, "required for array_parameter_ref entry type")
      else
        cs
      end
    end)
    |> then(fn cs ->
      if is_nil(array_size) and (is_nil(array_size_ref) or array_size_ref == "") do
        add_error(cs, :array_size, "must specify array_size or array_size_ref")
      else
        cs
      end
    end)
  end

  @doc """
  Returns the list of valid entry types.
  """
  def valid_entry_types, do: @entry_types

  @doc """
  Returns the list of valid bit offset modes.
  """
  def valid_bit_offset_modes, do: @bit_offset_modes
end
