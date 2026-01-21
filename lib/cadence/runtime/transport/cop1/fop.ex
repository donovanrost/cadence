defmodule Cadence.Runtime.Transport.COP1.FOP do
  @moduledoc """
  Ground-side COP-1 FOP controller for TC uplink.
  """

  use GenServer
  require Logger

  alias Cadence.CCSDS.Transport.COP1.CLCW
  alias Cadence.Domain.Interfaces.Entities.Interface
  alias Cadence.Runtime.Interfaces.SDLPConfig
  alias Cadence.Runtime.Telemetry.UplinkPipeline

  alias Cadence.Runtime.Transport.COP1.Application, as: COP1Application
  alias Cadence.Runtime.Transport.COP1.Config
  alias Cadence.Runtime.Transport.COP1.Context
  alias Cadence.Runtime.Transport.COP1.StreamServer
  alias Cadence.Runtime.Transport.COP1.StreamSupervisor

  @registry Cadence.MissionRegistry
  @default_window_size 4
  @default_timeout_ms 5_000
  @default_max_retransmit 3

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    interface = Keyword.fetch!(opts, :interface)
    name = via_tuple(interface.mission_id, interface.id)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @spec enabled?(Interface.t()) :: boolean()
  def enabled?(%Interface{} = interface) do
    Config.enabled?(interface)
  end

  @spec mode_for(Interface.t(), atom() | nil, non_neg_integer() | nil) :: :fop | :disabled
  def mode_for(%Interface{} = interface, pdu_type \\ nil, apid \\ nil) do
    Config.mode_for(interface, pdu_type, apid)
  end

  @spec send_frames(String.t(), String.t(), [map()], Context.t() | nil) ::
          :ok | {:error, term()}
  def send_frames(mission_id, interface_id, frames, context \\ nil) when is_list(frames) do
    GenServer.call(via_tuple(mission_id, interface_id), {:send_frames, frames, context})
  end

  @spec ingest_clcw(String.t(), String.t(), CLCW.t()) :: :ok
  def ingest_clcw(mission_id, interface_id, %CLCW{} = clcw) do
    GenServer.cast(via_tuple(mission_id, interface_id), {:clcw, clcw})
  end

  @spec stats(pid()) :: map()
  def stats(pid) do
    GenServer.call(pid, :stats)
  end

  def via_tuple(mission_id, interface_id) do
    {:via, Registry, {@registry, {:cop1_fop, mission_id, interface_id}}}
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(opts) do
    interface = Keyword.fetch!(opts, :interface)
    cop1 = Config.config(interface.config || %{})
    enabled = Config.mode(cop1) == :fop
    sdlp = SDLPConfig.fetch(interface)
    release_fun = Keyword.get(opts, :release_fun, &UplinkPipeline.send_release/1)
    event_fun = Keyword.get(opts, :event_fun, &COP1Application.emit_protocol_event/1)

    {frame_size, default_scid, default_vcid} = sdlp_uplink_defaults(interface, sdlp)
    enabled = ensure_frame_size(enabled, frame_size)

    base_stream = %{
      mission_id: interface.mission_id,
      interface_id: interface.id,
      enabled: enabled,
      release_fun: release_fun,
      frame_size: frame_size,
      default_scid: default_scid,
      default_vcid: default_vcid,
      window_size: parse_window_size(cop1),
      timeout_ms: parse_timeout_ms(cop1),
      max_retransmit: parse_max_retransmit(cop1),
      bypass_flag: parse_flag(cop1, ["bypass_flag", :bypass_flag, "bypass", :bypass], 0),
      control_command_flag:
        parse_flag(
          cop1,
          ["control_command_flag", :control_command_flag, "control_command", :control_command],
          0
        ),
      segment_header_flag: parse_flag(cop1, ["segment_header_flag", :segment_header_flag], 0),
      initial_seq: parse_initial_seq(cop1),
      event_fun: event_fun
    }

    state = %{
      mission_id: interface.mission_id,
      interface_id: interface.id,
      enabled: enabled,
      base_stream: base_stream,
      clcw_by_vcid: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:send_frames, _frames, _ctx}, _from, %{enabled: false} = state) do
    {:reply, {:error, :cop1_disabled}, state}
  end

  def handle_call({:send_frames, frames, context}, _from, state) when is_list(frames) do
    with {:ok, context} <- normalize_context(context),
         {:ok, stream_id} <- resolve_stream_id(context, state.interface_id),
         {:ok, vcid} <- resolve_stream_vcid(context, stream_id, state.base_stream),
         {:ok, pid, status} <-
           StreamSupervisor.ensure_stream(
             state.mission_id,
             state.interface_id,
             stream_id,
             state.base_stream,
             vcid: vcid
           ),
         :ok <- maybe_apply_cached_clcw(status, pid, state, vcid) do
      case StreamServer.send_frames(pid, frames, context) do
        :ok ->
          {:reply, :ok, state}

        {:error, {:send_failed, reason}} ->
          {:reply, {:error, :send_failed, reason}, state}

        {:error, reason} ->
          {:reply, {:error, reason}, state}
      end
    else
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:send_frames, _frames, _context}, _from, state) do
    {:reply, {:error, :invalid_payload}, state}
  end

  def handle_call(:stats, _from, state) do
    streams = StreamSupervisor.stream_stats(state.mission_id, state.interface_id)
    {:reply, aggregate_stats(streams, state.enabled), state}
  end

  @impl true
  def handle_cast({:clcw, %CLCW{} = clcw}, %{enabled: true} = state) do
    state = cache_clcw(state, clcw)
    StreamSupervisor.broadcast_clcw(state.mission_id, state.interface_id, clcw)
    {:noreply, state}
  end

  def handle_cast({:clcw, %CLCW{}}, state), do: {:noreply, state}

  @impl true
  def handle_info({:fop_timeout, seq}, state) do
    StreamSupervisor.broadcast_timeout(state.mission_id, state.interface_id, seq)
    {:noreply, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # Config and defaults
  # ---------------------------------------------------------------------------

  defp sdlp_uplink_defaults(_interface, {:ok, %{opts: opts}}) do
    frame_size = opts[:uplink_frame_size] || opts[:frame_size]
    {frame_size, opts[:uplink_scid], opts[:uplink_vcid]}
  end

  defp sdlp_uplink_defaults(%Interface{config: config}, :error) do
    sdlp = fetch_value(config || %{}, ["sdlp", :sdlp]) || %{}

    frame_size =
      parse_integer(fetch_value(sdlp, ["uplink_frame_size", :uplink_frame_size])) ||
        parse_integer(fetch_value(sdlp, ["frame_size", :frame_size]))

    uplink_scid = parse_integer(fetch_value(sdlp, ["uplink_scid", :uplink_scid]))
    uplink_vcid = parse_integer(fetch_value(sdlp, ["uplink_vcid", :uplink_vcid]))

    {frame_size, uplink_scid, uplink_vcid}
  end

  defp sdlp_uplink_defaults(_interface, _), do: {nil, nil, nil}

  defp ensure_frame_size(true, frame_size) when is_integer(frame_size), do: true

  defp ensure_frame_size(true, _frame_size) do
    Logger.warning("COP-1 FOP disabled: missing uplink frame_size")
    false
  end

  defp ensure_frame_size(false, _frame_size), do: false

  defp parse_window_size(cop1) do
    case parse_integer(fetch_value(cop1, ["window_size", :window_size])) do
      nil -> @default_window_size
      value when value > 0 -> value
      _ -> @default_window_size
    end
  end

  defp parse_timeout_ms(cop1) do
    case parse_integer(fetch_value(cop1, ["timeout_ms", :timeout_ms])) do
      nil -> @default_timeout_ms
      value when value > 0 -> value
      _ -> @default_timeout_ms
    end
  end

  defp parse_max_retransmit(cop1) do
    case parse_integer(fetch_value(cop1, ["max_retransmit", :max_retransmit])) do
      nil -> @default_max_retransmit
      value when value >= 0 -> value
      _ -> @default_max_retransmit
    end
  end

  defp parse_initial_seq(cop1) do
    parse_integer(fetch_value(cop1, ["initial_seq", :initial_seq])) || 0
  end

  defp parse_flag(cop1, keys, default) do
    case fetch_value(cop1, keys) do
      value when value in [0, 1] -> value
      true -> 1
      false -> 0
      _ -> default
    end
  end

  defp fetch_value(config, keys) do
    Enum.find_value(keys, fn key -> Map.get(config, key) end)
  end

  defp parse_integer(nil), do: nil
  defp parse_integer(value) when is_integer(value), do: value

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp parse_integer(_), do: nil

  defp resolve_stream_id(%Context{} = context, interface_id) do
    case context.stream_id do
      {target_id, ^interface_id, vcid} when is_binary(target_id) ->
        {:ok, {target_id, interface_id, vcid}}

      {target_id, other_interface_id, _vcid} when is_binary(target_id) ->
        {:error, {:tc_stream_interface_mismatch, other_interface_id}}

      stream_id when is_binary(stream_id) or is_integer(stream_id) ->
        {:ok, stream_id}

      nil ->
        {:error, :missing_tc_stream_id}

      _ ->
        {:error, :invalid_tc_stream_id}
    end
  end

  defp resolve_stream_id(_ctx, _interface_id), do: {:error, :missing_tc_stream_id}

  defp normalize_context(nil), do: {:ok, Context.new()}
  defp normalize_context(%Context{} = context), do: {:ok, context}
  defp normalize_context(_context), do: {:error, :invalid_cop1_context}

  defp resolve_stream_vcid(%Context{} = context, stream_id, base_stream) do
    vcid =
      context.vcid || stream_vcid_from_id(stream_id) ||
        Map.get(base_stream, :default_vcid)

    if is_integer(vcid) do
      {:ok, vcid}
    else
      {:error, :missing_vcid}
    end
  end

  defp stream_vcid_from_id({_target_id, _interface_id, vcid}) when is_integer(vcid), do: vcid
  defp stream_vcid_from_id(_), do: nil

  defp aggregate_stats(streams, enabled) do
    stats_list = Enum.map(streams, & &1.stats)

    %{
      enabled: enabled,
      pending_count: sum_stats(stats_list, :pending_count),
      in_flight_count: sum_stats(stats_list, :in_flight_count),
      lockout: any_stats(stats_list, :lockout),
      wait: any_stats(stats_list, :wait),
      retransmit: any_stats(stats_list, :retransmit),
      unlock_pending: any_stats(stats_list, :unlock_pending),
      last_report_value: last_report_value(stats_list),
      streams: streams
    }
  end

  defp sum_stats(stats_list, key) do
    Enum.reduce(stats_list, 0, fn stats, acc -> acc + Map.get(stats, key, 0) end)
  end

  defp any_stats(stats_list, key) do
    Enum.any?(stats_list, fn stats -> Map.get(stats, key, false) end)
  end

  defp last_report_value([stats]), do: Map.get(stats, :last_report_value)
  defp last_report_value(_), do: nil

  defp cache_clcw(%{clcw_by_vcid: clcw_by_vcid} = state, %CLCW{vcid: vcid} = clcw)
       when is_integer(vcid) do
    %{state | clcw_by_vcid: Map.put(clcw_by_vcid, vcid, clcw)}
  end

  defp cache_clcw(state, _clcw), do: state

  defp maybe_apply_cached_clcw(:started, pid, state, vcid) do
    case Map.get(state.clcw_by_vcid, vcid) do
      nil -> :ok
      clcw -> StreamServer.apply_clcw(pid, clcw)
    end
  end

  defp maybe_apply_cached_clcw(:existing, _pid, _state, _vcid), do: :ok
end
