defmodule Cadence.Runtime.Telemetry.UplinkPipeline do
  @moduledoc """
  Uplink processing pipeline decoupled from transport interfaces.

  All uplink bytes (COP-1 and non-COP-1) are sent via release contracts.
  """

  use GenServer
  require Logger

  alias Cadence.CCSDS.Core.{PDU, SDUOctets}
  alias Cadence.CCSDS.Metrics
  alias Cadence.CCSDS.SDU.Registry, as: SDURegistry
  alias Cadence.CCSDS.Uplink.Pipeline
  alias Cadence.Domain.Interfaces.Entities.Interface
  alias Cadence.Runtime.Interfaces.SDLPConfig
  alias Cadence.Runtime.Uplink.FramingContext
  alias Cadence.Runtime.Uplink.ReleasedUplinkFrame

  defmodule State do
    @moduledoc false
    defstruct [
      :mission_id,
      :interface_id,
      :uplink_pipeline,
      :uplink_opts,
      :send_fun,
      sdlp?: false
    ]
  end

  def start_link(opts) do
    interface = Keyword.fetch!(opts, :interface)
    name = via_tuple(interface.mission_id, interface.id)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def via_tuple(mission_id, interface_id) do
    {:via, Registry, {Cadence.MissionRegistry, {:uplink_pipeline, mission_id, interface_id}}}
  end

  def encode(mission_id, interface_id, payload, framing_context \\ nil) do
    GenServer.call(via_tuple(mission_id, interface_id), {:encode, payload, framing_context})
  end

  @spec send_release(ReleasedUplinkFrame.t()) :: :ok | {:error, term()}
  def send_release(%ReleasedUplinkFrame{} = release) do
    case Registry.lookup(
           Cadence.MissionRegistry,
           {:uplink_pipeline, release.mission_id, release.interface_id}
         ) do
      [{pid, _}] -> GenServer.call(pid, {:send_release, release})
      [] -> {:error, :uplink_pipeline_unavailable}
    end
  end

  def reset(mission_id, interface_id) do
    GenServer.cast(via_tuple(mission_id, interface_id), :reset)
  end

  @impl true
  def init(opts) do
    interface = Keyword.fetch!(opts, :interface)
    send_fun = Keyword.get(opts, :send_fun)
    {sdlp?, uplink_pipeline, uplink_opts} = init_uplink_pipeline(interface)

    {:ok,
     %State{
       mission_id: interface.mission_id,
       interface_id: interface.id,
       sdlp?: sdlp?,
       uplink_pipeline: uplink_pipeline,
       uplink_opts: uplink_opts,
       send_fun: send_fun
     }}
  end

  @impl true
  def handle_call({:encode, payload, framing_context}, _from, %State{sdlp?: true} = state) do
    framing_context = ensure_context(framing_context)

    case encode_sdlp(payload, framing_context, state) do
      {:ok, encoded, updated_state} -> {:reply, {:ok, encoded}, updated_state}
      {:error, reason, updated_state} -> {:reply, {:error, reason}, updated_state}
    end
  end

  def handle_call({:encode, payload, framing_context}, _from, %State{sdlp?: false} = state) do
    framing_context = ensure_context(framing_context)

    case encode_no_sdlp(payload, framing_context, state) do
      {:ok, encoded} -> {:reply, {:ok, encoded}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call(
        {:send_release, %ReleasedUplinkFrame{bytes: bytes} = release},
        _from,
        %State{} = state
      )
      when is_binary(bytes) do
    record_release_metrics(state, release)
    {:reply, do_send_release(state, bytes), state}
  end

  def handle_call({:send_release, _release}, _from, state) do
    {:reply, {:error, :invalid_payload}, state}
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
        uplink_opts = build_uplink_opts(opts)

        case Pipeline.init(uplink_opts) do
          {:ok, pipeline} -> {true, pipeline, uplink_opts}
          {:error, _} -> {true, nil, uplink_opts}
        end

      :error ->
        {false, nil, nil}
    end
  end

  defp encode_sdlp(_payload, _context, %State{uplink_pipeline: nil} = state) do
    {:error, :uplink_pipeline_unavailable, state}
  end

  defp encode_sdlp(%SDUOctets{} = sdu, %FramingContext{} = context, %State{} = state) do
    context = FramingContext.with_defaults(context, state.uplink_opts)

    case Pipeline.encode(sdu, context, state.uplink_pipeline, state.uplink_opts) do
      {:ok, encoded, new_pipeline} ->
        {:ok, encoded, %{state | uplink_pipeline: new_pipeline}}

      {:error, reason, new_pipeline} ->
        {:error, reason, %{state | uplink_pipeline: new_pipeline}}
    end
  end

  defp encode_sdlp(%PDU{} = pdu, %FramingContext{} = context, %State{} = state) do
    context = FramingContext.with_defaults(context, state.uplink_opts)
    opts = encode_opts(state.uplink_opts, context)

    case Pipeline.encode(pdu, context, state.uplink_pipeline, opts) do
      {:ok, encoded, new_pipeline} ->
        {:ok, encoded, %{state | uplink_pipeline: new_pipeline}}

      {:error, reason, new_pipeline} ->
        {:error, reason, %{state | uplink_pipeline: new_pipeline}}
    end
  end

  defp encode_sdlp(data, %FramingContext{} = context, %State{} = state) when is_binary(data) do
    sdu = sdu_from_bytes(data, state, context)
    encode_sdlp(sdu, context, state)
  end

  defp encode_no_sdlp(%PDU{} = pdu, %FramingContext{} = context, %State{} = state) do
    opts = encode_opts(state.uplink_opts, context)

    with {:ok, codec} <- SDURegistry.fetch(pdu.type),
         {:ok, %SDUOctets{} = sdu} <- codec.encode(pdu, opts) do
      {:ok, sdu.octets}
    else
      :error -> {:error, :unknown_sdu_type}
      {:error, reason} -> {:error, reason}
    end
  end

  defp encode_no_sdlp(%SDUOctets{octets: octets}, _context, _state), do: {:ok, octets}
  defp encode_no_sdlp(data, _context, _state) when is_binary(data), do: {:ok, data}
  defp encode_no_sdlp(_payload, _context, _state), do: {:error, :invalid_payload}

  defp encode_opts(opts, %FramingContext{} = context) do
    opts = opts || []

    opts =
      if is_binary(context.ocf) do
        Keyword.put(opts, :ocf_length, context.ocf_length || byte_size(context.ocf))
      else
        opts
      end

    opts
    |> Keyword.put(:scid, context.scid)
    |> Keyword.put(:vcid, context.vcid)
    |> Keyword.put(:map_id, context.map_id)
    |> Keyword.put(:direction, :uplink)
  end

  defp sdu_from_bytes(data, %State{} = state, %FramingContext{} = context) do
    context = FramingContext.with_defaults(context, state.uplink_opts)

    %SDUOctets{
      profile: state.uplink_opts[:profile],
      scid: context.scid,
      vcid: context.vcid,
      map_id: context.map_id,
      direction: :uplink,
      sdu_kind_hint: :space_packet,
      octets: data,
      quality: :good,
      source_frames: [],
      timestamp: nil,
      meta: %{}
    }
  end

  defp build_uplink_opts(nil), do: nil

  defp build_uplink_opts(opts) do
    profile = opts[:uplink_profile] || opts[:profile]
    Keyword.put(opts, :profile, profile)
  end

  defp ensure_context(nil), do: FramingContext.new()
  defp ensure_context(%FramingContext{} = context), do: context

  defp do_send_release(%State{send_fun: send_fun} = _state, bytes)
       when is_function(send_fun, 1) do
    send_fun.(bytes)
    |> normalize_send_result()
  end

  defp do_send_release(%State{} = state, bytes) do
    case Registry.lookup(
           Cadence.MissionRegistry,
           {:interface, state.mission_id, state.interface_id}
         ) do
      [{pid, _}] ->
        GenServer.call(pid, {:send_data, bytes})
        |> normalize_send_result()

      [] ->
        {:error, :interface_not_running}
    end
  end

  defp record_release_metrics(%State{} = state, %ReleasedUplinkFrame{} = release) do
    {count_metric, bytes_metric} = release_metrics(release.kind)
    profile = release_profile(state)

    Metrics.inc(state.mission_id, state.interface_id, profile, count_metric, 1)

    Metrics.inc(
      state.mission_id,
      state.interface_id,
      profile,
      bytes_metric,
      byte_size(release.bytes)
    )

    :ok
  end

  defp release_metrics(kind) do
    case kind do
      :initial -> {:uplink_release_initial, :uplink_release_initial_bytes}
      :retransmit -> {:uplink_release_retransmit, :uplink_release_retransmit_bytes}
      :bypass -> {:uplink_release_bypass, :uplink_release_bypass_bytes}
      :direct -> {:uplink_release_direct, :uplink_release_direct_bytes}
      _ -> {:uplink_release_unknown, :uplink_release_unknown_bytes}
    end
  end

  defp release_profile(%State{uplink_opts: opts}) when is_list(opts) do
    opts[:profile] || :raw
  end

  defp release_profile(_state), do: :raw

  defp normalize_send_result(result) do
    case result do
      :ok ->
        :ok

      {:ok, _} ->
        :ok

      {:error, :interface_not_running} ->
        {:error, :interface_not_running}

      {:error, :not_connected} ->
        {:error, :send_failed, :no_clients_connected}

      {:error, :no_clients_connected} ->
        {:error, :send_failed, :no_clients_connected}

      {:error, :send_failed, reason} ->
        {:error, :send_failed, reason}

      {:error, reason, detail} ->
        {:error, :send_failed, {reason, detail}}

      {:error, reason} ->
        {:error, :send_failed, reason}
    end
  end
end
