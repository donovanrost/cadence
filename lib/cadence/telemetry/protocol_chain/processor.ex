defmodule Cadence.Telemetry.ProtocolChain.Processor do
  @moduledoc """
  Pure functional module for protocol chain processing.

  Handles the mechanics of:
  - Initializing protocol instances from configuration
  - Processing data through read/write protocol chains
  - Configuration parsing and normalization
  """

  require Logger

  alias Cadence.Telemetry.Protocols.{
    CCSDSProtocol,
    CRCProtocol,
    LengthProtocol,
    TemplateProtocol,
    TerminatedProtocol,
    FixedProtocol
  }

  @type protocol_instance :: {module(), map()}
  @type protocol_chain :: [protocol_instance()]

  @doc """
  Maps protocol type string to its implementing module.
  """
  @spec protocol_module_for_type(String.t()) :: module() | nil
  def protocol_module_for_type("ccsds"), do: CCSDSProtocol
  def protocol_module_for_type("crc"), do: CRCProtocol
  def protocol_module_for_type("length"), do: LengthProtocol
  def protocol_module_for_type("template"), do: TemplateProtocol
  def protocol_module_for_type("terminated"), do: TerminatedProtocol
  def protocol_module_for_type("fixed"), do: FixedProtocol
  def protocol_module_for_type(_), do: nil

  @doc """
  Initializes a single protocol from its database configuration.

  Returns `{module, state}` tuple or nil if initialization fails.
  """
  @spec init_protocol(map()) :: protocol_instance() | nil
  def init_protocol(protocol_config) do
    protocol_module = protocol_module_for_type(protocol_config.protocol_type)

    if protocol_module do
      opts = atomize_protocol_config(protocol_config.protocol_config)
      protocol_state = protocol_module.new(opts)
      {protocol_module, protocol_state}
    else
      Logger.warning("Unknown protocol type: #{protocol_config.protocol_type}")
      nil
    end
  rescue
    error ->
      Logger.error("Failed to initialize protocol #{protocol_config.protocol_type}: #{inspect(error)}")
      nil
  end

  @doc """
  Initializes a complete protocol chain from database configurations.

  Takes a list of InterfaceProtocol schemas (already sorted by order).
  Returns a list of `{module, state}` tuples for the specified direction.
  """
  @spec init_chain([map()], String.t()) :: protocol_chain()
  def init_chain(protocol_configs, direction) do
    protocol_configs
    |> Enum.filter(fn config ->
      config.protocol_direction in [direction, "read_write"]
    end)
    |> Enum.map(&init_protocol/1)
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Creates a fresh clone of a protocol chain with original configurations.

  Used when creating per-client protocol instances for stateful protocols.
  The `protocol_configs` should be a list of `{protocol_type, config_map}` tuples.
  """
  @spec clone_chain([{String.t(), map()}]) :: protocol_chain()
  def clone_chain(protocol_configs) do
    Enum.map(protocol_configs, fn {protocol_type, config} ->
      protocol_module = protocol_module_for_type(protocol_type)

      if protocol_module do
        opts = atomize_protocol_config(config)
        protocol_state = protocol_module.new(opts)
        {protocol_module, protocol_state}
      else
        nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Processes binary data through the read protocol chain.

  Protocols are executed in forward order (0 → 1 → 2).
  Each protocol can extract multiple packets from input data.

  Returns:
  - `{:ok, packets, updated_chain}` - Successfully extracted packets
  - `{:stop, updated_chain}` - Protocol is buffering, needs more data
  - `{:disconnect, reason}` - Protocol requested disconnect
  """
  @spec process_read(protocol_chain(), binary()) ::
          {:ok, [binary()], protocol_chain()}
          | {:stop, protocol_chain()}
          | {:disconnect, term()}
  def process_read(protocol_chain, data) do
    process_through_read_chain([data], protocol_chain, [])
  end

  @doc """
  Processes a packet through the write protocol chain.

  Protocols are executed in reverse order (2 → 1 → 0).
  Each protocol can transform or frame the outgoing data.

  Returns:
  - `{:ok, binary, updated_chain}` - Successfully encoded packet
  - `{:error, reason}` - Encoding failed
  """
  @spec process_write(protocol_chain(), binary()) ::
          {:ok, binary(), protocol_chain()}
          | {:error, term()}
  def process_write(protocol_chain, packet) do
    # Process in reverse order for writes
    reversed_chain = Enum.reverse(protocol_chain)
    process_through_write_chain([packet], reversed_chain, [])
  end

  @doc """
  Determines the packet format based on the last protocol in the chain.

  The last protocol in the read chain determines the format of extracted packets.
  """
  @spec chain_format(protocol_chain()) :: :ccsds | :raw | :simulator
  def chain_format([]), do: :simulator
  def chain_format(chain) do
    {module, _state} = List.last(chain)

    if function_exported?(module, :packet_format, 0) do
      module.packet_format()
    else
      :raw
    end
  end

  @doc """
  Resets all protocols in the chain (e.g., on reconnection).
  """
  @spec reset_chain(protocol_chain()) :: protocol_chain()
  def reset_chain(chain) do
    Enum.map(chain, fn {module, state} ->
      new_state = module.connect_reset(state)
      {module, new_state}
    end)
  end

  # --- Private Functions ---

  # Process data through READ protocol chain (forward order: 0 → 1 → 2)
  defp process_through_read_chain(packets, [], processed_states) do
    {:ok, packets, Enum.reverse(processed_states)}
  end

  defp process_through_read_chain([], _remaining_chain, processed_states) do
    # Protocol buffering - waiting for more data
    {:stop, Enum.reverse(processed_states)}
  end

  defp process_through_read_chain(packets, [{module, state} | rest_chain], processed_states) do
    result =
      Enum.reduce_while(packets, {:ok, [], state}, fn packet, {:ok, acc_packets, current_state} ->
        case module.read_data(packet, current_state) do
          {:ok, new_packets, new_state} ->
            {:cont, {:ok, acc_packets ++ new_packets, new_state}}

          {:stop, new_state} ->
            {:halt, {:stop, new_state}}

          {:disconnect, reason} ->
            {:halt, {:disconnect, reason}}
        end
      end)

    case result do
      {:ok, new_packets, new_state} ->
        process_through_read_chain(new_packets, rest_chain, [
          {module, new_state} | processed_states
        ])

      {:stop, new_state} ->
        {:stop, Enum.reverse([{module, new_state} | processed_states])}

      {:disconnect, reason} ->
        {:disconnect, reason}
    end
  end

  # Process data through WRITE protocol chain (reverse order: 2 → 1 → 0)
  defp process_through_write_chain(packets, [], processed_states) do
    # Concatenate all encoded packets
    encoded = Enum.join(packets)
    {:ok, encoded, Enum.reverse(processed_states)}
  end

  defp process_through_write_chain(packets, [{module, state} | rest_chain], processed_states) do
    result =
      Enum.reduce_while(packets, {:ok, [], state}, fn packet, {:ok, acc_packets, current_state} ->
        case module.write_data(packet, current_state) do
          {:ok, new_packets, new_state} ->
            {:cont, {:ok, acc_packets ++ new_packets, new_state}}

          {:error, reason} ->
            {:halt, {:error, reason}}
        end
      end)

    case result do
      {:ok, new_packets, new_state} ->
        process_through_write_chain(new_packets, rest_chain, [
          {module, new_state} | processed_states
        ])

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Converts protocol configuration from database format to keyword list with atoms.

  Handles:
  - String keys → atom keys
  - Hex strings → binary values (sync_pattern_hex, terminator_hex)
  - Endianness strings → atoms
  """
  @spec atomize_protocol_config(map()) :: keyword()
  def atomize_protocol_config(config) when is_map(config) do
    config
    |> Enum.map(fn
      # Convert hex strings to binary
      {"sync_pattern_hex", hex_value} when is_binary(hex_value) ->
        {:sync_pattern, hex_to_binary(hex_value)}

      {"terminator_hex", hex_value} when is_binary(hex_value) ->
        {:terminator, hex_to_binary(hex_value)}

      # Convert endianness strings to atoms
      {"length_endian", value} when value in ["big", "little"] ->
        {:length_endian, String.to_atom(value)}

      {"length_encoding", value} when value in ["big", "little"] ->
        {:length_endian, String.to_atom(value)}

      # CRC protocol config conversions
      {"algorithm", value} when is_binary(value) ->
        {:algorithm, String.to_atom(value)}

      {"endian", value} when value in ["big", "little"] ->
        {:endian, String.to_atom(value)}

      {"on_failure", value} when value in ["skip", "disconnect", "pass"] ->
        {:on_failure, String.to_atom(value)}

      # CCSDS protocol config conversions
      {"crc_algorithm", value} when is_binary(value) ->
        {:crc_algorithm, String.to_atom(value)}

      {"crc_endian", value} when value in ["big", "little"] ->
        {:crc_endian, String.to_atom(value)}

      {"crc_on_failure", value} when value in ["skip", "disconnect", "pass"] ->
        {:crc_on_failure, String.to_atom(value)}

      {"crc_enabled", value} when is_boolean(value) ->
        {:crc_enabled, value}

      {"crc_enabled", "true"} ->
        {:crc_enabled, true}

      {"crc_enabled", "false"} ->
        {:crc_enabled, false}

      {"include_sync", value} when is_boolean(value) ->
        {:include_sync, value}

      {"discard_sync", value} when is_boolean(value) ->
        {:discard_sync, value}

      # Convert other string keys to atoms
      {key, value} when is_binary(key) ->
        {String.to_atom(key), value}

      {key, value} ->
        {key, value}
    end)
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
  catch
    error ->
      Logger.error("Failed to atomize protocol config: #{inspect(error)}, config: #{inspect(config)}")
      []
  end

  def atomize_protocol_config(_), do: []

  @doc """
  Converts a hex string to binary.
  """
  @spec hex_to_binary(String.t()) :: binary() | nil
  def hex_to_binary(hex_string) when is_binary(hex_string) do
    case Base.decode16(hex_string, case: :mixed) do
      {:ok, binary} -> binary
      :error -> nil
    end
  end

  def hex_to_binary(_), do: nil
end
