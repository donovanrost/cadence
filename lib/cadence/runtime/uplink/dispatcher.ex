defmodule Cadence.Runtime.Uplink.Dispatcher do
  @moduledoc """
  Mission-scoped uplink dispatcher.

  Accepts PDUs, routes them to an interface, applies SDLP framing, and sends bytes.
  """

  use GenServer

  alias Cadence.Application.Missions.MissionConfig
  alias Cadence.CCSDS.Core.PDU
  alias Cadence.CCSDS.SDU.SpacePacket
  alias Cadence.Domain.Interfaces.Entities.TargetInterface
  alias Cadence.Runtime.Telemetry.UplinkPipeline

  @sequence_mod 16_384

  defmodule State do
    @moduledoc false
    defstruct [
      :mission_id,
      routes_by_target: %{},
      sequence_counts: %{}
    ]
  end

  # ---------------------------------------------------------------------------
  # Client API
  # ---------------------------------------------------------------------------

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    config = Keyword.fetch!(opts, :config)
    GenServer.start_link(__MODULE__, config, name: via_tuple(config.mission_id))
  end

  @spec dispatch_pdu(String.t(), String.t(), PDU.t(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def dispatch_pdu(mission_id, target_id, %PDU{} = pdu, opts \\ []) do
    GenServer.call(via_tuple(mission_id), {:dispatch_pdu, target_id, pdu, opts})
  end

  @spec connected?(String.t(), String.t()) :: boolean()
  def connected?(mission_id, target_id) do
    GenServer.call(via_tuple(mission_id), {:connected?, target_id})
  end

  defp via_tuple(mission_id) do
    {:via, Registry, {Cadence.MissionRegistry, {:uplink_dispatcher, mission_id}}}
  end

  # ---------------------------------------------------------------------------
  # GenServer Callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(%MissionConfig{} = config) do
    routes_by_target = build_routes(config.target_interface_routings)

    {:ok, %State{mission_id: config.mission_id, routes_by_target: routes_by_target}}
  end

  @impl true
  def handle_call({:connected?, target_id}, _from, state) do
    routes = Map.get(state.routes_by_target, target_id, [])

    connected =
      Enum.any?(routes, fn route ->
        interface_connected?(state.mission_id, route.interface_id)
      end)

    {:reply, connected, state}
  end

  @impl true
  def handle_call({:dispatch_pdu, target_id, pdu, opts}, _from, state) do
    with {:ok, route} <- select_route(state, target_id, opts),
         :ok <- ensure_connected(state.mission_id, route.interface_id),
         {:ok, pdu, next_counts} <- prepare_pdu(pdu, state.sequence_counts),
         {:ok, encoded} <- encode_pdu(state.mission_id, route, pdu, opts),
         :ok <- send_bytes(state.mission_id, route.interface_id, encoded) do
      {:reply, {:ok, route.interface_id}, %{state | sequence_counts: next_counts}}
    else
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  # ---------------------------------------------------------------------------
  # Routing / Selection
  # ---------------------------------------------------------------------------

  defp build_routes(routings) do
    routings
    |> Enum.filter(&TargetInterface.allows_write?/1)
    |> Enum.group_by(& &1.target_id)
  end

  defp select_route(state, target_id, opts) do
    routes = Map.get(state.routes_by_target, target_id, [])

    case Keyword.get(opts, :interface_id) do
      nil ->
        case Enum.find(routes, &interface_connected?(state.mission_id, &1.interface_id)) do
          nil -> pick_route(routes)
          route -> {:ok, route}
        end

      interface_id ->
        case Enum.find(routes, &(&1.interface_id == interface_id)) do
          nil -> {:error, :no_interface}
          route -> {:ok, route}
        end
    end
  end

  defp pick_route([]), do: {:error, :no_interface}
  defp pick_route([route | _]), do: {:ok, route}

  # ---------------------------------------------------------------------------
  # Encoding / Send
  # ---------------------------------------------------------------------------

  defp ensure_connected(mission_id, interface_id) do
    if interface_connected?(mission_id, interface_id) do
      :ok
    else
      {:error, :send_failed, :no_clients_connected}
    end
  end

  defp interface_connected?(mission_id, interface_id) do
    case Registry.lookup(Cadence.MissionRegistry, {:interface, mission_id, interface_id}) do
      [{pid, _}] -> GenServer.call(pid, :connected?)
      [] -> false
    end
  end

  defp encode_pdu(mission_id, route, pdu, opts) do
    ctx =
      opts
      |> Keyword.get(:ctx, %{})
      |> Map.put_new(:scid, route.scid)

    case UplinkPipeline.encode(mission_id, route.interface_id, pdu, ctx) do
      {:ok, encoded} -> {:ok, encoded}
      {:error, reason} -> {:error, reason}
    end
  end

  defp send_bytes(mission_id, interface_id, encoded) do
    case Registry.lookup(Cadence.MissionRegistry, {:interface, mission_id, interface_id}) do
      [{pid, _}] ->
        case GenServer.call(pid, {:send_data, encoded}) do
          :ok -> :ok
          {:ok, _} -> :ok
          {:error, :not_connected} -> {:error, :send_failed, :no_clients_connected}
          {:error, :no_clients_connected} -> {:error, :send_failed, :no_clients_connected}
          {:error, reason} -> {:error, :send_failed, reason}
        end

      [] ->
        {:error, :interface_not_running}
    end
  end

  # ---------------------------------------------------------------------------
  # Sequence Management
  # ---------------------------------------------------------------------------

  defp prepare_pdu(%PDU{type: :space_packet, value: %SpacePacket{} = packet} = pdu, counts) do
    if is_nil(packet.apid) do
      {:error, :missing_apid}
    else
      {sequence_count, next_counts} =
        if is_nil(packet.sequence_count) do
          next_sequence(counts, packet.apid)
        else
          {packet.sequence_count, counts}
        end

      updated_packet =
        packet
        |> ensure_sequence_flags()
        |> Map.put(:sequence_count, sequence_count)

      {:ok, %{pdu | value: updated_packet}, next_counts}
    end
  end

  defp prepare_pdu(%PDU{} = pdu, counts), do: {:ok, pdu, counts}

  defp next_sequence(counts, apid) do
    current = Map.get(counts, apid, -1)
    next = rem(current + 1, @sequence_mod)
    {next, Map.put(counts, apid, next)}
  end

  defp ensure_sequence_flags(%SpacePacket{sequence_flags: nil} = packet) do
    %{packet | sequence_flags: 3}
  end

  defp ensure_sequence_flags(packet), do: packet
end
