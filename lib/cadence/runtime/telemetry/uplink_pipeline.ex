defmodule Cadence.Runtime.Telemetry.UplinkPipeline do
  @moduledoc """
  Uplink processing pipeline decoupled from transport interfaces.
  """

  use GenServer
  require Logger

  alias Cadence.CCSDS.Core.SDUOctets
  alias Cadence.CCSDS.Uplink.Pipeline
  alias Cadence.Domain.Interfaces.Entities.Interface
  alias Cadence.Runtime.Interfaces.SDLPConfig

  defmodule State do
    @moduledoc false
    defstruct [
      :mission_id,
      :interface_id,
      :uplink_pipeline,
      :uplink_opts,
      sdlp?: false
    ]
  end

  def start_link(opts) do
    interface = Keyword.fetch!(opts, :interface)
    name = via_tuple(interface.mission_id, interface.id)
    GenServer.start_link(__MODULE__, interface, name: name)
  end

  def via_tuple(mission_id, interface_id) do
    {:via, Registry, {Cadence.MissionRegistry, {:uplink_pipeline, mission_id, interface_id}}}
  end

  def encode(mission_id, interface_id, data) when is_binary(data) do
    GenServer.call(via_tuple(mission_id, interface_id), {:encode, data})
  end

  def reset(mission_id, interface_id) do
    GenServer.cast(via_tuple(mission_id, interface_id), :reset)
  end

  @impl true
  def init(%Interface{} = interface) do
    {sdlp?, uplink_pipeline, uplink_opts} = init_uplink_pipeline(interface)

    {:ok,
     %State{
       mission_id: interface.mission_id,
       interface_id: interface.id,
       sdlp?: sdlp?,
       uplink_pipeline: uplink_pipeline,
       uplink_opts: uplink_opts
     }}
  end

  @impl true
  def handle_call({:encode, data}, _from, %State{sdlp?: true} = state) do
    case encode_sdlp(data, state) do
      {:ok, encoded, updated_state} -> {:reply, {:ok, encoded}, updated_state}
      {:error, reason, updated_state} -> {:reply, {:error, reason}, updated_state}
    end
  end

  def handle_call({:encode, data}, _from, %State{sdlp?: false} = state) do
    {:reply, {:ok, data}, state}
  end

  @impl true
  def handle_cast(:reset, %State{sdlp?: true, uplink_opts: opts} = state) do
    case Pipeline.init(opts) do
      {:ok, pipeline} ->
        {:noreply, %{state | uplink_pipeline: pipeline}}

      {:error, reason} ->
        Logger.warning(
          "Failed to reset uplink pipeline for interface=#{state.interface_id}: #{inspect(reason)}"
        )

        {:noreply, %{state | uplink_pipeline: nil}}
    end
  end

  def handle_cast(:reset, state), do: {:noreply, state}

  defp init_uplink_pipeline(%Interface{} = interface) do
    case SDLPConfig.fetch(interface) do
      {:ok, %{opts: opts}} ->
        case Pipeline.init(opts) do
          {:ok, pipeline} -> {true, pipeline, opts}
          {:error, _} -> {true, nil, opts}
        end

      :error ->
        {false, nil, nil}
    end
  end

  defp encode_sdlp(_data, %State{uplink_pipeline: nil} = state) do
    {:error, :uplink_pipeline_unavailable, state}
  end

  defp encode_sdlp(data, %State{} = state) do
    ctx = uplink_ctx(state.uplink_opts)

    sdu = %SDUOctets{
      profile: state.uplink_opts[:profile],
      scid: ctx[:scid],
      vcid: ctx[:vcid],
      map_id: ctx[:map_id],
      direction: :uplink,
      sdu_kind_hint: :space_packet,
      octets: data,
      quality: :good,
      source_frames: [],
      timestamp: nil,
      meta: %{}
    }

    case Pipeline.encode(sdu, ctx, state.uplink_pipeline, state.uplink_opts) do
      {:ok, encoded, new_pipeline} ->
        {:ok, encoded, %{state | uplink_pipeline: new_pipeline}}

      {:error, reason, new_pipeline} ->
        {:error, reason, %{state | uplink_pipeline: new_pipeline}}
    end
  end

  defp uplink_ctx(opts) do
    %{
      frame_size: opts[:frame_size],
      scid: opts[:uplink_scid] || opts[:scid],
      vcid: opts[:uplink_vcid] || opts[:vcid],
      map_id: opts[:uplink_map_id]
    }
  end
end
