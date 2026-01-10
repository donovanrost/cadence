defmodule Cadence.Telemetry.ProtocolBehaviour do
  @moduledoc """
  COSMOS-style protocol behavior.

  Protocols process data on behalf of interfaces, defining how to:
  - Delineate packet boundaries from byte streams
  - Add/remove encoding layers (encryption, compression, framing)
  - Mark packets as stored vs real-time
  - Manage connection state

  ## Protocol Methods

  Protocols implement 9 methods organized into four categories:

  ### Connection Lifecycle
  - `reset/3` - Reset protocol state (general cleanup)
  - `connect_reset/1` - Reset on connection establishment
  - `disconnect_reset/1` - Reset on disconnect

  ### Read Path (Telemetry)
  - `read_data/2` - Process raw incoming bytes, delineate packets
  - `read_packet/3` - Transform packet data/metadata after delineation

  ### Write Path (Commanding)
  - `write_packet/3` - Transform packet before encoding
  - `write_data/2` - Add encoding layers to outgoing data

  ### Hooks
  - `post_write_interface/3` - Hook after packet transmission (optional)
  - `protocol_cmd/3` - Runtime reconfiguration (optional)

  ## Return Values

  `read_data/2` and `write_data/2` return:
  - `{:ok, [binary()], protocol_state()}` - Extracted packets (may be multiple)
  - `{:stop, protocol_state()}` - Need more data, buffer and wait
  - `{:disconnect, String.t()}` - Connection error, trigger reconnect

  ## Packet Metadata

  Protocols can modify packet metadata:
  - `:stored` - true = historical data, don't update CVT
  - `:target_id` - Target identifier
  - `:received_at` - Timestamp
  - Custom fields as needed

  ## Example

      defmodule MyProtocol do
        use Cadence.Telemetry.Protocol

        def new(opts) do
          %{buffer: <<>>, ...}
        end

        def read_data(data, state) do
          # Delineate packets from byte stream
          new_buffer = state.buffer <> data

          case extract_packets(new_buffer) do
            {packets, remaining} when length(packets) > 0 ->
              {:ok, packets, %{state | buffer: remaining}}

            {[], buffer} ->
              # Need more data
              {:stop, %{state | buffer: buffer}}
          end
        end
      end

  """

  @type protocol_state :: map()
  @type direction :: :read | :write | :read_write

  @type read_result ::
          {:ok, [binary()], protocol_state()}
          | {:stop, protocol_state()}
          | {:disconnect, String.t()}

  @type packet_metadata :: %{
          required(:stored) => boolean(),
          required(:target_id) => String.t(),
          required(:received_at) => DateTime.t(),
          optional(atom()) => any()
        }

  @doc """
  Reset protocol state.

  Called during general cleanup or when manually resetting the protocol.

  ## Parameters
  - `protocol_state` - Current protocol state
  - `args` - Reset arguments (protocol-specific)
  - `interface` - Reference to interface (for accessing connection state)

  ## Returns
  Updated protocol state
  """
  @callback reset(protocol_state(), args :: keyword(), interface :: any()) :: protocol_state()

  @doc """
  Reset protocol state on connection establishment.

  Called when interface successfully connects. Use this to clear buffers
  and reset any connection-specific state.

  ## Returns
  Updated protocol state with cleared buffers
  """
  @callback connect_reset(protocol_state()) :: protocol_state()

  @doc """
  Reset protocol state on disconnection.

  Called when interface loses connection. Use this to clear buffers
  and mark any incomplete packets as failed.

  ## Returns
  Updated protocol state
  """
  @callback disconnect_reset(protocol_state()) :: protocol_state()

  @doc """
  Process incoming raw data from interface.

  This is the primary method for delineating packet boundaries. The protocol
  accumulates data in an internal buffer and extracts complete packets.

  ## Returns
  - `{:ok, [packets], new_state}` - Extracted one or more complete packets
  - `{:stop, new_state}` - Need more data, buffered for next call
  - `{:disconnect, reason}` - Protocol error, interface should reconnect

  ## Example

      def read_data(data, state) do
        buffer = state.buffer <> data

        if byte_size(buffer) >= 10 do
          <<packet::binary-size(10), rest::binary>> = buffer
          {:ok, [packet], %{state | buffer: rest}}
        else
          {:stop, %{state | buffer: buffer}}
        end
      end
  """
  @callback read_data(binary(), protocol_state()) :: read_result()

  @doc """
  Transform packet data and/or metadata after delineation.

  Called after `read_data/2` successfully extracts a packet. Use this to:
  - Mark packets as stored (historical) vs real-time
  - Extract metadata from packet headers
  - Validate packet contents
  - Add protocol-specific metadata

  ## Returns
  Tuple of `{packet_data, metadata, new_state}`

  ## Example

      def read_packet(packet, metadata, state) do
        # Mark as stored if packet has historical flag
        <<flags::8, rest::binary>> = packet

        metadata =
          if (flags &&& 0x80) != 0 do
            %{metadata | stored: true}
          else
            metadata
          end

        {rest, metadata, state}
      end
  """
  @callback read_packet(binary(), packet_metadata(), protocol_state()) ::
              {binary(), packet_metadata(), protocol_state()}

  @doc """
  Transform packet before encoding for transmission.

  Called before `write_data/2` when sending commands. Use this to:
  - Add packet headers
  - Set metadata fields
  - Validate command packets
  - Add sequence numbers

  ## Returns
  Tuple of `{packet_data, metadata, new_state}`
  """
  @callback write_packet(binary(), packet_metadata(), protocol_state()) ::
              {binary(), packet_metadata(), protocol_state()}

  @doc """
  Add encoding layers to outgoing data.

  Inverse of `read_data/2`. Adds framing headers, checksums, or other
  encoding that will be stripped by the receiving end's read_data/2.

  ## Returns
  Same as `read_data/2` but for outgoing data

  ## Example

      def write_data(data, state) do
        # Add length header
        length = byte_size(data)
        packet = <<length::32, data::binary>>
        {:ok, [packet], state}
      end
  """
  @callback write_data(binary(), protocol_state()) :: read_result()

  @doc """
  Hook called after packet transmitted to interface.

  Optional hook for post-transmission actions like:
  - Waiting for command responses
  - Tracking sent commands
  - Implementing retries

  Defaults to no-op if not implemented.
  """
  @callback post_write_interface(binary(), packet_metadata(), protocol_state()) ::
              protocol_state()

  @doc """
  Runtime protocol reconfiguration.

  Optional method for changing protocol behavior at runtime.
  Use for dynamic parameter updates without restarting.

  Defaults to no-op if not implemented.
  """
  @callback protocol_cmd(String.t(), list(), keyword()) :: any()

  @doc """
  Returns the packet format this protocol produces.

  Used by the protocol chain to determine how extracted packets should
  be identified and processed downstream.

  Returns:
  - `:ccsds` - CCSDS Space Packet Protocol (identify by APID)
  - `:raw` - Raw binary packets (generic framing)
  - `:ccsds` - CCSDS Space Packet format
  - `:raw` - Raw binary packets (no CCSDS parsing applied)

  Defaults to `:raw` if not implemented.
  """
  @callback packet_format() :: :ccsds | :raw

  @optional_callbacks [post_write_interface: 3, protocol_cmd: 3, packet_format: 0]
end
