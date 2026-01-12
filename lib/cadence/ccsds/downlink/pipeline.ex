defmodule Cadence.CCSDS.Downlink.Pipeline do
  @moduledoc """
  Downlink pipeline: bytes -> LinkFrame -> SDUOctets -> PDU -> Packet.
  """

  alias Cadence.CCSDS.Core.{PDU, SDUOctets}
  alias Cadence.CCSDS.SDU.{Mapping, Registry}

  alias Cadence.CCSDS.Downlink.PacketAdapter

  @type state :: %{
          frame_buffer: binary(),
          reassembly: term(),
          frame_codec: module(),
          reassembly_mod: module()
        }

  @spec init(keyword()) :: {:ok, state()} | {:error, term()}
  def init(opts) do
    profile = Keyword.fetch!(opts, :profile)

    with {:ok, frame_codec, reassembly_mod} <- profile_modules(profile),
         {:ok, reassembly_state} <- init_reassembly(reassembly_mod, opts) do
      {:ok,
       %{
         frame_buffer: <<>>,
         reassembly: reassembly_state,
         frame_codec: frame_codec,
         reassembly_mod: reassembly_mod
       }}
    else
      _ -> {:error, :invalid_profile}
    end
  end

  defp profile_modules(:tm),
    do: {:ok, Cadence.CCSDS.SDLP.TM.FrameCodec, Cadence.CCSDS.SDLP.TM.Reassembly}

  defp profile_modules(:aos),
    do: {:ok, Cadence.CCSDS.SDLP.AOS.FrameCodec, Cadence.CCSDS.SDLP.AOS.Reassembly}

  defp profile_modules(:uslp),
    do: {:ok, Cadence.CCSDS.SDLP.USLP.FrameCodec, Cadence.CCSDS.SDLP.USLP.Reassembly}

  defp profile_modules(_profile), do: {:error, :invalid_profile}

  defp init_reassembly(reassembly_mod, opts) do
    reassembly_mod.init(opts)
  end

  @spec decode(binary(), map(), Mapping.t(), state(), keyword()) ::
          {:ok, [Cadence.Telemetry.Packet.t()], state()} | {:error, term(), state()}
  def decode(bytes, ctx, %Mapping{} = mapping, state, opts) when is_binary(bytes) do
    buffer = state.frame_buffer <> bytes

    frame_opts =
      Keyword.take(opts, [:frame_size, :secondary_header_length, :ocf_length, :timestamp])

    case state.frame_codec.decode(buffer, frame_opts) do
      {:ok, frames, rest} ->
        ctx = Map.put_new(ctx, :direction, :downlink)
        {packets, reassembly_state} = process_frames(frames, ctx, mapping, opts, state)
        {:ok, packets, %{state | frame_buffer: rest, reassembly: reassembly_state}}

      {:error, reason} ->
        {:error, reason, state}
    end
  end

  defp process_frames(frames, ctx, mapping, opts, state) do
    Enum.reduce(frames, {[], state.reassembly}, fn frame, {acc, st} ->
      ingest_frame(frame, ctx, mapping, opts, state.reassembly_mod, acc, st)
    end)
  end

  defp ingest_frame(frame, ctx, mapping, opts, reassembly_mod, acc, st) do
    case reassembly_mod.ingest(frame, ctx, st) do
      {:ok, sdu_octets, st1} ->
        decoded = decode_sdu_octets(sdu_octets, mapping, opts)
        {acc ++ decoded, st1}

      {:error, _reason, st1} ->
        {acc, st1}
    end
  end

  defp decode_sdu_octets(sdu_octets_list, mapping, opts) do
    Enum.reduce(sdu_octets_list, [], fn %SDUOctets{} = sdu, acc ->
      with {:ok, sdu_type} <-
             Mapping.fetch(mapping, sdu.scid, sdu.vcid, sdu.map_id, sdu.direction),
           {:ok, codec} <- Registry.fetch(sdu_type),
           {:ok, %PDU{} = pdu} <- codec.decode(sdu, opts),
           {:ok, packet} <- PacketAdapter.to_packet(pdu, sdu, opts) do
        [packet | acc]
      else
        _ -> acc
      end
    end)
    |> Enum.reverse()
  end
end
