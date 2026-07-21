defmodule CadenceSimulator.COP1.LoopbackPeer do
  @moduledoc """
  TCP-connected simulator peer for COP-1 loopback.

  It receives framed TC uplink bytes from a Cadence TCP provider, decodes TC
  transfer frames up to the managed maximum size, reassembles MAP SDUs, and
  responds on the same socket with encoded CLCW reports.
  """

  use GenServer

  require Logger

  alias Cadence.CCSDS.Core.LinkFrame
  alias Cadence.CCSDS.SpacePacket
  alias Cadence.CCSDS.SpacePacket.Codec, as: SpacePacketCodec
  alias Cadence.CCSDS.TC.{FrameCodec, Reassembly}
  alias Cadence.CCSDS.Transport.COP1.{CLCW, FARM}
  alias CadenceSimulator.COP1.CLCWInjector

  @tcp_opts [:binary, packet: 0, active: false, nodelay: true]
  @default_reconnect_interval_ms 250

  defstruct [
    :host,
    :port,
    :tc_frame_size,
    :fecf,
    :runtime_resolver,
    :socket,
    :reconnect_interval_ms,
    :connect_timer_ref,
    :clcw_injector,
    :command_target,
    :segment_header_flag,
    :segment_header_by_vcid,
    :tc_reassembly,
    :farm_config,
    farm_by_vcid: %{},
    receive_buffer: <<>>,
    tc_frame_count: 0,
    farm_accept_count: 0,
    farm_discard_count: 0,
    clcw_count: 0,
    command_count: 0,
    command_error_count: 0,
    last_command: nil,
    last_command_error: nil,
    last_tc_frame_seq: nil,
    last_farm_event: nil,
    last_farm_state: nil,
    last_clcw_report_value: nil,
    last_error: nil
  ]

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    case Keyword.get(opts, :name) do
      nil -> GenServer.start_link(__MODULE__, opts)
      name -> GenServer.start_link(__MODULE__, opts, name: name)
    end
  end

  @spec stop(GenServer.server()) :: :ok
  def stop(server), do: GenServer.stop(server)

  @spec snapshot(GenServer.server()) :: map()
  def snapshot(server), do: GenServer.call(server, :snapshot)

  @impl true
  def init(opts) do
    with {:ok, tc_reassembly} <-
           Reassembly.init(max_sdu_octets: Keyword.get(opts, :max_command_sdu_octets, 1_048_576)),
         {:ok, farm_config} <- build_farm_config(opts) do
      state = %__MODULE__{
        host: Keyword.get(opts, :host, "127.0.0.1"),
        port: Keyword.fetch!(opts, :port),
        tc_frame_size: Keyword.fetch!(opts, :tc_frame_size),
        fecf: Keyword.get(opts, :fecf, false),
        runtime_resolver: Keyword.get(opts, :runtime_resolver),
        reconnect_interval_ms:
          Keyword.get(opts, :reconnect_interval_ms, @default_reconnect_interval_ms),
        clcw_injector: build_clcw_injector(opts),
        command_target: Keyword.get(opts, :command_target),
        segment_header_flag: Keyword.get(opts, :segment_header_flag, 0),
        segment_header_by_vcid: Keyword.get(opts, :segment_header_by_vcid, %{}),
        tc_reassembly: tc_reassembly,
        farm_config: farm_config
      }

      {:ok, connect_or_schedule(state)}
    else
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_call(:snapshot, _from, state) do
    {:reply,
     %{
       host: state.host,
       port: state.port,
       connected?: is_port(state.socket),
       tc_frame_size: state.tc_frame_size,
       fecf: state.fecf,
       tc_frame_count: state.tc_frame_count,
       farm_accept_count: state.farm_accept_count,
       farm_discard_count: state.farm_discard_count,
       farm_states: farm_snapshots(state.farm_by_vcid),
       clcw_count: state.clcw_count,
       command_count: state.command_count,
       command_error_count: state.command_error_count,
       last_command: state.last_command,
       last_command_error: state.last_command_error,
       reassembly_buffer_count: map_size(state.tc_reassembly.buffers),
       last_tc_frame_seq: state.last_tc_frame_seq,
       last_farm_event: state.last_farm_event,
       last_farm_state: state.last_farm_state,
       last_clcw_report_value: state.last_clcw_report_value,
       last_error: state.last_error
     }, state}
  end

  @impl true
  def handle_info(:connect, state) do
    {:noreply, %{state | connect_timer_ref: nil} |> connect_or_schedule()}
  end

  def handle_info({:tcp, socket, data}, %{socket: socket} = state) when is_binary(data) do
    next_state =
      state
      |> process_inbound_data(data)
      |> reactivate_socket()

    {:noreply, next_state}
  end

  def handle_info({:tcp_closed, socket}, %{socket: socket} = state) do
    Logger.warning("COP-1 loopback socket closed")

    {:noreply,
     state
     |> reset_connection_state()
     |> schedule_reconnect()}
  end

  def handle_info({:tcp_error, socket, reason}, %{socket: socket} = state) do
    Logger.warning("COP-1 loopback socket error: #{inspect(reason)}")

    {:noreply,
     schedule_reconnect(%{
       reset_connection_state(state)
       | socket: nil,
         last_error: inspect(reason)
     })}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    cancel_reconnect(state.connect_timer_ref)

    if is_port(state.socket) do
      :gen_tcp.close(state.socket)
    end

    :ok
  end

  defp connect_or_schedule(state) do
    state = maybe_refresh_runtime(state)

    case :gen_tcp.connect(String.to_charlist(state.host), state.port, @tcp_opts) do
      {:ok, socket} ->
        :ok = :inet.setopts(socket, active: :once)
        %{state | socket: socket, last_error: nil}

      {:error, reason} ->
        Logger.warning(
          "COP-1 loopback failed to connect to #{state.host}:#{state.port}: #{inspect(reason)}"
        )

        schedule_reconnect(%{state | last_error: inspect(reason)})
    end
  end

  defp schedule_reconnect(%{connect_timer_ref: nil} = state) do
    %{
      state
      | connect_timer_ref: Process.send_after(self(), :connect, state.reconnect_interval_ms)
    }
  end

  defp schedule_reconnect(state), do: state

  defp cancel_reconnect(nil), do: :ok

  defp cancel_reconnect(timer_ref) do
    Process.cancel_timer(timer_ref)
    :ok
  end

  defp process_inbound_data(state, data) do
    buffer = state.receive_buffer <> data

    case FrameCodec.decode(
           buffer,
           frame_size: state.tc_frame_size,
           fecf: state.fecf,
           segment_header_flag: state.segment_header_flag,
           segment_header_by_vcid: state.segment_header_by_vcid
         ) do
      {:ok, frames, rest} ->
        frames
        |> Enum.reduce(%{state | receive_buffer: rest}, &handle_tc_frame/2)
        |> Map.put(:receive_buffer, rest)

      {:error, reason} ->
        Logger.warning("COP-1 loopback failed to decode TC frames: #{inspect(reason)}")
        %{state | receive_buffer: buffer, last_error: inspect(reason)}
    end
  end

  defp handle_tc_frame(%LinkFrame{} = frame, state) do
    with {:ok, farm} <- farm_for_frame(state, frame),
         {:ok, transition} <- FARM.process_frame(farm, frame) do
      state = apply_farm_transition(state, frame, transition)

      clcw =
        transition.state
        |> FARM.clcw()
        |> maybe_apply_injector(state.clcw_injector, state.tc_frame_count)

      with {:ok, clcw_binary} <- CLCW.encode(clcw),
           :ok <- :gen_tcp.send(state.socket, clcw_binary) do
        %{
          state
          | tc_frame_count: state.tc_frame_count + 1,
            clcw_count: state.clcw_count + 1,
            last_tc_frame_seq: frame.frame_seq,
            last_clcw_report_value: clcw.report_value,
            last_error: nil
        }
      else
        {:error, reason} ->
          Logger.warning("COP-1 loopback failed to send CLCW: #{inspect(reason)}")
          %{state | last_error: inspect(reason)}
      end
    else
      {:error, reason} ->
        Logger.warning(
          "COP-1 loopback failed to process TC frame with FARM-1: #{inspect(reason)}"
        )

        %{state | last_error: inspect(reason)}
    end
  end

  defp reactivate_socket(%{socket: socket} = state) when is_port(socket) do
    :ok = :inet.setopts(socket, active: :once)
    state
  end

  defp reactivate_socket(state), do: state

  defp build_clcw_injector(opts) do
    injector_opts = [
      overrides: Keyword.get(opts, :clcw_overrides, %{}),
      schedule: Keyword.get(opts, :clcw_schedule, [])
    ]

    if injector_opts[:overrides] == %{} and injector_opts[:schedule] == [] do
      nil
    else
      CLCWInjector.new(injector_opts)
    end
  end

  defp maybe_apply_injector(%CLCW{} = clcw, %CLCWInjector{} = injector, step) do
    CLCWInjector.apply(injector, clcw, step)
  end

  defp maybe_apply_injector(%CLCW{} = clcw, _injector, _step), do: clcw

  defp build_farm_config(opts) do
    farm_config = %{
      receiver_frame_sequence_number: Keyword.get(opts, :farm_initial_vr, 0),
      positive_window_width: Keyword.get(opts, :farm_positive_window_width, 127),
      negative_window_width: Keyword.get(opts, :farm_negative_window_width, 127),
      retransmission_allowed: Keyword.get(opts, :farm_retransmission_allowed, true)
    }

    case FARM.new(Map.put(farm_config, :vcid, 0)) do
      {:ok, _farm} -> {:ok, farm_config}
      {:error, reason} -> {:error, {:invalid_farm_config, reason}}
    end
  end

  defp farm_for_frame(state, %LinkFrame{vcid: vcid}) do
    case Map.fetch(state.farm_by_vcid, vcid) do
      {:ok, farm} -> {:ok, farm}
      :error -> FARM.new(Map.put(state.farm_config, :vcid, vcid))
    end
  end

  defp apply_farm_transition(state, frame, transition) do
    state = %{
      state
      | farm_by_vcid: Map.put(state.farm_by_vcid, frame.vcid, transition.state),
        last_farm_event: transition.event,
        last_farm_state: transition.state.state
    }

    state =
      case transition.disposition do
        :accept -> %{state | farm_accept_count: state.farm_accept_count + 1}
        :discard -> %{state | farm_discard_count: state.farm_discard_count + 1}
        _other -> state
      end

    if transition.deliver? do
      maybe_execute_command(frame, state)
    else
      state
    end
  end

  defp farm_snapshots(farm_by_vcid) do
    Map.new(farm_by_vcid, fn {vcid, farm} ->
      {vcid,
       %{
         state: farm.state,
         receiver_frame_sequence_number: farm.receiver_frame_sequence_number,
         retransmit: farm.retransmit,
         farm_b_counter: farm.farm_b_counter,
         positive_window_width: farm.positive_window_width,
         negative_window_width: farm.negative_window_width
       }}
    end)
  end

  defp maybe_execute_command(
         %LinkFrame{} = frame,
         %{command_target: command_target} = state
       )
       when not is_nil(command_target) do
    if Map.get(frame.meta, :control_command_flag, 0) == 0 do
      ingest_command_frame(frame, state)
    else
      state
    end
  end

  defp maybe_execute_command(%LinkFrame{}, state), do: state

  defp ingest_command_frame(%LinkFrame{} = frame, state) do
    case Reassembly.ingest(
           frame,
           %{direction: :uplink, sdu_kind_hint: :command},
           state.tc_reassembly
         ) do
      {:ok, sdus, reassembly_state} ->
        Enum.reduce(sdus, %{state | tc_reassembly: reassembly_state}, &execute_command_sdu/2)

      {:error, reason, reassembly_state} ->
        %{
          state
          | tc_reassembly: reassembly_state,
            command_error_count: state.command_error_count + 1,
            last_command_error: inspect(reason)
        }
    end
  end

  defp execute_command_sdu(sdu, %{command_target: command_target} = state) do
    with {:ok, command_payload} <- command_application_data(sdu.octets),
         {:ok, command_result} <-
           CadenceSimulator.execute_encoded_command(command_target, command_payload) do
      %{
        state
        | command_count: state.command_count + 1,
          last_command: command_result,
          last_command_error: nil
      }
    else
      {:error, reason} ->
        %{
          state
          | command_error_count: state.command_error_count + 1,
            last_command_error: inspect(reason)
        }
    end
  catch
    :exit, reason ->
      %{
        state
        | command_error_count: state.command_error_count + 1,
          last_command_error: inspect(reason)
      }
  end

  defp command_application_data(packet_octets) do
    case SpacePacketCodec.decode(packet_octets) do
      {:ok, %SpacePacket{packet_type: :command, data: data}} ->
        {:ok, data}

      {:ok, %SpacePacket{packet_type: packet_type}} ->
        {:error, {:unexpected_command_packet_type, packet_type}}

      {:error, reason} ->
        {:error, {:invalid_command_space_packet, reason}}
    end
  end

  defp reset_connection_state(state) do
    %{
      state
      | socket: nil,
        receive_buffer: <<>>,
        tc_reassembly: %{state.tc_reassembly | buffers: %{}}
    }
  end

  defp maybe_refresh_runtime(%{runtime_resolver: nil} = state), do: state

  defp maybe_refresh_runtime(state) do
    case resolve_runtime_updates(state.runtime_resolver) do
      {:ok, runtime_updates} ->
        refreshed_state =
          state
          |> maybe_put_runtime_value(:host, runtime_updates)
          |> maybe_put_runtime_value(:port, runtime_updates)
          |> maybe_put_runtime_value(:tc_frame_size, runtime_updates)
          |> maybe_put_runtime_value(:segment_header_flag, runtime_updates)
          |> maybe_put_runtime_value(:fecf, runtime_updates)
          |> maybe_put_farm_initial_vr(runtime_updates)
          |> maybe_reset_reassembly_for_runtime_change(state)

        maybe_log_runtime_refresh(state, refreshed_state)
        refreshed_state

      {:error, reason} ->
        Logger.warning("COP-1 loopback failed to refresh runtime output: #{inspect(reason)}")
        state
    end
  end

  defp maybe_put_runtime_value(state, key, runtime_updates) do
    case Keyword.fetch(runtime_updates, key) do
      {:ok, value} -> Map.put(state, key, value)
      :error -> state
    end
  end

  defp maybe_put_farm_initial_vr(state, runtime_updates) do
    case Keyword.fetch(runtime_updates, :farm_initial_vr) do
      {:ok, receiver_frame_sequence_number} ->
        put_in(state.farm_config.receiver_frame_sequence_number, receiver_frame_sequence_number)

      :error ->
        state
    end
  end

  defp maybe_log_runtime_refresh(previous_state, refreshed_state) do
    previous_runtime =
      {
        previous_state.host,
        previous_state.port,
        previous_state.tc_frame_size,
        previous_state.segment_header_flag,
        previous_state.fecf
      }

    refreshed_runtime =
      {
        refreshed_state.host,
        refreshed_state.port,
        refreshed_state.tc_frame_size,
        refreshed_state.segment_header_flag,
        refreshed_state.fecf
      }

    if refreshed_runtime != previous_runtime do
      Logger.info(
        "COP-1 loopback refreshed runtime from #{format_runtime(previous_runtime)} to #{format_runtime(refreshed_runtime)}"
      )
    end
  end

  defp maybe_reset_reassembly_for_runtime_change(refreshed_state, previous_state) do
    if refreshed_state.tc_frame_size != previous_state.tc_frame_size or
         refreshed_state.segment_header_flag != previous_state.segment_header_flag or
         refreshed_state.fecf != previous_state.fecf do
      %{refreshed_state | tc_reassembly: %{refreshed_state.tc_reassembly | buffers: %{}}}
    else
      refreshed_state
    end
  end

  defp format_runtime({host, port, tc_frame_size, segment_header_flag, fecf?}) do
    "#{host}:#{port} tc_frame_size=#{tc_frame_size} segment_header_flag=#{segment_header_flag} fecf=#{fecf?}"
  end

  defp resolve_runtime_updates({module, function, args})
       when is_atom(module) and is_atom(function) and is_list(args) do
    apply(module, function, args)
  end
end
