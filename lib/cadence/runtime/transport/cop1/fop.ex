defmodule Cadence.Runtime.Transport.COP1.FOP do
  @moduledoc """
  Ground-side COP-1 FOP controller for TC uplink, keyed by channel.
  """

  use GenServer
  require Logger

  alias Cadence.Domain.Interfaces.Entities.Interface
  alias Cadence.Runtime.ChannelId
  alias Cadence.Runtime.Links.LinkController
  alias Cadence.Runtime.Transport

  alias Cadence.Runtime.Transport.COP1.Application, as: COP1Application
  alias Cadence.Runtime.Transport.COP1.Config
  alias Cadence.Runtime.Transport.COP1.Context
  alias Cadence.Runtime.Transport.COP1.Report
  alias Cadence.Runtime.Transport.COP1.StreamServer
  alias Cadence.Runtime.Transport.COP1.StreamSupervisor
  alias Cadence.Transport.TCStreamId

  @registry Cadence.MissionRegistry
  @default_window_size 4
  @default_timeout_ms 5_000
  @default_max_retransmit 3

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    mission_id = Keyword.fetch!(opts, :mission_id)
    channel_id = Keyword.fetch!(opts, :channel_id)
    name = via_tuple(mission_id, channel_id)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @spec enabled?(Interface.t()) :: boolean()
  def enabled?(%Interface{} = interface) do
    Config.enabled?(interface)
  end

  @spec mode_for(Interface.t(), atom() | nil, non_neg_integer() | nil) :: :fop | :bypass
  def mode_for(%Interface{} = interface, pdu_type \\ nil, apid \\ nil) do
    Config.mode_for(interface, pdu_type, apid)
  end

  @spec send_frames(String.t(), ChannelId.t(), [map()], Context.t() | nil) ::
          :ok | {:error, term()} | {:defer, term()}
  def send_frames(mission_id, %ChannelId{} = channel_id, frames, context \\ nil)
      when is_list(frames) do
    GenServer.call(via_tuple(mission_id, channel_id), {:send_frames, frames, context})
  end

  @spec ingest_report(Report.t()) :: :ok
  def ingest_report(%Report{tc_stream_id: %TCStreamId{} = tc_stream_id} = report) do
    channel_id = ChannelId.new(tc_stream_id.scid, tc_stream_id.vcid, tc_stream_id.map_id)

    GenServer.cast(
      via_tuple(tc_stream_id.mission_id, channel_id),
      {:report, report}
    )
  end

  @spec ingest_clcw(String.t(), ChannelId.t(), term()) :: :ok
  def ingest_clcw(mission_id, %ChannelId{} = channel_id, _clcw) do
    COP1Application.report_decode_failed(:missing_scid, %{
      mission_id: mission_id,
      channel_id: channel_id
    })
  end

  @spec stats(pid()) :: map()
  def stats(pid) do
    GenServer.call(pid, :stats)
  end

  def via_tuple(mission_id, %ChannelId{} = channel_id) do
    {:via, Registry, {@registry, {:cop1_fop, mission_id, ChannelId.key(channel_id)}}}
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(opts) do
    mission_id = Keyword.fetch!(opts, :mission_id)
    channel_id = Keyword.fetch!(opts, :channel_id)
    protocol_config = Keyword.get(opts, :protocol_config, %{})
    sdlp = Map.get(protocol_config, :sdlp, :error)
    cop1 = Map.get(protocol_config, :cop1, %{})
    default_interface_id = Map.get(protocol_config, :interface_id)
    enabled = Config.mode(cop1) == :fop
    release_fun = Keyword.get(opts, :release_fun, &default_release_fun/1)
    event_fun = Keyword.get(opts, :event_fun, &COP1Application.emit_protocol_event/1)

    {frame_size, default_scid, default_vcid} = sdlp_uplink_defaults(sdlp, channel_id)
    enabled = ensure_frame_size(enabled, frame_size)

    base_stream = %{
      mission_id: mission_id,
      interface_id: nil,
      enabled: enabled,
      release_fun: release_fun,
      frame_size: frame_size,
      default_scid: default_scid,
      default_vcid: default_vcid,
      window_size: parse_window_size(cop1),
      timeout_ms: parse_timeout_ms(cop1),
      max_retransmit: parse_max_retransmit(cop1),
      initial_seq: parse_initial_seq(cop1),
      event_fun: event_fun
    }

    state = %{
      mission_id: mission_id,
      channel_id: channel_id,
      default_interface_id: default_interface_id,
      enabled: enabled,
      base_stream: base_stream,
      reports_by_stream: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:send_frames, _frames, _ctx}, _from, %{enabled: false} = state) do
    {:reply, {:error, :cop1_disabled}, state}
  end

  def handle_call({:send_frames, frames, context}, _from, state) when is_list(frames) do
    with {:ok, context} <- normalize_context(context),
         {:ok, interface_id} <- active_interface(state),
         {:ok, stream_id} <- resolve_stream_id(context, state, interface_id),
         {:ok, vcid} <- resolve_stream_vcid(context, stream_id, state.base_stream),
         base_stream <- %{state.base_stream | interface_id: interface_id},
         {:ok, pid, status} <-
           StreamSupervisor.ensure_stream(state.mission_id, stream_id, base_stream, vcid: vcid),
         :ok <- maybe_apply_cached_report(status, pid, state, stream_id) do
      case StreamServer.send_frames(pid, frames, context) do
        :ok -> {:reply, :ok, state}
        {:defer, reason} -> {:reply, {:defer, reason}, state}
        {:error, {:send_failed, reason}} -> {:reply, {:error, :send_failed, reason}, state}
        {:error, reason} -> {:reply, {:error, reason}, state}
      end
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:send_frames, _frames, _context}, _from, state) do
    {:reply, {:error, :invalid_payload}, state}
  end

  def handle_call(:stats, _from, state) do
    streams = StreamSupervisor.stream_stats(state.mission_id)
    {:reply, aggregate_stats(streams, state.enabled, state.channel_id), state}
  end

  @impl true
  def handle_cast({:report, %Report{} = report}, %{enabled: true} = state) do
    state = cache_report(state, report)

    case StreamSupervisor.deliver_report(state.mission_id, report) do
      :ok ->
        :ok

      :unknown_stream ->
        COP1Application.emit_protocol_event(%{
          mission_id: state.mission_id,
          protocol: :cop1,
          status: :cop1_report_for_unknown_stream,
          stream_id: report.tc_stream_id
        })
    end

    {:noreply, state}
  end

  def handle_cast({:report, %Report{}}, state), do: {:noreply, state}

  @impl true
  def handle_info({:fop_timeout, seq}, state) do
    StreamSupervisor.broadcast_timeout(state.mission_id, seq)
    {:noreply, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp active_interface(state) do
    if link_controller_running?(state) do
      case LinkController.active_uplink_interface(state.mission_id, state.channel_id) do
        nil -> fallback_interface(state)
        interface_id -> {:ok, interface_id}
      end
    else
      fallback_interface(state)
    end
  end

  defp fallback_interface(state) do
    if is_binary(state.default_interface_id) do
      {:ok, state.default_interface_id}
    else
      {:error, :no_active_interface}
    end
  end

  defp link_controller_running?(state) do
    Registry.lookup(
      Cadence.MissionRegistry,
      {:link_controller, state.mission_id, state.channel_id.scid}
    ) != []
  end

  defp sdlp_uplink_defaults({:ok, %{opts: opts}}, %ChannelId{} = channel_id) do
    frame_size = opts[:uplink_frame_size] || opts[:frame_size]
    uplink_scid = opts[:uplink_scid] || channel_id.scid
    uplink_vcid = opts[:uplink_vcid] || channel_id.vcid
    {frame_size, uplink_scid, uplink_vcid}
  end

  defp sdlp_uplink_defaults(_sdlp, %ChannelId{} = channel_id) do
    {nil, channel_id.scid, channel_id.vcid}
  end

  defp ensure_frame_size(enabled, frame_size) do
    if enabled and not is_integer(frame_size) do
      Logger.warning("COP-1 FOP disabled: missing uplink frame_size")
      false
    else
      enabled
    end
  end

  defp default_release_fun(%Cadence.Runtime.Uplink.ReleasedUplinkFrame{} = release) do
    meta = %{
      stream_id: release.stream_id,
      seq: release.seq,
      retries: release.retries,
      kind: release.kind,
      correlation_id: release.correlation_id
    }

    case Transport.send_bytes(release.mission_id, release.interface_id, release.bytes, meta) do
      :ok -> :ok
      {:error, reason} -> {:error, :send_failed, reason}
    end
  end

  defp normalize_context(nil), do: {:ok, Context.new()}
  defp normalize_context(%Context{} = context), do: {:ok, context}
  defp normalize_context(_), do: {:error, :invalid_context}

  defp resolve_stream_id(%Context{stream_id: %TCStreamId{} = stream_id}, _state, _interface_id),
    do: {:ok, stream_id}

  defp resolve_stream_id(%Context{} = context, state, interface_id) do
    scid = (context.stream_id && context.stream_id.scid) || state.channel_id.scid
    vcid = (context.stream_id && context.stream_id.vcid) || state.channel_id.vcid
    map_id = context.stream_id && context.stream_id.map_id

    {:ok, TCStreamId.new!(state.mission_id, interface_id, scid, vcid, map_id: map_id)}
  end

  defp resolve_stream_vcid(%Context{vcid: vcid}, _stream_id, _base_stream) when is_integer(vcid),
    do: {:ok, vcid}

  defp resolve_stream_vcid(_context, %TCStreamId{vcid: vcid}, _base_stream)
       when is_integer(vcid),
       do: {:ok, vcid}

  defp resolve_stream_vcid(_context, _stream_id, %{default_vcid: vcid}) when is_integer(vcid),
    do: {:ok, vcid}

  defp resolve_stream_vcid(_, _, _), do: {:error, :missing_vcid}

  defp aggregate_stats(streams, enabled, channel_id) do
    streams
    |> Enum.filter(fn %{stream_id: stream_id} ->
      stream_id.scid == channel_id.scid and stream_id.vcid == channel_id.vcid
    end)
    |> Enum.reduce(
      %{
        enabled: enabled,
        in_flight_count: 0,
        pending_count: 0,
        lockout: false,
        held: false,
        wait: false,
        retransmit: false,
        unlock_pending: false,
        last_report_value: nil
      },
      fn stream, acc ->
        stats = stream.stats

        acc
        |> Map.update(:in_flight_count, stats.in_flight_count, &(&1 + stats.in_flight_count))
        |> Map.update(:pending_count, stats.pending_count, &(&1 + stats.pending_count))
        |> Map.update(:lockout, stats.lockout, &(&1 || stats.lockout))
        |> Map.update(:held, stats.held, &(&1 || stats.held))
        |> Map.update(:wait, stats.wait, &(&1 || stats.wait))
        |> Map.update(:retransmit, stats.retransmit, &(&1 || stats.retransmit))
        |> Map.update(:unlock_pending, stats.unlock_pending, &(&1 || stats.unlock_pending))
        |> Map.update(:last_report_value, stats.last_report_value, fn current ->
          merge_report_value(current, stats.last_report_value)
        end)
      end
    )
  end

  defp merge_report_value(nil, value), do: value
  defp merge_report_value(value, nil), do: value

  defp merge_report_value(value, next) when is_integer(value) and is_integer(next),
    do: max(value, next)

  defp cache_report(state, %Report{} = report) do
    key = TCStreamId.to_key(report.tc_stream_id)
    %{state | reports_by_stream: Map.put(state.reports_by_stream, key, report)}
  end

  defp maybe_apply_cached_report(:started, pid, state, %TCStreamId{} = stream_id) do
    key = TCStreamId.to_key(stream_id)

    case Map.get(state.reports_by_stream, key) do
      nil -> :ok
      report -> StreamServer.apply_report(pid, report)
    end
  end

  defp maybe_apply_cached_report(:existing, _pid, _state, _stream_id), do: :ok

  defp parse_window_size(cop1) do
    parse_integer(fetch_value(cop1, ["window_size", :window_size])) || @default_window_size
  end

  defp parse_timeout_ms(cop1) do
    parse_integer(fetch_value(cop1, ["timeout_ms", :timeout_ms])) || @default_timeout_ms
  end

  defp parse_max_retransmit(cop1) do
    parse_integer(fetch_value(cop1, ["max_retransmit", :max_retransmit])) ||
      @default_max_retransmit
  end

  defp parse_initial_seq(cop1) do
    parse_integer(fetch_value(cop1, ["initial_seq", :initial_seq]))
  end

  defp fetch_value(config, keys) when is_list(keys) do
    Enum.find_value(keys, fn key -> Map.get(config, key) end)
  end

  defp fetch_value(config, key), do: Map.get(config, key)

  defp parse_integer(nil), do: nil
  defp parse_integer(value) when is_integer(value), do: value

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp parse_integer(_value), do: nil
end
