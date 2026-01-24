defmodule Cadence.Runtime.Uplink.TCFraming do
  @moduledoc """
  TC framing pipeline with segmentation state per interface.
  """

  use GenServer

  alias Cadence.CCSDS.Core.PDU
  alias Cadence.Domain.Interfaces.Entities.Interface
  alias Cadence.Runtime.Interfaces.SDLPConfig
  alias Cadence.Runtime.Uplink.FrameBuilder
  alias Cadence.Runtime.Uplink.FramingContext

  defmodule State do
    @moduledoc false
    defstruct [
      :mission_id,
      :interface_id,
      :uplink_opts,
      :segmentation_config,
      sdlp?: false,
      segmentations: %{}
    ]
  end

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    interface = Keyword.fetch!(opts, :interface)
    name = via_tuple(interface.mission_id, interface.id)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def via_tuple(mission_id, interface_id) do
    {:via, Registry, {Cadence.MissionRegistry, {:tc_framing, mission_id, interface_id}}}
  end

  @spec build_frames(String.t(), String.t(), PDU.t(), FramingContext.t() | nil) ::
          {:ok, [map()]} | {:error, term()}
  def build_frames(mission_id, interface_id, %PDU{} = pdu, context \\ nil) do
    GenServer.call(via_tuple(mission_id, interface_id), {:build_frames, pdu, context})
  end

  @spec reset(String.t(), String.t()) :: :ok
  def reset(mission_id, interface_id) do
    GenServer.cast(via_tuple(mission_id, interface_id), :reset)
  end

  @impl true
  def init(opts) do
    interface = Keyword.fetch!(opts, :interface)
    {sdlp?, uplink_opts, segmentation_config} = init_uplink_opts(interface)

    {:ok,
     %State{
       mission_id: interface.mission_id,
       interface_id: interface.id,
       sdlp?: sdlp?,
       uplink_opts: uplink_opts,
       segmentation_config: segmentation_config
     }}
  end

  @impl true
  def handle_call({:build_frames, %PDU{} = pdu, context}, _from, %State{sdlp?: true} = state) do
    context = ensure_context(context)
    {stream_id, initial_seq} = stream_context(context)

    with {:ok, seg_state, state} <- ensure_segmentation(state, stream_id, initial_seq),
         {:ok, frames, next_seg_state} <- build_tc_frames(pdu, context, seg_state, state) do
      state = put_segmentation(state, stream_id, next_seg_state)
      {:reply, {:ok, frames}, state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:build_frames, %PDU{}, _context}, _from, state) do
    {:reply, {:error, :tc_framing_unavailable}, state}
  end

  def handle_call({:build_frames, _payload, _context}, _from, state) do
    {:reply, {:error, :invalid_payload}, state}
  end

  @impl true
  def handle_cast(:reset, %State{sdlp?: true} = state) do
    {:noreply, %{state | segmentations: %{}}}
  end

  def handle_cast(:reset, state), do: {:noreply, state}

  defp init_uplink_opts(%Interface{} = interface) do
    case SDLPConfig.fetch(interface) do
      {:ok, %{opts: opts}} ->
        segmentation_config = Keyword.get(opts, :segmentation, %{})
        {true, build_uplink_opts(opts), segmentation_config}

      :error ->
        {false, nil, %{}}
    end
  end

  defp build_tc_frames(%PDU{} = pdu, %FramingContext{} = context, seg_state, %State{} = state) do
    context = FramingContext.with_defaults(context, state.uplink_opts)

    frame_size = context.frame_size
    scid = context.scid
    vcid = context.vcid

    cond do
      not is_integer(frame_size) ->
        {:error, :missing_frame_size}

      not is_integer(scid) ->
        {:error, :missing_scid}

      not is_integer(vcid) ->
        {:error, :missing_vcid}

      true ->
        # Derive segment_header_flag from segmentation config, with context override for
        # emergency bypass scenarios
        segment_header_flag = derive_segment_header_flag(context, state.segmentation_config)

        # bypass_flag can be overridden per-issuance for emergency scenarios
        bypass_flag = FramingContext.normalize_flag(context.bypass_flag, 0)

        # control_command_flag is typically 0 for normal commands
        control_command_flag = FramingContext.normalize_flag(context.control_command_flag, 0)

        builder_ctx = %{
          frame_size: frame_size,
          scid: scid,
          vcid: vcid,
          map_id: context.map_id,
          bypass_flag: bypass_flag,
          control_command_flag: control_command_flag,
          segment_header_flag: segment_header_flag
        }

        FrameBuilder.build_frames(pdu, builder_ctx, seg_state)
    end
  end

  # Derives segment_header_flag from segmentation config.
  # Context can override for emergency scenarios, but normally we derive from config.
  defp derive_segment_header_flag(%FramingContext{} = context, segmentation_config) do
    # If context explicitly sets segment_header_flag, use it (emergency override)
    case context.segment_header_flag do
      flag when flag in [0, 1] ->
        flag

      _ ->
        # Otherwise derive from segmentation config
        Map.get(segmentation_config, :segment_header_flag, 1)
    end
  end

  defp build_uplink_opts(nil), do: nil

  defp build_uplink_opts(opts) do
    profile = opts[:uplink_profile] || opts[:profile]
    Keyword.put(opts, :profile, profile)
  end

  defp stream_context(%FramingContext{} = context) do
    stream_id = context.stream_id || :default
    initial_seq = context.initial_seq || 0
    {stream_id, initial_seq}
  end

  defp stream_context(_context), do: {:default, 0}

  defp ensure_context(nil), do: FramingContext.new()
  defp ensure_context(%FramingContext{} = context), do: context

  defp ensure_segmentation(%State{} = state, stream_id, initial_seq) do
    case Map.get(state.segmentations, stream_id) do
      nil ->
        case FrameBuilder.init_segmentation(frame_seq: initial_seq) do
          {:ok, seg_state} -> {:ok, seg_state, state}
          {:error, reason} -> {:error, reason}
        end

      seg_state ->
        {:ok, seg_state, state}
    end
  end

  defp put_segmentation(%State{} = state, stream_id, seg_state) do
    %{state | segmentations: Map.put(state.segmentations, stream_id, seg_state)}
  end
end
