defmodule Cadence.Interfaces.InterfaceProtocol do
  @moduledoc """
  InterfaceProtocol schema representing a single protocol in an interface's protocol chain.

  Following the OpenC3 COSMOS architecture, interfaces can have multiple protocols that
  process data sequentially:
  - READ protocols execute in order (first declared runs first)
  - WRITE protocols execute in reverse order (last declared runs first)

  Each protocol specifies its own direction (read, write, or read_write) and configuration.

  ## Examples

      # First protocol in chain - CCSDS template (order: 0)
      %InterfaceProtocol{
        protocol_type: "template",
        protocol_direction: "read",
        protocol_config: %{
          "sync_pattern_hex" => "1ACFFC1D",
          "header_length" => 6,
          "length_offset" => 4,
          "length_bit_size" => 16,
          "length_value_offset" => 1,
          "length_endian" => "big",
          "discard_leading_bytes" => 4
        },
        order: 0
      }

      # Second protocol in chain - CRC validation (order: 1)
      %InterfaceProtocol{
        protocol_type: "crc",
        protocol_direction: "read_write",
        protocol_config: %{
          "crc_bit_size" => 32,
          "crc_algorithm" => "CRC32"
        },
        order: 1
      }
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          interface_id: Ecto.UUID.t(),
          protocol_type: String.t(),
          protocol_config: map(),
          protocol_direction: String.t(),
          order: integer(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  schema "interface_protocols" do
    field :protocol_type, :string
    field :protocol_config, :map, default: %{}
    field :protocol_direction, :string, default: "read_write"
    field :order, :integer

    belongs_to :interface, Cadence.Interfaces.InterfaceSchema

    timestamps(type: :utc_datetime)
  end

  @protocol_types [
    "ccsds",
    "length",
    "template",
    "terminated",
    "fixed",
    "crc"
  ]

  @protocol_directions [
    "read",
    "write",
    "read_write"
  ]

  @doc """
  Changeset for creating or updating a protocol in an interface chain.
  """
  def changeset(protocol, attrs) do
    protocol
    |> cast(attrs, [
      :interface_id,
      :protocol_type,
      :protocol_config,
      :protocol_direction,
      :order
    ])
    |> validate_required([:interface_id, :protocol_type, :protocol_direction, :order])
    |> validate_inclusion(:protocol_type, @protocol_types)
    |> validate_inclusion(:protocol_direction, @protocol_directions)
    |> validate_number(:order, greater_than_or_equal_to: 0)
    |> validate_protocol_config()
    |> foreign_key_constraint(:interface_id)
    |> unique_constraint([:interface_id, :order],
      name: :interface_protocols_interface_id_order_index
    )
  end

  # Validate protocol configuration matches protocol type
  defp validate_protocol_config(changeset) do
    case {get_field(changeset, :protocol_type), get_field(changeset, :protocol_config)} do
      {protocol_type, protocol_config}
      when not is_nil(protocol_type) and not is_nil(protocol_config) ->
        apply_protocol_config_validation(changeset, protocol_type, protocol_config)

      _ ->
        changeset
    end
  end

  defp apply_protocol_config_validation(changeset, protocol_type, protocol_config) do
    case protocol_type do
      "length" -> validate_length_protocol_config(changeset, protocol_config)
      "template" -> validate_template_protocol_config(changeset, protocol_config)
      "terminated" -> validate_terminated_protocol_config(changeset, protocol_config)
      "fixed" -> validate_fixed_protocol_config(changeset, protocol_config)
      "crc" -> validate_crc_protocol_config(changeset, protocol_config)
      "ccsds" -> validate_ccsds_protocol_config(changeset, protocol_config)
      _ -> changeset
    end
  end

  defp validate_length_protocol_config(changeset, _config) do
    # length_bit_size has a default, so no required keys
    changeset
  end

  defp validate_template_protocol_config(changeset, config) do
    required_keys = ["sync_pattern_hex"]

    if Enum.all?(required_keys, &Map.has_key?(config, &1)) do
      changeset
    else
      add_error(
        changeset,
        :protocol_config,
        "template protocol requires: #{Enum.join(required_keys, ", ")}"
      )
    end
  end

  defp validate_terminated_protocol_config(changeset, config) do
    required_keys = ["terminator_hex"]

    if Enum.all?(required_keys, &Map.has_key?(config, &1)) do
      changeset
    else
      add_error(
        changeset,
        :protocol_config,
        "terminated protocol requires: #{Enum.join(required_keys, ", ")}"
      )
    end
  end

  defp validate_fixed_protocol_config(changeset, config) do
    required_keys = ["packet_size"]

    if Enum.all?(required_keys, &Map.has_key?(config, &1)) do
      changeset
    else
      add_error(
        changeset,
        :protocol_config,
        "fixed protocol requires: #{Enum.join(required_keys, ", ")}"
      )
    end
  end

  defp validate_crc_protocol_config(changeset, config) do
    valid_algorithms = [
      "crc32",
      "crc16_ccitt",
      "crc16_xmodem",
      "crc8",
      "xor_checksum"
    ]

    valid_on_failure = ["skip", "disconnect", "pass"]

    algorithm = Map.get(config, "algorithm", "crc16_ccitt")
    on_failure = Map.get(config, "on_failure", "skip")

    cond do
      algorithm not in valid_algorithms ->
        add_error(
          changeset,
          :protocol_config,
          "crc protocol: invalid algorithm '#{algorithm}'"
        )

      on_failure not in valid_on_failure ->
        add_error(
          changeset,
          :protocol_config,
          "crc protocol: invalid on_failure '#{on_failure}'"
        )

      true ->
        changeset
    end
  end

  defp validate_ccsds_protocol_config(changeset, config) do
    valid_algorithms = ["crc32", "crc16_ccitt", "crc16_xmodem"]
    valid_on_failure = ["skip", "disconnect", "pass"]

    crc_enabled = Map.get(config, "crc_enabled", false)
    crc_algorithm = Map.get(config, "crc_algorithm", "crc16_ccitt")
    crc_on_failure = Map.get(config, "crc_on_failure", "skip")

    cond do
      crc_enabled == true and crc_algorithm not in valid_algorithms ->
        add_error(
          changeset,
          :protocol_config,
          "ccsds protocol: invalid crc_algorithm '#{crc_algorithm}'"
        )

      crc_enabled == true and crc_on_failure not in valid_on_failure ->
        add_error(
          changeset,
          :protocol_config,
          "ccsds protocol: invalid crc_on_failure '#{crc_on_failure}'"
        )

      true ->
        changeset
    end
  end
end
