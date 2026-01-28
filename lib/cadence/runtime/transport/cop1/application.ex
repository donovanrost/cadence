defmodule Cadence.Runtime.Transport.COP1.Application do
  @moduledoc """
  COP-1 application boundary for proposing sends and ingesting reports.
  """

  alias Cadence.Runtime.ChannelId
  alias Cadence.Runtime.Transport.COP1.Context
  alias Cadence.Runtime.Transport.COP1.FOP
  alias Cadence.Runtime.Transport.COP1.Metrics
  alias Cadence.Runtime.Transport.COP1.Report
  alias Cadence.Runtime.Transport.ProtocolEvent
  alias Cadence.Transport.TCStreamId

  @spec propose_send_frames(
          String.t(),
          ChannelId.t(),
          [map()],
          Context.t() | nil
        ) :: :ok | {:error, term()} | {:defer, term()}
  def propose_send_frames(mission_id, %ChannelId{} = channel_id, frames, context \\ nil)
      when is_list(frames) do
    base_context = Context.new(stream_id: TCStreamId.new_from_channel!(mission_id, channel_id))
    final_context = Context.merge(base_context, context)

    FOP.send_frames(mission_id, channel_id, frames, final_context)
  end

  @spec ingest_report(Report.t()) :: :ok
  def ingest_report(%Report{} = report) do
    FOP.ingest_report(report)
  end

  @spec ingest_clcw(String.t(), ChannelId.t(), term()) :: :ok
  def ingest_clcw(mission_id, %ChannelId{} = channel_id, clcw) do
    FOP.ingest_clcw(mission_id, channel_id, clcw)
  end

  @spec report_decode_failed(term(), map()) :: :ok
  def report_decode_failed(reason, ctx \\ %{}) do
    mission_id = Map.get(ctx, :mission_id)
    interface_id = Map.get(ctx, :interface_id)
    scid = Map.get(ctx, :scid)
    vcid = Map.get(ctx, :vcid)

    if is_binary(mission_id) and is_integer(scid) and is_integer(vcid) do
      Metrics.inc(mission_id, interface_id, scid, vcid, :cop1_report_decode_failures_total, 1)
    end

    tc_stream_id =
      if is_binary(mission_id) and is_integer(scid) and is_integer(vcid) do
        TCStreamId.new!(mission_id, interface_id, scid, vcid)
      else
        nil
      end

    event = %{
      mission_id: mission_id,
      interface_id: interface_id,
      protocol: :cop1,
      status: :cop1_report_decode_failed,
      reason: reason,
      stream_id: tc_stream_id
    }

    emit_protocol_event(event)
  end

  @spec stats(String.t(), ChannelId.t()) :: {:ok, map()} | {:error, :cop1_fop_not_running}
  def stats(mission_id, %ChannelId{} = channel_id) do
    case Registry.lookup(
           Cadence.MissionRegistry,
           {:cop1_fop, mission_id, ChannelId.key(channel_id)}
         ) do
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
