defmodule Cadence.Runtime.Telemetry.DownlinkPipeline do
  @moduledoc """
  Downlink processing pipeline decoupled from transport interfaces.
  """

  use GenServer
  require Logger

  alias Cadence.CCSDS.Metrics
  alias Cadence.Domain.Interfaces.Entities.Interface
  alias Cadence.Runtime.Interfaces.SDLPConfig
  alias Cadence.Runtime.Telemetry.DeframeSupervisor
  alias Cadence.Runtime.Telemetry.SpacePacketFramer
  alias Cadence.Runtime.Transport.COP1.Application, as: COP1Application
  alias Cadence.Runtime.Transport.COP1.DownlinkHandler
  alias Cadence.Telemetry.Packet
  alias Cadence.Time, as: CadenceTime

  defmodule ConnectionState do
    @moduledoc false
    defstruct [
      :frame_buffer,
      :space_packet_framer
    ]
  end

  def start_link(opts) do
    interface = Keyword.fetch!(opts, :interface)
    name = via_tuple(interface.mission_id, interface.id)
    GenServer.start_link(__MODULE__, interface, name: name)
  end

  def via_tuple(mission_id, interface_id) do
    {:via, Registry, {Cadence.MissionRegistry, {:downlink_pipeline, mission_id, interface_id}}}
  end

  def ingest(mission_id, interface_id, connection_id, data, metadata \\ %{}) do
    GenServer.cast(via_tuple(mission_id, interface_id), {:ingest, connection_id, data, metadata})
  end

  def reset_connection(mission_id, interface_id, connection_id) do
    GenServer.cast(via_tuple(mission_id, interface_id), {:reset_connection, connection_id})
  end

  def drop_connection(mission_id, interface_id, connection_id) do
    GenServer.cast(via_tuple(mission_id, interface_id), {:drop_connection, connection_id})
  end

  @impl true
  def init(%Interface{} = interface) do
    sdlp_config = SDLPConfig.fetch(interface)
    cop1_enabled = COP1Application.enabled?(interface)

    state = %{
      interface: interface,
      mission_id: interface.mission_id,
      interface_id: interface.id,
      sdlp_config: sdlp_config,
      cop1_enabled: cop1_enabled,
      connections: %{}
    }

    {:ok, state}
  end

  @impl true
  def terminate(_reason, _state) do
    :ok
  end

  @impl true
  def handle_cast({:ingest, connection_id, data, metadata}, state) when is_binary(data) do
    base_meta = build_base_metadata(metadata, state)

    case state.sdlp_config do
      {:ok, %{mapping: mapping, opts: opts}} ->
        state = handle_sdlp_data(state, connection_id, data, base_meta, mapping, opts)
        {:noreply, state}

      :error ->
        state = handle_space_packet_data(state, connection_id, data, base_meta)
        {:noreply, state}
    end
  end

  def handle_cast({:reset_connection, connection_id}, state) do
    updated =
      update_connection(state, connection_id, fn _conn ->
        %ConnectionState{frame_buffer: <<>>, space_packet_framer: SpacePacketFramer.new()}
      end)

    {:noreply, updated}
  end

  def handle_cast({:drop_connection, connection_id}, state) do
    {:noreply, %{state | connections: Map.delete(state.connections, connection_id)}}
  end

  defp handle_sdlp_data(state, connection_id, data, base_meta, mapping, opts) do
    profile = Keyword.fetch!(opts, :profile)
    frame_codec = frame_codec_for(profile)

    frame_opts =
      Keyword.take(opts, [:frame_size, :secondary_header_length, :ocf_length, :timestamp])

    connection_state =
      Map.get(state.connections, connection_id, %ConnectionState{frame_buffer: <<>>})

    buffer = connection_state.frame_buffer <> data

    case frame_codec.decode(buffer, frame_opts) do
      {:ok, frames, rest} ->
        ctx = %{direction: :downlink}

        Metrics.inc(
          state.mission_id,
          state.interface_id,
          profile,
          :frames_decoded,
          length(frames)
        )

        Enum.each(frames, fn frame ->
          maybe_ingest_clcw(state, frame)
          dispatch_frame(state, connection_id, frame, ctx, base_meta, mapping, opts)
        end)

        update_connection(state, connection_id, fn conn ->
          %{conn | frame_buffer: rest}
        end)

      {:error, reason} ->
        Metrics.inc(state.mission_id, state.interface_id, profile, :frame_decode_errors, 1)

        Logger.warning(
          "Downlink pipeline frame decode error for interface=#{state.interface_id}: #{inspect(reason)}"
        )

        update_connection(state, connection_id, fn conn -> conn end)
    end
  end

  defp handle_space_packet_data(state, connection_id, data, base_meta) do
    connection_state =
      Map.get(
        state.connections,
        connection_id,
        %ConnectionState{space_packet_framer: SpacePacketFramer.new()}
      )

    {packet_binaries, framer, errors} =
      SpacePacketFramer.ingest(connection_state.space_packet_framer, data)

    Enum.each(errors, fn reason ->
      Logger.warning(
        "Space packet framing error for interface=#{state.interface_id}: #{inspect(reason)}"
      )
    end)

    packets =
      packet_binaries
      |> Enum.map(&build_ccsds_packet(&1, base_meta))
      |> Enum.reject(&is_nil/1)

    Enum.each(packets, fn %Packet{} = packet ->
      Phoenix.PubSub.broadcast(
        Cadence.PubSub,
        "mission:#{state.mission_id}:telemetry:raw",
        {:telemetry_packet, packet, base_meta}
      )
    end)

    notify_interface(length(packets), connection_id, state)

    update_connection(state, connection_id, fn conn ->
      %{conn | space_packet_framer: framer}
    end)
  end

  defp dispatch_frame(state, connection_id, frame, ctx, base_meta, mapping, opts) do
    profile = Keyword.fetch!(opts, :profile)

    worker_started =
      case DeframeSupervisor.start_worker(
             state.mission_id,
             state.interface_id,
             connection_id,
             profile,
             frame.scid,
             frame.vcid,
             mapping: mapping,
             opts: opts,
             reassembly_opts: opts
           ) do
        {:ok, _pid} ->
          true

        {:error, {:already_started, _pid}} ->
          true

        {:error, reason} ->
          Logger.warning(
            "Failed to start deframe worker scid=#{frame.scid} vcid=#{frame.vcid} for interface=#{state.interface_id}: #{inspect(reason)}"
          )

          false
      end

    if worker_started do
      worker_name =
        DeframeSupervisor.worker_name(
          state.mission_id,
          state.interface_id,
          connection_id,
          profile,
          frame.scid,
          frame.vcid
        )

      GenServer.cast(worker_name, {:ingest_frame, frame, ctx, base_meta})
    end
  end

  defp update_connection(state, connection_id, fun) do
    updated =
      state.connections
      |> Map.update(connection_id, fun.(%ConnectionState{}), fun)

    %{state | connections: updated}
  end

  defp build_ccsds_packet(binary, metadata) do
    case Packet.from_ccsds(binary, metadata) do
      {:ok, packet} ->
        packet

      {:error, reason} ->
        Logger.error(
          "Failed to parse CCSDS packet for target=#{metadata.target_id}: #{inspect(reason)}"
        )

        nil
    end
  end

  defp frame_codec_for(:tm), do: Cadence.CCSDS.SDLP.TM.FrameCodec
  defp frame_codec_for(:aos), do: Cadence.CCSDS.SDLP.AOS.FrameCodec
  defp frame_codec_for(:uslp), do: Cadence.CCSDS.SDLP.USLP.FrameCodec

  defp notify_interface(0, _connection_id, _state), do: :ok

  defp notify_interface(count, connection_id, state) do
    GenServer.cast(interface_name(state), {:downlink_packets, connection_id, count})
  end

  defp interface_name(state) do
    {:via, Registry,
     {Cadence.MissionRegistry, {:interface, state.mission_id, state.interface_id}}}
  end

  defp build_base_metadata(metadata, state) do
    metadata
    |> Map.put_new(:mission_id, state.mission_id)
    |> Map.put_new(:interface_id, state.interface_id)
    |> Map.put_new(:received_at, CadenceTime.now())
    |> Map.put_new(:stored, false)
  end

  defp maybe_ingest_clcw(
         %{cop1_enabled: true} = state,
         %{profile: :tm, ocf: ocf, scid: scid, vcid: vcid}
       )
       when is_binary(ocf) and byte_size(ocf) == 4 do
    DownlinkHandler.ingest_tm_ocf(state.mission_id, state.interface_id, ocf, %{
      scid: scid,
      vcid: vcid
    })
  end

  defp maybe_ingest_clcw(_state, _frame), do: :ok
end
