defmodule Cadence.MissionDatabase.CommandContainer do
  @moduledoc """
  Defines the binary layout of a command packet.

  Command containers describe how to encode a command into binary format
  for transmission to the spacecraft.

  Similar to telemetry Containers but for the uplink direction.

  ## Example

      %CommandContainer{
        name: "THRUSTER_FIRE_PKT",
        byte_order: :big_endian,
        header: <<0x1A, 0xCF>>,  # Sync word
        size_in_bits: 128
      }
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @byte_orders [:big_endian, :little_endian]

  schema "mdb_command_containers" do
    belongs_to :meta_command, Cadence.MissionDatabase.MetaCommand

    field :name, :string
    field :description, :string

    # Inheritance
    field :base_container_ref, :string

    # Layout
    field :byte_order, Ecto.Enum, values: @byte_orders

    # Fixed header/trailer
    field :header, :binary
    field :trailer, :binary

    # Size
    field :size_in_bits, :integer
    field :max_size_in_bits, :integer

    # Entries
    has_many :entries, Cadence.MissionDatabase.CommandContainerEntry

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for a CommandContainer.
  """
  def changeset(container, attrs) do
    container
    |> cast(attrs, [
      :meta_command_id,
      :name,
      :description,
      :base_container_ref,
      :byte_order,
      :header,
      :trailer,
      :size_in_bits,
      :max_size_in_bits
    ])
    |> validate_required([:meta_command_id])
    |> validate_inclusion(:byte_order, @byte_orders)
    |> validate_size()
  end

  defp validate_size(changeset) do
    size = get_field(changeset, :size_in_bits)
    max_size = get_field(changeset, :max_size_in_bits)

    cond do
      not is_nil(size) and not is_nil(max_size) and size > max_size ->
        add_error(changeset, :size_in_bits, "cannot be greater than max_size_in_bits")

      not is_nil(size) and size < 0 ->
        add_error(changeset, :size_in_bits, "must be non-negative")

      not is_nil(max_size) and max_size < 0 ->
        add_error(changeset, :max_size_in_bits, "must be non-negative")

      true ->
        changeset
    end
  end

  @doc """
  Returns the list of valid byte orders.
  """
  def valid_byte_orders, do: @byte_orders
end
