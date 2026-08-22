defmodule Cadence.Protocol.TMFramePipeline do
  @moduledoc """
  Thin adapter over the extracted TM frame codec and reassembly kernel.

  This is intentionally narrower than a full runtime integration. It gives the
  new application a pure, reusable surface for decoding packet-carrying TM
  frames without importing the legacy channel-service process topology.
  """

  alias CCSDS.Core.SDUOctets
  alias CCSDS.SDLP.TM.{FrameCodec, Reassembly}
  alias CCSDS.SpacePacket
  alias CCSDS.SpacePacket.Codec, as: SpacePacketCodec

  @type state :: term()

  @spec init(keyword()) :: {:ok, state()}
  def init(opts \\ []) when is_list(opts) do
    opts
    |> Keyword.put_new(:default_sdu_type, :space_packet)
    |> Reassembly.init()
  end

  @spec stats(state()) :: map()
  def stats(state), do: Reassembly.stats(state)

  @spec decode_sdu_octets(binary(), keyword(), state(), map()) ::
          {:ok, [SDUOctets.t()], binary(), state()} | {:error, term(), state()}
  def decode_sdu_octets(frame_bytes, codec_opts, state, ctx \\ %{})
      when is_binary(frame_bytes) and is_list(codec_opts) and is_map(ctx) do
    with {:ok, sdu_octets, _frame_infos, _anomalies, rest, next_state} <-
           decode_sdu_octets_detailed(frame_bytes, codec_opts, state, ctx) do
      {:ok, sdu_octets, rest, next_state}
    end
  end

  @spec decode_sdu_octets_detailed(binary(), keyword(), state(), map()) ::
          {:ok, [SDUOctets.t()], [map()], [map()], binary(), state()} | {:error, term(), state()}
  def decode_sdu_octets_detailed(frame_bytes, codec_opts, state, ctx \\ %{})
      when is_binary(frame_bytes) and is_list(codec_opts) and is_map(ctx) do
    with {:ok, frame_infos, decode_anomalies, rest} <-
           FrameCodec.decode_detailed(frame_bytes, codec_opts) do
      context =
        ctx
        |> Map.put_new(:direction, :downlink)
        |> Map.put_new(:sdu_kind_hint, :space_packet)

      reduce_frames(frame_infos, decode_anomalies, rest, state, context)
    end
  end

  @spec decode_space_packets(binary(), keyword(), state(), map()) ::
          {:ok, [binary()], binary(), state()} | {:error, term(), state()}
  def decode_space_packets(frame_bytes, codec_opts, state, ctx \\ %{}) do
    with {:ok, sdu_octets, rest, next_state} <-
           decode_sdu_octets(frame_bytes, codec_opts, state, ctx) do
      packets =
        sdu_octets
        |> Enum.filter(&(&1.sdu_kind_hint == :space_packet))
        |> Enum.map(& &1.octets)
        |> Enum.reject(&idle_space_packet?/1)

      {:ok, packets, rest, next_state}
    end
  end

  defp reduce_frames(frame_infos, decode_anomalies, rest, state, ctx) do
    frame_infos
    |> Enum.reduce({[], [], Enum.reverse(decode_anomalies), state}, fn frame_info,
                                                                       {acc_sdu_octets,
                                                                        kept_frames, anomalies,
                                                                        current_state} ->
      case Reassembly.ingest_detailed(frame_info.frame, ctx, current_state) do
        {:ok, sdu_octets, reassembly_anomalies, next_state} ->
          {Enum.reverse(sdu_octets, acc_sdu_octets), [frame_info | kept_frames],
           reassembly_anomalies
           |> locate_anomalies(frame_info)
           |> Enum.reverse(anomalies), next_state}

        {:error, reason, reassembly_anomalies, next_state} ->
          error_anomaly = %{
            anomaly_kind: :frame_reassembly_error,
            scid: frame_info.frame.scid,
            vcid: frame_info.frame.vcid,
            map_id: frame_info.frame.map_id,
            frame_seq: frame_info.frame.frame_seq,
            raw_frame_offset_bytes: frame_info.raw_frame_offset_bytes,
            raw_frame_length_bytes: frame_info.raw_frame_length_bytes,
            metadata: %{reason: reason, frame_meta: frame_info.frame.meta}
          }

          located_anomalies = locate_anomalies(reassembly_anomalies, frame_info)

          {acc_sdu_octets, kept_frames,
           [error_anomaly | Enum.reverse(located_anomalies, anomalies)], next_state}
      end
    end)
    |> then(fn {sdu_octets, kept_frames, anomalies, next_state} ->
      {:ok, Enum.reverse(sdu_octets), Enum.reverse(kept_frames), Enum.reverse(anomalies), rest,
       next_state}
    end)
  end

  defp locate_anomalies(anomalies, frame_info) do
    Enum.map(anomalies, fn anomaly ->
      anomaly
      |> Map.put_new(:scid, frame_info.frame.scid)
      |> Map.put_new(:vcid, frame_info.frame.vcid)
      |> Map.put_new(:map_id, frame_info.frame.map_id)
      |> Map.put_new(:frame_seq, frame_info.frame.frame_seq)
      |> Map.put(:raw_frame_offset_bytes, frame_info.raw_frame_offset_bytes)
      |> Map.put(:raw_frame_length_bytes, frame_info.raw_frame_length_bytes)
    end)
  end

  defp idle_space_packet?(encoded_packet) do
    case SpacePacketCodec.decode(encoded_packet) do
      {:ok, packet} -> SpacePacket.idle?(packet)
      {:error, _reason} -> false
    end
  end
end
