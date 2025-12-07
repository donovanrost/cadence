defmodule Cadence.Telemetry.ProtocolChain do
  @moduledoc """
  GenServer that manages protocol chain state for an interface.

  Responsibilities:
  - Owns protocol state (buffers, configuration)
  - Processes incoming bytes into packets
  - Returns packet format along with extracted packets
  - Isolated from interface - crashes don't affect socket connections

  ## Architecture

  Each interface has one ProtocolChain process. For interfaces with multiple
  clients (like TCP server), the chain can either be shared or cloned per-client
  depending on configuration.

  ## Usage

      # Start a protocol chain for an interface
      {:ok, pid} = ProtocolChain.start_link(
        interface_id: interface_id,
        mission_id: mission_id,
        protocols: protocol_configs
      )

      # Process incoming data
      case ProtocolChain.process_read(pid, binary_data) do
        {:ok, packets} ->
          # packets is a list of {binary, format, metadata}
          Enum.each(packets, fn {packet_binary, format, metadata} ->
            # format is :ccsds, :raw, or :simulator
          end)

        :need_more_data ->
          # Protocol is buffering, wait for more data

        {:error, reason} ->
          # Processing failed
      end
  """

  use GenServer
  require Logger

  alias Cadence.Telemetry.ProtocolChain.Processor
  alias Cadence.Interfaces

  defmodule State do
    @moduledoc false
    defstruct [
      :interface_id,
      :mission_id,
      :read_chain,
      :write_chain,
      :format,
      # Original configs for cloning (for per-client chains)
      :protocol_configs
    ]
  end

  ## Client API

  @doc """
  Starts a ProtocolChain process for an interface.

  Options:
  - `:interface_id` - Required. The interface this chain belongs to.
  - `:mission_id` - Required. The mission context.
  - `:protocols` - Optional. List of InterfaceProtocol configs. If not provided,
    will be loaded from database.
  """
  def start_link(opts) do
    interface_id = Keyword.fetch!(opts, :interface_id)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(interface_id))
  end

  @doc """
  Returns the via tuple for registry lookup.
  """
  def via_tuple(interface_id) do
    {:via, Registry, {Cadence.ProtocolChainRegistry, interface_id}}
  end

  @doc """
  Returns the PID of a protocol chain by interface_id.
  """
  def whereis(interface_id) do
    case Registry.lookup(Cadence.ProtocolChainRegistry, interface_id) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  @doc """
  Processes binary data through the read protocol chain.

  Returns:
  - `{:ok, [{packet_binary, format, metadata}]}` - Successfully extracted packets
  - `:need_more_data` - Protocol is buffering, waiting for more data
  - `{:error, reason}` - Processing failed
  """
  @spec process_read(pid() | GenServer.name(), binary(), map()) ::
          {:ok, [{binary(), atom(), map()}]}
          | :need_more_data
          | {:error, term()}
  def process_read(chain, data, metadata \\ %{}) do
    GenServer.call(chain, {:process_read, data, metadata})
  end

  @doc """
  Processes a packet through the write protocol chain for transmission.

  Returns:
  - `{:ok, encoded_binary}` - Successfully encoded packet
  - `{:error, reason}` - Encoding failed
  """
  @spec process_write(pid() | GenServer.name(), binary()) ::
          {:ok, binary()}
          | {:error, term()}
  def process_write(chain, packet) do
    GenServer.call(chain, {:process_write, packet})
  end

  @doc """
  Returns the packet format this chain produces.
  """
  @spec get_format(pid() | GenServer.name()) :: :ccsds | :raw | :simulator
  def get_format(chain) do
    GenServer.call(chain, :get_format)
  end

  @doc """
  Resets the protocol chain state (e.g., on reconnection).
  Clears all buffers but keeps configuration.
  """
  @spec reset(pid() | GenServer.name()) :: :ok
  def reset(chain) do
    GenServer.call(chain, :reset)
  end

  @doc """
  Creates a fresh clone of this chain's configuration.

  Used for per-client protocol instances in multi-client interfaces.
  Returns the initialized chain ready for use.
  """
  @spec clone(pid() | GenServer.name()) :: {:ok, Processor.protocol_chain()} | {:error, term()}
  def clone(chain) do
    GenServer.call(chain, :clone)
  end

  ## Server Callbacks

  @impl true
  def init(opts) do
    interface_id = Keyword.fetch!(opts, :interface_id)
    mission_id = Keyword.fetch!(opts, :mission_id)

    # Load protocols from opts or database
    protocol_configs =
      Keyword.get_lazy(opts, :protocols, fn ->
        Interfaces.list_protocols(interface_id)
      end)

    # Initialize read and write chains
    read_chain = Processor.init_chain(protocol_configs, "read")
    write_chain = Processor.init_chain(protocol_configs, "write")

    # Determine format based on read chain
    format = Processor.chain_format(read_chain)

    # Store original configs for cloning
    configs_for_clone =
      protocol_configs
      |> Enum.filter(fn config -> config.protocol_direction in ["read", "read_write"] end)
      |> Enum.map(fn config -> {config.protocol_type, config.protocol_config} end)

    Logger.info(
      "ProtocolChain started for interface_id=#{interface_id}, " <>
        "read_protocols=#{length(read_chain)}, write_protocols=#{length(write_chain)}, " <>
        "format=#{format}"
    )

    state = %State{
      interface_id: interface_id,
      mission_id: mission_id,
      read_chain: read_chain,
      write_chain: write_chain,
      format: format,
      protocol_configs: configs_for_clone
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:process_read, data, metadata}, _from, state) do
    case Processor.process_read(state.read_chain, data) do
      {:ok, packets, updated_chain} ->
        # Wrap each packet with format and metadata
        packets_with_format =
          Enum.map(packets, fn packet_binary ->
            {packet_binary, state.format, metadata}
          end)

        {:reply, {:ok, packets_with_format}, %{state | read_chain: updated_chain}}

      {:stop, updated_chain} ->
        {:reply, :need_more_data, %{state | read_chain: updated_chain}}

      {:disconnect, reason} ->
        {:reply, {:error, {:disconnect, reason}}, state}
    end
  end

  def handle_call({:process_write, packet}, _from, state) do
    case Processor.process_write(state.write_chain, packet) do
      {:ok, encoded, updated_chain} ->
        {:reply, {:ok, encoded}, %{state | write_chain: updated_chain}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:get_format, _from, state) do
    {:reply, state.format, state}
  end

  def handle_call(:reset, _from, state) do
    read_chain = Processor.reset_chain(state.read_chain)
    write_chain = Processor.reset_chain(state.write_chain)

    {:reply, :ok, %{state | read_chain: read_chain, write_chain: write_chain}}
  end

  def handle_call(:clone, _from, state) do
    cloned_chain = Processor.clone_chain(state.protocol_configs)
    {:reply, {:ok, cloned_chain}, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info(
      "ProtocolChain terminating for interface_id=#{state.interface_id}: #{inspect(reason)}"
    )

    :ok
  end
end
