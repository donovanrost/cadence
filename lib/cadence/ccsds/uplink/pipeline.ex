defmodule Cadence.CCSDS.Uplink.Pipeline do
  @moduledoc """
  Uplink pipeline: PDU -> SDUOctets -> LinkFrame -> bytes.
  """

  alias Cadence.CCSDS.Core.{LinkFrame, PDU, SDUOctets}
  alias Cadence.CCSDS.SDU.Registry

  @type state :: %{
          segmentation: term(),
          frame_codec: module(),
          segmentation_mod: module()
        }

  @spec init(keyword()) :: {:ok, state()} | {:error, term()}
  def init(opts) do
    profile = Keyword.fetch!(opts, :profile)

    with {:ok, frame_codec, segmentation_mod} <- profile_modules(profile),
         {:ok, segmentation_state} <- init_segmentation(segmentation_mod, opts) do
      {:ok,
       %{
         segmentation: segmentation_state,
         frame_codec: frame_codec,
         segmentation_mod: segmentation_mod
       }}
    else
      _ -> {:error, :invalid_profile}
    end
  end

  defp profile_modules(:tm),
    do: {:ok, Cadence.CCSDS.SDLP.TM.FrameCodec, Cadence.CCSDS.SDLP.TM.Segmentation}

  defp profile_modules(:aos),
    do: {:ok, Cadence.CCSDS.SDLP.AOS.FrameCodec, Cadence.CCSDS.SDLP.AOS.Segmentation}

  defp profile_modules(:uslp),
    do: {:ok, Cadence.CCSDS.SDLP.USLP.FrameCodec, Cadence.CCSDS.SDLP.USLP.Segmentation}

  defp profile_modules(_profile), do: {:error, :invalid_profile}

  defp init_segmentation(segmentation_mod, opts) do
    segmentation_mod.init(opts)
  end

  @spec encode(PDU.t() | SDUOctets.t(), map(), state(), keyword()) ::
          {:ok, binary(), state()} | {:error, term(), state()}
  def encode(%PDU{} = pdu, ctx, state, opts) do
    with {:ok, sdu} <- encode_sdu(pdu, opts),
         {:ok, frames, seg_state} <- state.segmentation_mod.segment(sdu, ctx, state.segmentation),
         {:ok, bytes} <- encode_frames(frames, opts) do
      {:ok, bytes, %{state | segmentation: seg_state}}
    else
      {:error, reason} -> {:error, reason, state}
      {:error, reason, seg_state} -> {:error, reason, %{state | segmentation: seg_state}}
    end
  end

  def encode(%SDUOctets{} = sdu, ctx, state, opts) do
    with {:ok, frames, seg_state} <- state.segmentation_mod.segment(sdu, ctx, state.segmentation),
         {:ok, bytes} <- encode_frames(frames, opts) do
      {:ok, bytes, %{state | segmentation: seg_state}}
    else
      {:error, reason} -> {:error, reason, state}
      {:error, reason, seg_state} -> {:error, reason, %{state | segmentation: seg_state}}
    end
  end

  def encode(_payload, _ctx, state, _opts), do: {:error, :invalid_payload, state}

  defp encode_sdu(%PDU{} = pdu, opts) do
    case Registry.fetch(pdu.type) do
      {:ok, codec} -> codec.encode(pdu, opts)
      :error -> {:error, :unknown_sdu_type}
    end
  end

  defp encode_frames(frames, opts) do
    frame_opts = Keyword.take(opts, [:frame_size, :secondary_header_length, :ocf_length])

    frames
    |> Enum.reduce({:ok, []}, fn %LinkFrame{} = frame, {:ok, acc} ->
      case frame_codec_encode(frame, frame_opts) do
        {:ok, bin} -> {:ok, [bin | acc]}
        {:error, reason} -> {:error, reason}
      end
    end)
    |> case do
      {:ok, bins} -> {:ok, bins |> Enum.reverse() |> IO.iodata_to_binary()}
      {:error, reason} -> {:error, reason}
    end
  end

  defp frame_codec_encode(frame, opts) do
    case ensure_profile(frame) do
      :ok -> frame_codec_for(frame).encode(frame, opts)
      {:error, reason} -> {:error, reason}
    end
  end

  defp frame_codec_for(%LinkFrame{profile: :tm}), do: Cadence.CCSDS.SDLP.TM.FrameCodec
  defp frame_codec_for(%LinkFrame{profile: :aos}), do: Cadence.CCSDS.SDLP.AOS.FrameCodec
  defp frame_codec_for(%LinkFrame{profile: :uslp}), do: Cadence.CCSDS.SDLP.USLP.FrameCodec

  defp ensure_profile(%LinkFrame{profile: profile}) when profile in [:tm, :aos, :uslp], do: :ok
  defp ensure_profile(_), do: {:error, :invalid_profile}
end
