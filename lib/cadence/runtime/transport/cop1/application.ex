defmodule Cadence.Runtime.Transport.COP1.Application do
  @moduledoc """
  COP-1 application boundary for proposing sends and ingesting reports.
  """

  alias Cadence.CCSDS.Transport.COP1.CLCW
  alias Cadence.Domain.Interfaces.Entities.Interface

  alias Cadence.Runtime.Transport.COP1.Context
  alias Cadence.Runtime.Transport.COP1.FOP
  alias Cadence.Runtime.Transport.ProtocolEvent
  alias Cadence.Runtime.Uplink.RouteDecision

  @spec propose_send_frames(
          String.t(),
          RouteDecision.t(),
          [map()],
          Context.t() | nil
        ) :: :ok | {:error, term()}
  def propose_send_frames(
        mission_id,
        %RouteDecision{} = decision,
        frames,
        context \\ nil
      )
      when is_list(frames) do
    base_context = Context.from_route_decision(decision)
    final_context = Context.merge(base_context, context)

    FOP.send_frames(mission_id, decision.interface_id, frames, final_context)
  end

  @spec ingest_clcw(String.t(), String.t(), CLCW.t()) :: :ok
  def ingest_clcw(mission_id, interface_id, %CLCW{} = clcw) do
    FOP.ingest_clcw(mission_id, interface_id, clcw)
  end

  @spec enabled?(Interface.t()) :: boolean()
  def enabled?(%Interface{} = interface) do
    FOP.enabled?(interface)
  end

  @spec stats(String.t(), String.t()) :: {:ok, map()} | {:error, :cop1_fop_not_running}
  def stats(mission_id, interface_id) do
    case Registry.lookup(Cadence.MissionRegistry, {:cop1_fop, mission_id, interface_id}) do
      [{pid, _}] -> {:ok, FOP.stats(pid)}
      [] -> {:error, :cop1_fop_not_running}
    end
  end

  @spec emit_protocol_event(map() | ProtocolEvent.t()) :: :ok
  def emit_protocol_event(%ProtocolEvent{} = event) do
    ProtocolEvent.broadcast(event)
  end

  def emit_protocol_event(attrs) when is_map(attrs) do
    attrs
    |> ProtocolEvent.new()
    |> ProtocolEvent.broadcast()
  end
end
