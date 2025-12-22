defmodule Cadence.Domain.Interfaces.ValueObjects.ProtocolType do
  @moduledoc """
  Value object representing interface protocol types.

  Protocols are components in an interface's protocol chain that process data.
  Following OpenC3 COSMOS architecture:
  - READ protocols execute in order (protocol 0 → 1 → 2 ...)
  - WRITE protocols execute in reverse order (... 2 → 1 → 0)

  ## Protocol Types

  - `:ccsds` - CCSDS space packet protocol (header parsing, optional CRC)
  - `:length` - Length-prefixed framing (packet size in header)
  - `:template` - Sync pattern with configurable header parsing
  - `:terminated` - Terminator-delimited packets
  - `:fixed` - Fixed-size packets
  - `:crc` - CRC validation layer

  ## Configuration Requirements

  Each protocol type has specific configuration requirements:

  - **:template** requires: `sync_pattern_hex`
  - **:terminated** requires: `terminator_hex`
  - **:fixed** requires: `packet_size`
  - **:crc** optional: `algorithm`, `on_failure`
  - **:ccsds** optional: `crc_enabled`, `crc_algorithm`
  """

  @type t :: :ccsds | :length | :template | :terminated | :fixed | :crc

  @values [:ccsds, :length, :template, :terminated, :fixed, :crc]

  # Protocols that perform CRC operations
  @crc_protocols [:crc, :ccsds]

  # Protocols that handle packet framing
  @framing_protocols [:length, :template, :terminated, :fixed, :ccsds]

  @doc """
  Returns all valid protocol type values.
  """
  @spec values() :: [t()]
  def values, do: @values

  @doc """
  Returns true if the given value is a valid protocol type.
  """
  @spec valid?(term()) :: boolean()
  def valid?(value) when value in @values, do: true
  def valid?(_), do: false

  @doc """
  Validates a protocol type value.
  """
  @spec validate(term()) :: :ok | {:error, :invalid_protocol_type}
  def validate(value) when value in @values, do: :ok
  def validate(_), do: {:error, :invalid_protocol_type}

  @doc """
  Parses a string or atom into a protocol type.
  """
  @spec parse(String.t() | atom()) :: {:ok, t()} | {:error, :invalid_protocol_type}
  def parse(value) when is_atom(value) and value in @values, do: {:ok, value}

  def parse(value) when is_binary(value) do
    case String.downcase(value) do
      "ccsds" -> {:ok, :ccsds}
      "length" -> {:ok, :length}
      "template" -> {:ok, :template}
      "terminated" -> {:ok, :terminated}
      "fixed" -> {:ok, :fixed}
      "crc" -> {:ok, :crc}
      _ -> {:error, :invalid_protocol_type}
    end
  end

  def parse(_), do: {:error, :invalid_protocol_type}

  @doc """
  Returns true if this protocol type performs CRC operations.
  """
  @spec handles_crc?(t()) :: boolean()
  def handles_crc?(type) when type in @crc_protocols, do: true
  def handles_crc?(_), do: false

  @doc """
  Returns true if this protocol type handles packet framing.
  """
  @spec handles_framing?(t()) :: boolean()
  def handles_framing?(type) when type in @framing_protocols, do: true
  def handles_framing?(_), do: false

  @doc """
  Returns the required configuration keys for a protocol type.
  """
  @spec required_config_keys(t()) :: [String.t()]
  def required_config_keys(:template), do: ["sync_pattern_hex"]
  def required_config_keys(:terminated), do: ["terminator_hex"]
  def required_config_keys(:fixed), do: ["packet_size"]
  def required_config_keys(:ccsds), do: []
  def required_config_keys(:length), do: []
  def required_config_keys(:crc), do: []

  @doc """
  Returns the optional configuration keys for a protocol type.
  """
  @spec optional_config_keys(t()) :: [String.t()]
  def optional_config_keys(:length) do
    ["length_bit_size", "length_endian", "length_offset"]
  end

  def optional_config_keys(:template) do
    [
      "header_length",
      "length_offset",
      "length_bit_size",
      "length_value_offset",
      "length_endian",
      "discard_leading_bytes"
    ]
  end

  def optional_config_keys(:crc) do
    ["algorithm", "on_failure"]
  end

  def optional_config_keys(:ccsds) do
    ["crc_enabled", "crc_algorithm", "crc_on_failure"]
  end

  def optional_config_keys(:terminated) do
    ["strip_terminator"]
  end

  def optional_config_keys(:fixed), do: []

  @doc """
  Validates configuration for a given protocol type.

  Returns `:ok` if valid, `{:error, reason}` otherwise.
  """
  @spec validate_config(t(), map()) :: :ok | {:error, String.t()}
  def validate_config(type, config) when is_map(config) do
    required = required_config_keys(type)
    missing = Enum.reject(required, &Map.has_key?(config, &1))

    if Enum.empty?(missing) do
      :ok
    else
      {:error, "#{type} protocol requires: #{Enum.join(missing, ", ")}"}
    end
  end

  def validate_config(_type, _config), do: {:error, "config must be a map"}

  @doc """
  Returns the display name for a protocol type.
  """
  @spec display_name(t()) :: String.t()
  def display_name(:ccsds), do: "CCSDS Space Packet"
  def display_name(:length), do: "Length Prefix"
  def display_name(:template), do: "Sync Template"
  def display_name(:terminated), do: "Terminator Delimited"
  def display_name(:fixed), do: "Fixed Size"
  def display_name(:crc), do: "CRC Validation"

  @doc """
  Returns a description of what the protocol does.
  """
  @spec description(t()) :: String.t()
  def description(:ccsds) do
    "Parses CCSDS space packets with optional CRC validation"
  end

  def description(:length) do
    "Frames packets using a length field in the header"
  end

  def description(:template) do
    "Synchronizes on a byte pattern and parses variable-length packets"
  end

  def description(:terminated) do
    "Splits data stream on a terminator sequence"
  end

  def description(:fixed) do
    "Handles fixed-size packets"
  end

  def description(:crc) do
    "Validates and/or appends CRC checksums"
  end
end
