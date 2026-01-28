defmodule Cadence.Runtime.Transport.InterfaceWorker do
  @moduledoc """
  Transport interface worker.

  Owns transport lifecycle only; protocol state is elsewhere.
  """

  use GenServer

  require Logger

  alias Cadence.Runtime.ChannelId
  alias Cadence.Runtime.Classifier
  alias Cadence.Runtime.Links.LinkController
  alias Cadence.Runtime.Router

  @registry Cadence.MissionRegistry

  defmodule State do
    @moduledoc false
    defstruct [:organization_id, :mission_id, :interface_id, :status, :config]
  end

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    mission_id = Keyword.fetch!(opts, :mission_id)
    interface_id = Keyword.fetch!(opts, :interface_id)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(mission_id, interface_id))
  end

  @spec send_bytes(String.t(), String.t(), binary(), map()) :: :ok
  def send_bytes(mission_id, interface_id, bytes, metadata \\ %{}) do
    GenServer.cast(via_tuple(mission_id, interface_id), {:send, bytes, metadata})
  end

  @impl true
  def init(opts) do
    mission_id = Keyword.fetch!(opts, :mission_id)
    interface_id = Keyword.fetch!(opts, :interface_id)

    Logger.debug(
      "Starting InterfaceWorker for mission_id=#{mission_id} interface_id=#{interface_id}"
    )

    {:ok,
     %State{
       organization_id: Keyword.fetch!(opts, :organization_id),
       mission_id: mission_id,
       interface_id: interface_id,
       status: :down,
       config: Keyword.get(opts, :config, %{})
     }, {:continue, :mark_connected}}
  end

  @impl true
  def handle_cast({:send, _bytes, _metadata}, state) do
    {:noreply, state}
  end

  @impl true
  def handle_call(:connected?, _from, state) do
    {:reply, state.status == :up, state}
  end

  @impl true
  def handle_continue(:mark_connected, state) do
    Router.interface_connected(state.mission_id, state.interface_id)
    {:noreply, %{state | status: :up}}
  end

  @impl true
  def handle_info({:rx_bytes, bytes, metadata}, state) do
    Logger.debug("transport.rx_bytes",
      mission_id: state.mission_id,
      interface_id: state.interface_id,
      bytes: byte_size(bytes)
    )

    case Classifier.classify(
           state.organization_id,
           state.mission_id,
           state.interface_id,
           bytes,
           metadata
         ) do
      {:ok, channel_id} ->
        Logger.debug("transport.classify.ok",
          mission_id: state.mission_id,
          interface_id: state.interface_id,
          channel_id: ChannelId.key(channel_id)
        )

        tagged_meta = Router.tag_channel_meta(metadata, channel_id)

        LinkController.route_downlink(
          state.mission_id,
          channel_id.scid,
          state.interface_id,
          bytes,
          tagged_meta
        )

      :ignore ->
        Logger.debug("transport.classify.ignore",
          mission_id: state.mission_id,
          interface_id: state.interface_id
        )

        :ok
    end

    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    Logger.debug(
      "Stopping InterfaceWorker for mission_id=#{state.mission_id} interface_id=#{state.interface_id}"
    )

    Router.interface_disconnected(state.mission_id, state.interface_id)
    :ok
  end

  defp via_tuple(mission_id, interface_id) do
    {:via, Registry, {@registry, {:transport_interface, mission_id, interface_id}}}
  end
end
