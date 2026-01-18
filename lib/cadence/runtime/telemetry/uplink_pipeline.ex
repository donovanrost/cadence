defmodule Cadence.Runtime.Telemetry.UplinkPipeline do
  @moduledoc """
  Uplink processing pipeline decoupled from transport interfaces.
  """

  use GenServer
  require Logger

  alias Cadence.CCSDS.Core.{PDU, SDUOctets}
  alias Cadence.CCSDS.SDU.Registry, as: SDURegistry
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

  def encode(mission_id, interface_id, payload, ctx \\ %{}) do
    GenServer.call(via_tuple(mission_id, interface_id), {:encode, payload, ctx})
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
  def handle_call({:encode, payload, ctx}, _from, %State{sdlp?: true} = state) do
    case encode_sdlp(payload, ctx, state) do
      {:ok, encoded, updated_state} -> {:reply, {:ok, encoded}, updated_state}
      {:error, reason, updated_state} -> {:reply, {:error, reason}, updated_state}
    end
  end

  def handle_call({:encode, payload, ctx}, _from, %State{sdlp?: false} = state) do
    case encode_no_sdlp(payload, ctx, state) do
      {:ok, encoded} -> {:reply, {:ok, encoded}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
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

  defp encode_sdlp(_payload, _ctx, %State{uplink_pipeline: nil} = state) do
    {:error, :uplink_pipeline_unavailable, state}
  end

  defp encode_sdlp(%SDUOctets{} = sdu, ctx, %State{} = state) do
    ctx = merge_ctx(state.uplink_opts, ctx)

    case Pipeline.encode(sdu, ctx, state.uplink_pipeline, state.uplink_opts) do
      {:ok, encoded, new_pipeline} ->
        {:ok, encoded, %{state | uplink_pipeline: new_pipeline}}

      {:error, reason, new_pipeline} ->
        {:error, reason, %{state | uplink_pipeline: new_pipeline}}
    end
  end

  defp encode_sdlp(%PDU{} = pdu, ctx, %State{} = state) do
    ctx = merge_ctx(state.uplink_opts, ctx)
    opts = encode_opts(state.uplink_opts, ctx)

    case Pipeline.encode(pdu, ctx, state.uplink_pipeline, opts) do
      {:ok, encoded, new_pipeline} ->
        {:ok, encoded, %{state | uplink_pipeline: new_pipeline}}

      {:error, reason, new_pipeline} ->
        {:error, reason, %{state | uplink_pipeline: new_pipeline}}
    end
  end

  defp encode_sdlp(data, ctx, %State{} = state) when is_binary(data) do
    sdu = sdu_from_bytes(data, state, ctx)
    encode_sdlp(sdu, ctx, state)
  end

  defp encode_no_sdlp(%PDU{} = pdu, ctx, %State{} = state) do
    opts = encode_opts(state.uplink_opts, ctx)

    with {:ok, codec} <- SDURegistry.fetch(pdu.type),
         {:ok, %SDUOctets{} = sdu} <- codec.encode(pdu, opts) do
      {:ok, sdu.octets}
    else
      :error -> {:error, :unknown_sdu_type}
      {:error, reason} -> {:error, reason}
    end
  end

  defp encode_no_sdlp(%SDUOctets{octets: octets}, _ctx, _state), do: {:ok, octets}
  defp encode_no_sdlp(data, _ctx, _state) when is_binary(data), do: {:ok, data}
  defp encode_no_sdlp(_payload, _ctx, _state), do: {:error, :invalid_payload}

  defp merge_ctx(opts, ctx) do
    uplink = uplink_ctx(opts)
    Map.merge(uplink, ctx || %{})
  end

  defp encode_opts(opts, ctx) do
    opts = opts || []

    opts
    |> Keyword.put(:scid, ctx[:scid])
    |> Keyword.put(:vcid, ctx[:vcid])
    |> Keyword.put(:map_id, ctx[:map_id])
    |> Keyword.put(:direction, :uplink)
  end

  defp sdu_from_bytes(data, %State{} = state, ctx) do
    ctx = merge_ctx(state.uplink_opts, ctx)

    %SDUOctets{
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
  end

  defp uplink_ctx(nil), do: %{}

  defp uplink_ctx(opts) do
    %{
      frame_size: opts[:frame_size],
      scid: opts[:uplink_scid] || opts[:scid],
      vcid: opts[:uplink_vcid] || opts[:vcid],
      map_id: opts[:uplink_map_id]
    }
  end
end
