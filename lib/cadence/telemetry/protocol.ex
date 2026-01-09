defmodule Cadence.Telemetry.Protocol do
  @moduledoc """
  Base protocol module with helpful utilities and default implementations.

  Use this module in your protocol implementation to get sensible defaults
  for the COSMOS-style protocol behavior:

      defmodule MyProtocol do
        use Cadence.Telemetry.Protocol

        def new(opts) do
          %{
            buffer: <<>>,
            my_custom_field: Keyword.get(opts, :custom)
          }
        end

        def read_data(data, state) do
          # Implement packet delineation
        end
      end

  ## Default Implementations

  Using this module provides default implementations for:
  - `reset/3` - Returns state unchanged
  - `connect_reset/1` - Clears buffer
  - `disconnect_reset/1` - Clears buffer
  - `read_packet/3` - Pass-through (packet, metadata, state)
  - `write_packet/3` - Pass-through (packet, metadata, state)
  - `write_data/2` - Pass-through wrapped in {:ok, [data], state}
  - `post_write_interface/3` - No-op

  Override any of these to implement protocol-specific behavior.

  ## Required Implementations

  You must implement:
  - `new/1` - Create initial protocol state
  - `read_data/2` - Delineate packets from byte stream

  """

  # Protocol type to module mapping (resolved at runtime to avoid circular deps)
  @protocol_modules %{
    length_prefixed: Cadence.Telemetry.Protocols.LengthProtocol,
    terminated: Cadence.Telemetry.Protocols.TerminatedProtocol,
    fixed: Cadence.Telemetry.Protocols.FixedProtocol,
    template: Cadence.Telemetry.Protocols.TemplateProtocol
  }

  @doc """
  Creates a new protocol instance by type.

  Supports the following types:
  - `:length_prefixed` - Length-prefixed packets (uses LengthProtocol)
  - `:terminated` - Terminator-delimited packets (uses TerminatedProtocol)
  - `:fixed` - Fixed-length packets (uses FixedProtocol)
  - `:template` - Sync pattern with header parsing (uses TemplateProtocol)

  ## Examples

      Protocol.new(type: :length_prefixed, length_bytes: 4)
      Protocol.new(type: :terminated, terminator: "\\r\\n")
      Protocol.new(type: :fixed, packet_length: 100)
      Protocol.new(type: :template, sync_pattern: <<0x1A, 0xCF, 0xFC, 0x1D>>, header_length: 6)
  """
  def new(opts) when is_list(opts) do
    type = Keyword.fetch!(opts, :type)
    opts = Keyword.delete(opts, :type)

    module =
      Map.get(@protocol_modules, type) ||
        raise ArgumentError, "Unknown protocol type: #{inspect(type)}"

    # Translate convenience options for length_prefixed
    opts =
      if type == :length_prefixed do
        if length_bytes = Keyword.get(opts, :length_bytes) do
          opts
          |> Keyword.delete(:length_bytes)
          |> Keyword.put_new(:length_bit_size, length_bytes * 8)
        else
          opts
        end
      else
        opts
      end

    module.new(opts)
  end

  @doc """
  Creates a new protocol instance.

  Delegates to the protocol module's `new/1` function.
  """
  def new(module, opts) when is_atom(module) do
    module.new(opts)
  end

  @doc """
  Process incoming data through a protocol.

  Dispatches to the appropriate protocol's `read_data/2` function based on state struct type.
  """
  def process(data, %{__struct__: module} = state) do
    module.read_data(data, state)
  end

  @doc """
  Provides default protocol implementations.

  When `use Cadence.Telemetry.Protocol` is called, this macro injects:
  1. The ProtocolBehaviour
  2. Default implementations that can be overridden
  """
  defmacro __using__(_opts) do
    quote do
      @behaviour Cadence.Telemetry.ProtocolBehaviour

      import Bitwise

      # Default implementations that can be overridden

      @doc """
      Reset protocol state (default: no-op).
      """
      def reset(state, _args, _interface), do: state

      @doc """
      Reset on connection (default: clear buffer).
      """
      def connect_reset(state) do
        %{state | buffer: <<>>}
      end

      @doc """
      Reset on disconnection (default: clear buffer).
      """
      def disconnect_reset(state) do
        %{state | buffer: <<>>}
      end

      @doc """
      Transform packet after delineation (default: pass-through).
      """
      def read_packet(packet, metadata, state) do
        {packet, metadata, state}
      end

      @doc """
      Transform packet before encoding (default: pass-through).
      """
      def write_packet(packet, metadata, state) do
        {packet, metadata, state}
      end

      @doc """
      Encode outgoing data (default: wrap in list).
      """
      def write_data(data, state) do
        {:ok, [data], state}
      end

      @doc """
      Post-transmission hook (default: no-op).
      """
      def post_write_interface(_packet, _metadata, state) do
        state
      end

      @doc """
      Returns the packet format this protocol produces (default: :raw).
      """
      def packet_format, do: :raw

      # Allow protocols to override defaults
      defoverridable reset: 3,
                     connect_reset: 1,
                     disconnect_reset: 1,
                     read_packet: 3,
                     write_packet: 3,
                     write_data: 2,
                     post_write_interface: 3,
                     packet_format: 0
    end
  end

  @doc """
  Helper to create default packet metadata.
  """
  def default_metadata(target_id) do
    %{
      stored: false,
      target_id: target_id,
      received_at: DateTime.utc_now()
    }
  end

  @doc """
  Helper to decode unsigned integer from binary.
  """
  def decode_unsigned(binary, :big) when is_binary(binary) do
    :binary.decode_unsigned(binary, :big)
  end

  def decode_unsigned(binary, :little) when is_binary(binary) do
    :binary.decode_unsigned(binary, :little)
  end

  @doc """
  Helper to encode unsigned integer to binary.
  """
  def encode_unsigned(value, bit_size, :big) do
    <<value::unsigned-big-size(bit_size)>>
  end

  def encode_unsigned(value, bit_size, :little) do
    <<value::unsigned-little-size(bit_size)>>
  end
end
