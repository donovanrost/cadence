defmodule Cadence.Runtime.Telemetry.DeframeWorker do
  @moduledoc """
  Reassembles SDLP frames into packets for a single stream.
  """

  use GenServer
  require Logger

  alias Cadence.CCSDS.Core.{PDU, SDUOctets}
  alias Cadence.CCSDS.Metrics
  alias Cadence.CCSDS.PDUDispatcher
  alias Cadence.CCSDS.SDU.{Mapping, Registry}

  defmodule State do
    @moduledoc false
    defstruct [
      :mission_id,
      :interface_id,
      :connection_id,
      :profile,
      :scid,
      :vcid,
      :mapping,
      :opts,
      :reassembly_mod,
      :reassembly_state
    ]
  end

  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    profile = Keyword.fetch!(opts, :profile)
    mapping = Keyword.fetch!(opts, :mapping)
    reassembly_opts = Keyword.get(opts, :reassembly_opts, [])

    reassembly_mod = reassembly_module(profile)

    {:ok, reassembly_state} = reassembly_mod.init(reassembly_opts)

    state = %State{
      mission_id: Keyword.fetch!(opts, :mission_id),
      interface_id: Keyword.fetch!(opts, :interface_id),
      connection_id: Keyword.fetch!(opts, :connection_id),
      profile: profile,
      scid: Keyword.fetch!(opts, :scid),
      vcid: Keyword.fetch!(opts, :vcid),
      mapping: mapping,
      opts: Keyword.get(opts, :opts, []),
      reassembly_mod: reassembly_mod,
      reassembly_state: reassembly_state
    }

    {:ok, state}
  end

  @impl true
  def handle_cast({:ingest_frame, frame, ctx, base_meta}, state) do
    frame = %{frame | meta: Map.merge(base_meta, frame.meta || %{})}

    case state.reassembly_mod.ingest(frame, ctx, state.reassembly_state) do
      {:ok, sdu_octets, new_state} ->
        {packet_count, failures, idle_count} =
          process_sdu_octets(sdu_octets, base_meta, state)

        Metrics.inc(
          state.mission_id,
          state.interface_id,
          state.profile,
          :sdu_octets,
          length(sdu_octets)
        )

        Metrics.inc(
          state.mission_id,
          state.interface_id,
          state.profile,
          :packets_emitted,
          packet_count
        )

        Metrics.inc(
          state.mission_id,
          state.interface_id,
          state.profile,
          :sdu_decode_errors,
          failures
        )

        Metrics.inc(
          state.mission_id,
          state.interface_id,
          state.profile,
          :idle_packets,
          idle_count
        )

        notify_interface(packet_count, state)
        {:noreply, %{state | reassembly_state: new_state}}

      {:error, reason, new_state} ->
        Metrics.inc(state.mission_id, state.interface_id, state.profile, :reassembly_errors, 1)

        Logger.warning(
          "Deframe worker dropped frame (profile=#{state.profile}, scid=#{state.scid}, vcid=#{state.vcid}): #{inspect(reason)}"
        )

        {:noreply, %{state | reassembly_state: new_state}}

      {:error, reason} ->
        Metrics.inc(state.mission_id, state.interface_id, state.profile, :reassembly_errors, 1)

        Logger.warning(
          "Deframe worker dropped frame (profile=#{state.profile}, scid=#{state.scid}, vcid=#{state.vcid}): #{inspect(reason)}"
        )

        {:noreply, state}
    end
  end

  defp reassembly_module(:tm), do: Cadence.CCSDS.SDLP.TM.Reassembly
  defp reassembly_module(:aos), do: Cadence.CCSDS.SDLP.AOS.Reassembly
  defp reassembly_module(:uslp), do: Cadence.CCSDS.SDLP.USLP.Reassembly

  defp process_sdu_octets(sdu_octets_list, base_meta, state) do
    Enum.reduce(sdu_octets_list, {0, 0, 0}, fn %SDUOctets{} = sdu,
                                               {packets, failures, idle_count} ->
      case decode_sdu_to_pdu(sdu, state.mapping, state.opts) do
        {:ok, %PDU{} = pdu} ->
          dispatch_pdu(pdu, sdu, base_meta, state)
          {packets + 1, failures, idle_count}

        {:skip, :idle} ->
          {packets, failures, idle_count + 1}

        {:error, _} ->
          {packets, failures + 1, idle_count}
      end
    end)
  end

  defp decode_sdu_to_pdu(%SDUOctets{} = sdu, %Mapping{} = mapping, opts) do
    with {:ok, sdu_type} <-
           Mapping.fetch(mapping, sdu.scid, sdu.vcid, sdu.map_id, sdu.direction),
         {:ok, codec} <- Registry.fetch(sdu_type) do
      case codec.decode(sdu, opts) do
        {:ok, %PDU{value: :idle}} -> {:skip, :idle}
        {:ok, %PDU{} = pdu} -> {:ok, pdu}
        {:error, reason} -> {:error, reason}
      end
    else
      _ -> {:error, :decode_failed}
    end
  end

  defp dispatch_pdu(%PDU{} = pdu, %SDUOctets{} = sdu, base_meta, state) do
    ctx = %{
      mission_id: state.mission_id,
      interface_id: state.interface_id,
      connection_id: state.connection_id,
      profile: state.profile,
      scid: state.scid,
      vcid: state.vcid,
      base_meta: base_meta,
      sdu: sdu,
      opts: state.opts
    }

    PDUDispatcher.ingest(dispatcher_name(state), pdu, ctx)
  end

  defp notify_interface(0, _state), do: :ok

  defp notify_interface(count, state) do
    GenServer.cast(interface_name(state), {:downlink_packets, state.connection_id, count})
  end

  defp interface_name(state) do
    {:via, Registry,
     {Cadence.MissionRegistry, {:interface, state.mission_id, state.interface_id}}}
  end

  defp dispatcher_name(state) do
    PDUDispatcher.via_tuple(state.mission_id, state.interface_id)
  end
end
