defmodule Cadence.Runtime.Uplink.Dispatcher do
  @moduledoc """
  Mission-scoped uplink dispatcher.

  Accepts PDUs, routes them to an interface, applies SDLP framing, and sends bytes.
  Non-COP-1 sends are dispatched via UplinkPipeline.
  """

  use GenServer

  alias Cadence.Application.Missions.MissionConfig
  alias Cadence.Runtime.Telemetry.UplinkPipeline
  alias Cadence.Runtime.Transport.COP1.Application, as: COP1Application
  alias Cadence.Runtime.Transport.COP1.Context, as: COP1Context
  alias Cadence.Runtime.Uplink.FramingContext
  alias Cadence.Runtime.Uplink.ReleasedUplinkFrame
  alias Cadence.Runtime.Uplink.RouteDecision
  alias Cadence.Runtime.Uplink.RoutingService
  alias Cadence.Runtime.Uplink.SequenceManager
  alias Cadence.Runtime.Uplink.TCFraming
  alias Cadence.Runtime.Uplink.UplinkPDU

  defmodule State do
    @moduledoc false
    defstruct [
      :mission_id,
      :routing_service,
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

  @spec dispatch_pdu(String.t(), UplinkPDU.t(), keyword()) ::
          {:ok, RouteDecision.t()} | {:error, term()}
  def dispatch_pdu(mission_id, %UplinkPDU{} = uplink_pdu, opts \\ []) do
    GenServer.call(via_tuple(mission_id), {:dispatch_pdu, uplink_pdu, opts})
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
    routing_service = RoutingService.new(config)

    {:ok,
     %State{
       mission_id: config.mission_id,
       routing_service: routing_service
     }}
  end

  @impl true
  def handle_call({:connected?, target_id}, _from, state) do
    routes = RoutingService.routes_for_target(state.routing_service, target_id)

    connected =
      Enum.any?(routes, fn route ->
        interface_connected?(state.mission_id, route.interface_id)
      end)

    {:reply, connected, state}
  end

  @impl true
  def handle_call({:dispatch_pdu, uplink_pdu, opts}, _from, state) do
    case do_dispatch_pdu(state, uplink_pdu, opts) do
      {:ok, decision, next_counts} ->
        {:reply, {:ok, decision}, %{state | sequence_counts: next_counts}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}

      {:error, reason, detail} ->
        {:reply, {:error, reason, detail}, state}
    end
  end

  defp do_dispatch_pdu(state, %UplinkPDU{} = uplink_pdu, opts) do
    routing_opts = Keyword.take(opts, [:interface_id])

    with {:ok, decision} <-
           RoutingService.route(state.routing_service, uplink_pdu, routing_opts),
         :ok <- ensure_connected(state.mission_id, decision.interface_id),
         {:ok, pdu, next_counts} <-
           SequenceManager.prepare_pdu(uplink_pdu.pdu, state.sequence_counts),
         :ok <-
           dispatch_via_route(
             state,
             decision,
             UplinkPDU.from_pdu(uplink_pdu.target_id, pdu),
             opts
           ) do
      {:ok, decision, next_counts}
    else
      {:error, reason} -> {:error, reason}
      {:error, reason, detail} -> {:error, reason, detail}
    end
  end

  defp dispatch_via_route(state, %RouteDecision{} = decision, %UplinkPDU{} = uplink_pdu, opts) do
    framing_override = Keyword.get(opts, :framing_context)
    cop1_override = Keyword.get(opts, :cop1_context)
    {framing_context, cop1_context} = build_contexts(decision, framing_override, cop1_override)

    if decision.cop1_mode == :fop do
      case TCFraming.build_frames(
             state.mission_id,
             decision.interface_id,
             uplink_pdu.pdu,
             framing_context
           ) do
        {:ok, frames} ->
          COP1Application.propose_send_frames(state.mission_id, decision, frames, cop1_context)

        {:error, reason} ->
          {:error, reason}
      end
    else
      case encode_pdu(state.mission_id, decision, uplink_pdu.pdu, framing_context) do
        {:ok, encoded} ->
          send_release(state.mission_id, decision, encoded, nil)

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp build_contexts(%RouteDecision{} = decision, framing_override, cop1_override) do
    base_framing = FramingContext.from_route_decision(decision)
    base_cop1 = COP1Context.from_route_decision(decision)

    framing_context = FramingContext.merge(base_framing, framing_override)
    cop1_context = COP1Context.merge(base_cop1, cop1_override)

    framing_context =
      framing_context
      |> FramingContext.put_if_nil(:stream_id, cop1_context.stream_id)
      |> FramingContext.put_if_nil(:initial_seq, cop1_context.initial_seq)

    {framing_context, cop1_context}
  end

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

  defp encode_pdu(mission_id, %RouteDecision{} = decision, pdu, %FramingContext{} = context) do
    case UplinkPipeline.encode(mission_id, decision.interface_id, pdu, context) do
      {:ok, encoded} -> {:ok, encoded}
      {:error, reason} -> {:error, reason}
    end
  end

  defp send_release(mission_id, %RouteDecision{} = decision, encoded, correlation_id) do
    release =
      ReleasedUplinkFrame.from_bytes(
        mission_id,
        decision.interface_id,
        decision.tc_stream_id,
        encoded,
        :direct,
        correlation_id
      )

    UplinkPipeline.send_release(release)
  end
end
