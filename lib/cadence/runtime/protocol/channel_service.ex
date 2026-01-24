defmodule Cadence.Runtime.Protocol.ChannelService do
  @moduledoc """
  Protocol owner for a {mission_id, ChannelId}.

  Owns TM processing, TC framing/segmentation, COP-1 FOP state, and CLCW handling.
  It never owns interface lifecycle; it asks LinkController for active interfaces.

  Note: Simulator framing uses the CCSDS uplink pipeline directly; runtime uplink
  framing lives here in ChannelService.
  """

  use GenServer

  alias Cadence.CCSDS.Core.{PDU, SDUOctets}
  alias Cadence.CCSDS.PDUDispatcher
  alias Cadence.CCSDS.SDLP.TM.FrameCodec, as: TMFrameCodec
  alias Cadence.CCSDS.SDLP.TM.Reassembly, as: TMReassembly
  alias Cadence.CCSDS.SDU.Mapping
  alias Cadence.CCSDS.SDU.Registry, as: SDURegistry
  alias Cadence.Runtime.ChannelId
  alias Cadence.Runtime.Links.LinkController
  alias Cadence.Runtime.Protocol.Supervisor, as: ProtocolSupervisor
  alias Cadence.Runtime.Telemetry.SpacePacketFramer
  alias Cadence.Runtime.Transport
  alias Cadence.Runtime.Transport.COP1.Application, as: COP1Application
  alias Cadence.Runtime.Transport.COP1.Config, as: COP1Config
  alias Cadence.Runtime.Transport.COP1.Context, as: COP1Context
  alias Cadence.Runtime.Transport.COP1.DownlinkHandler
  alias Cadence.Runtime.Uplink.FrameBuilder
  alias Cadence.Telemetry.Packet
  alias Cadence.Time, as: CadenceTime
  alias Cadence.Transport.TCStreamId

  defmodule State do
    @moduledoc false
    defstruct [
      :mission_id,
      :channel_id,
      :frame_buffer,
      :space_packet_framer,
      :reassembly_state,
      tm_state: %{},
      tc_state: %{},
      cop1_state: %{}
    ]
  end

  @registry Cadence.MissionRegistry

  # ---------------------------------------------------------------------------
  # Client API
  # ---------------------------------------------------------------------------

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    mission_id = Keyword.fetch!(opts, :mission_id)
    channel_id = Keyword.fetch!(opts, :channel_id)

    GenServer.start_link(__MODULE__, {mission_id, channel_id},
      name: via_tuple(mission_id, channel_id)
    )
  end

  @spec handle_downlink(String.t(), ChannelId.t(), binary(), map()) :: :ok
  def handle_downlink(mission_id, %ChannelId{} = channel_id, bytes, meta) do
    GenServer.cast(via_tuple(mission_id, channel_id), {:downlink, bytes, meta})
  end

  @spec send_uplink(String.t(), ChannelId.t(), binary() | PDU.t(), map()) ::
          :ok | {:error, term()} | {:defer, term()}
  def send_uplink(mission_id, %ChannelId{} = channel_id, payload, meta \\ %{}) do
    GenServer.call(via_tuple(mission_id, channel_id), {:uplink, payload, meta})
  end

  # ---------------------------------------------------------------------------
  # GenServer Callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init({mission_id, %ChannelId{} = channel_id}) do
    {:ok,
     %State{
       mission_id: mission_id,
       channel_id: channel_id,
       frame_buffer: <<>>,
       space_packet_framer: SpacePacketFramer.new(),
       reassembly_state: nil
     }}
  end

  @impl true
  def handle_cast({:downlink, bytes, meta}, state) do
    interface_id = meta[:interface_id]

    updated =
      case protocol_config(state, interface_id) do
        {:ok, %{sdlp: {:ok, %{mapping: mapping, opts: opts}}} = protocol_config} ->
          ensure_pdu_dispatcher(state, protocol_config)
          ensure_cop1_fop(state, protocol_config)
          handle_sdlp_downlink(state, bytes, meta, mapping, opts, interface_id)

        _ ->
          handle_space_packet_downlink(state, bytes, meta)
      end

    {:noreply, updated}
  end

  @impl true
  def handle_call({:uplink, %PDU{} = pdu, meta}, _from, state) do
    case select_uplink_interface(state, meta) do
      {:ok, interface_id} ->
        case protocol_config(state, interface_id) do
          {:ok, %{sdlp: {:ok, %{opts: opts}}} = protocol_config} ->
            cop1_mode = resolve_cop1_mode(protocol_config, pdu)

            ensure_cop1_fop(state, protocol_config)

            handle_sdlp_uplink(state, pdu, meta, interface_id, opts, cop1_mode)

          {:ok, protocol_config} ->
            cop1_mode = resolve_cop1_mode(protocol_config, pdu)
            handle_non_sdlp_uplink(state, pdu, meta, interface_id, cop1_mode)

          :error ->
            {:reply, {:error, :tc_framing_unavailable}, state}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:uplink, bytes, meta}, _from, state) when is_binary(bytes) do
    case select_uplink_interface(state, meta) do
      {:ok, interface_id} ->
        payload = Map.put(meta, :channel_id, state.channel_id)

        case Transport.send_bytes(state.mission_id, interface_id, bytes, payload) do
          :ok -> {:reply, :ok, state}
          {:error, reason} -> {:reply, {:error, reason}, state}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:uplink, _payload, _meta}, _from, state) do
    {:reply, {:error, :invalid_payload}, state}
  end

  defp via_tuple(mission_id, %ChannelId{} = channel_id) do
    {:via, Registry, {@registry, {:channel_service, mission_id, ChannelId.key(channel_id)}}}
  end

  defp protocol_config(state, interface_id) when is_binary(interface_id) do
    LinkController.protocol_config_for_interface(
      state.mission_id,
      state.channel_id.scid,
      interface_id
    )
  end

  defp protocol_config(_state, _interface_id), do: :error

  defp ensure_pdu_dispatcher(state, protocol_config) do
    ProtocolSupervisor.ensure_pdu_dispatcher(state.mission_id, state.channel_id, protocol_config)
  end

  defp ensure_cop1_fop(state, protocol_config) when is_map(protocol_config) do
    cop1 = Map.get(protocol_config, :cop1, %{})

    if COP1Config.mode(cop1) == :fop do
      ProtocolSupervisor.ensure_cop1_fop(state.mission_id, state.channel_id, protocol_config)
    end
  end

  defp ensure_cop1_fop(_state, _protocol_config), do: :ok

  defp select_uplink_interface(state, meta) do
    requested = Map.get(meta, :interface_id)

    cond do
      is_binary(requested) and binding_active?(state, requested) ->
        {:ok, requested}

      is_binary(requested) ->
        {:error, :no_active_interface}

      not link_controller_running?(state) ->
        {:error, :no_active_interface}

      true ->
        case LinkController.active_uplink_interface(state.mission_id, state.channel_id) do
          nil -> {:error, :no_active_interface}
          interface_id -> {:ok, interface_id}
        end
    end
  end

  defp binding_active?(state, interface_id) do
    link_controller_running?(state) and
      LinkController.binding_active?(
        state.mission_id,
        state.channel_id,
        interface_id,
        :uplink
      )
  end

  defp link_controller_running?(state) do
    Registry.lookup(
      Cadence.MissionRegistry,
      {:link_controller, state.mission_id, state.channel_id.scid}
    ) != []
  end

  defp resolve_cop1_mode(nil, _pdu), do: :bypass

  defp resolve_cop1_mode(protocol_config, %PDU{} = pdu) do
    cop1 = Map.get(protocol_config, :cop1, %{})
    COP1Config.mode_for_config(cop1, pdu.type, apid_from_pdu(pdu))
  end

  defp apid_from_pdu(%PDU{type: :space_packet, value: %{apid: apid}}) when is_integer(apid),
    do: apid

  defp apid_from_pdu(_pdu), do: nil

  defp handle_sdlp_uplink(state, %PDU{} = pdu, meta, interface_id, opts, cop1_mode) do
    case build_tc_frames(state, pdu, meta, interface_id, opts) do
      {:ok, frames, next_state} ->
        case maybe_send_frames(state, next_state, frames, meta, interface_id, cop1_mode) do
          {:ok, final_state} -> {:reply, :ok, final_state}
          {:defer, reason, final_state} -> {:reply, {:defer, reason}, final_state}
          {:error, reason, final_state} -> {:reply, {:error, reason}, final_state}
        end

      {:error, reason, next_state} ->
        {:reply, {:error, reason}, next_state}
    end
  end

  defp handle_non_sdlp_uplink(state, %PDU{} = _pdu, _meta, _interface_id, :fop) do
    {:reply, {:error, :tc_framing_unavailable}, state}
  end

  defp handle_non_sdlp_uplink(state, %PDU{} = pdu, meta, interface_id, _cop1_mode) do
    case encode_pdu_bytes(state, pdu, meta, interface_id) do
      {:ok, bytes} ->
        payload = Map.put(meta, :channel_id, state.channel_id)

        case Transport.send_bytes(state.mission_id, interface_id, bytes, payload) do
          :ok -> {:reply, :ok, state}
          {:error, reason} -> {:reply, {:error, reason}, state}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  defp build_tc_frames(state, %PDU{} = pdu, meta, interface_id, opts) do
    frame_size = opts[:uplink_frame_size] || opts[:frame_size]
    scid = state.channel_id.scid || opts[:uplink_scid]
    vcid = state.channel_id.vcid || opts[:uplink_vcid]
    map_id = state.channel_id.map_id || opts[:uplink_map_id]

    cond do
      not is_integer(frame_size) ->
        {:error, :missing_frame_size, state}

      not is_integer(scid) ->
        {:error, :missing_scid, state}

      not is_integer(vcid) ->
        {:error, :missing_vcid, state}

      true ->
        build_tc_frames_from_opts(state, pdu, meta, interface_id, opts, %{
          frame_size: frame_size,
          scid: scid,
          vcid: vcid,
          map_id: map_id
        })
    end
  end

  defp build_tc_frames_from_opts(state, pdu, meta, interface_id, opts, base_ctx) do
    segmentation = opts[:segmentation] || %{}
    {stream_id, initial_seq} = stream_context(state, meta, interface_id)

    with {:ok, seg_state, next_state} <- ensure_segmentation(state, stream_id, initial_seq),
         {:ok, frames, next_seg} <-
           FrameBuilder.build_frames(
             pdu,
             Map.merge(base_ctx, %{
               bypass_flag: framing_bypass_flag(meta),
               control_command_flag: framing_control_command_flag(meta),
               segment_header_flag: derive_segment_header_flag(meta, segmentation)
             }),
             seg_state
           ) do
      {:ok, frames, put_segmentation(next_state, stream_id, next_seg)}
    else
      {:error, reason} -> {:error, reason, state}
    end
  end

  defp stream_context(state, meta, interface_id) do
    case Map.get(meta, :cop1_context) do
      %COP1Context{stream_id: %TCStreamId{} = stream_id} ->
        {stream_id, Map.get(meta, :initial_seq, 0)}

      _ ->
        stream_id =
          TCStreamId.new_from_channel!(state.mission_id, state.channel_id,
            interface_id: interface_id
          )

        {stream_id, Map.get(meta, :initial_seq, 0)}
    end
  end

  defp ensure_segmentation(%State{} = state, stream_id, initial_seq) do
    case Map.get(state.tc_state, stream_id) do
      nil ->
        case FrameBuilder.init_segmentation(frame_seq: initial_seq) do
          {:ok, seg_state} -> {:ok, seg_state, state}
          {:error, reason} -> {:error, reason}
        end

      seg_state ->
        {:ok, seg_state, state}
    end
  end

  defp put_segmentation(state, stream_id, seg_state) do
    %{state | tc_state: Map.put(state.tc_state, stream_id, seg_state)}
  end

  defp derive_segment_header_flag(meta, segmentation) do
    case Map.get(meta, :segment_header_flag) do
      flag when flag in [0, 1] ->
        flag

      _ ->
        Map.get(segmentation, :segment_header_flag, 1)
    end
  end

  defp framing_bypass_flag(meta) do
    case Map.get(meta, :cop1_context) do
      %COP1Context{} = context ->
        if context.bypass == true, do: 1, else: 0

      _ ->
        case Map.get(meta, :bypass_flag) do
          flag when flag in [0, 1] -> flag
          _ -> 0
        end
    end
  end

  defp framing_control_command_flag(meta) do
    case Map.get(meta, :cop1_context) do
      %COP1Context{} = context ->
        case COP1Context.control_flags(context) do
          %{control_command_flag: flag} -> flag
          _ -> 0
        end

      _ ->
        case Map.get(meta, :control_command_flag) do
          flag when flag in [0, 1] -> flag
          _ -> 0
        end
    end
  end

  defp maybe_send_frames(state, next_state, frames, meta, interface_id, :fop) do
    context = cop1_context(state, meta, interface_id)

    case COP1Application.propose_send_frames(state.mission_id, state.channel_id, frames, context) do
      :ok -> {:ok, next_state}
      {:defer, reason} -> {:defer, reason, next_state}
      {:error, reason} -> {:error, reason, next_state}
    end
  end

  defp maybe_send_frames(state, next_state, frames, meta, interface_id, _mode) do
    payload = Map.put(meta, :channel_id, state.channel_id)

    result =
      Enum.reduce_while(frames, :ok, fn frame, acc ->
        case Transport.send_bytes(state.mission_id, interface_id, frame.bytes, payload) do
          :ok -> {:cont, acc}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)

    case result do
      :ok -> {:ok, next_state}
      {:error, reason} -> {:error, reason, next_state}
    end
  end

  defp cop1_context(state, meta, interface_id) do
    base_context =
      COP1Context.new(
        stream_id:
          TCStreamId.new_from_channel!(state.mission_id, state.channel_id,
            interface_id: interface_id
          ),
        vcid: state.channel_id.vcid
      )

    case Map.get(meta, :cop1_context) do
      %COP1Context{} = context -> COP1Context.merge(base_context, context)
      _ -> base_context
    end
  end

  defp encode_pdu_bytes(state, %PDU{} = pdu, _meta, _interface_id) do
    opts = [
      profile: :tc,
      direction: :uplink,
      scid: state.channel_id.scid,
      vcid: state.channel_id.vcid,
      map_id: state.channel_id.map_id
    ]

    case SDURegistry.fetch(pdu.type) do
      {:ok, codec} ->
        case codec.encode(pdu, opts) do
          {:ok, %SDUOctets{octets: octets}} -> {:ok, octets}
          {:error, reason} -> {:error, reason}
        end

      :error ->
        {:error, :unknown_sdu_type}
    end
  end

  defp handle_sdlp_downlink(state, bytes, meta, %Mapping{} = mapping, opts, interface_id) do
    frame_opts =
      Keyword.take(opts, [:frame_size, :secondary_header_length, :ocf_length, :timestamp])

    buffer = state.frame_buffer <> bytes

    {:ok, frames, rest} = TMFrameCodec.decode(buffer, frame_opts)

    {next_reassembly, next_cop1} =
      deframe_frames(state, frames, meta, mapping, opts, interface_id)

    %{state | frame_buffer: rest, reassembly_state: next_reassembly, cop1_state: next_cop1}
  end

  defp handle_space_packet_downlink(state, bytes, meta) do
    {packet_binaries, framer, _errors} =
      SpacePacketFramer.ingest(state.space_packet_framer, bytes)

    packets =
      packet_binaries
      |> Enum.map(&build_ccsds_packet(&1, meta))
      |> Enum.reject(&is_nil/1)

    Enum.each(packets, fn %Packet{} = packet ->
      Phoenix.PubSub.broadcast(
        Cadence.PubSub,
        "mission:#{state.mission_id}:telemetry:raw",
        {:telemetry_packet, packet, meta}
      )
    end)

    %{state | space_packet_framer: framer}
  end

  defp ensure_reassembly(state, opts) do
    reassembly_state =
      case state.reassembly_state do
        nil ->
          {:ok, new_state} = TMReassembly.init(reassembly_opts(opts))
          new_state

        existing ->
          existing
      end

    {reassembly_state, state.cop1_state}
  end

  defp deframe_frames(state, frames, meta, mapping, opts, interface_id) do
    ctx = %{direction: :downlink}
    {reassembly_state, cop1_state} = ensure_reassembly(state, opts)

    Enum.reduce(frames, {reassembly_state, cop1_state}, fn frame, {acc_state, acc_cop1} ->
      acc_cop1 = maybe_ingest_clcw(state, frame, interface_id, acc_cop1)

      {next_state, acc_cop1} =
        ingest_frame(frame, ctx, acc_state, acc_cop1, state, meta, mapping, interface_id)

      {next_state, acc_cop1}
    end)
  end

  defp ingest_frame(frame, ctx, acc_state, acc_cop1, state, meta, mapping, interface_id) do
    case TMReassembly.ingest(frame, ctx, acc_state) do
      {:ok, sdu_octets, new_state} ->
        dispatch_sdu_octets(state, sdu_octets, meta, mapping, interface_id)
        {new_state, acc_cop1}

      {:error, _reason, new_state} ->
        {new_state, acc_cop1}
    end
  end

  defp reassembly_opts(opts) do
    Keyword.get(opts, :reassembly_opts, opts)
  end

  defp maybe_ingest_clcw(state, %{ocf: ocf, scid: scid, vcid: vcid}, interface_id, cop1_state)
       when is_binary(ocf) and byte_size(ocf) == 4 do
    DownlinkHandler.ingest_tm_ocf(state.mission_id, state.channel_id, ocf, %{
      scid: scid,
      vcid: vcid,
      interface_id: interface_id
    })

    Map.put(cop1_state, :last_clcw, ocf)
  end

  defp maybe_ingest_clcw(_state, _frame, _interface_id, cop1_state), do: cop1_state

  defp dispatch_sdu_octets(state, sdu_octets, meta, mapping, interface_id) do
    Enum.each(sdu_octets, fn %SDUOctets{} = sdu ->
      case decode_sdu_to_pdu(sdu, mapping) do
        {:ok, %PDU{} = pdu} ->
          ctx = %{
            mission_id: state.mission_id,
            channel_id: state.channel_id,
            interface_id: interface_id,
            scid: state.channel_id.scid,
            vcid: state.channel_id.vcid,
            base_meta: meta,
            sdu: sdu
          }

          PDUDispatcher.ingest(dispatcher_name(state.mission_id, state.channel_id), pdu, ctx)

        _ ->
          :ok
      end
    end)
  end

  defp decode_sdu_to_pdu(%SDUOctets{} = sdu, %Mapping{} = mapping) do
    with {:ok, sdu_type} <-
           Mapping.fetch(mapping, sdu.scid, sdu.vcid, sdu.map_id, sdu.direction),
         {:ok, codec} <- SDURegistry.fetch(sdu_type) do
      case codec.decode(sdu, []) do
        {:ok, %PDU{value: :idle}} -> {:skip, :idle}
        {:ok, %PDU{} = pdu} -> {:ok, pdu}
        {:error, reason} -> {:error, reason}
      end
    else
      _ -> {:error, :decode_failed}
    end
  end

  defp dispatcher_name(mission_id, channel_id) do
    PDUDispatcher.via_tuple(mission_id, channel_id)
  end

  defp build_ccsds_packet(binary, metadata) do
    metadata =
      metadata
      |> Map.put_new(:mission_id, metadata[:mission_id] || metadata["mission_id"])
      |> Map.put_new(:received_at, CadenceTime.now())

    case Packet.from_ccsds(binary, metadata) do
      {:ok, packet} -> packet
      {:error, _reason} -> nil
    end
  end
end
