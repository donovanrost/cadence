defmodule Cadence.Runtime.Uplink.FrameBuilder do
  @moduledoc """
  Builds TC frames for COP-1 uplink from PDUs.
  """

  alias Cadence.CCSDS.Core.PDU
  alias Cadence.CCSDS.SDU.Registry, as: SDURegistry
  alias Cadence.CCSDS.TC.{FrameCodec, Segmentation}

  @spec init_segmentation(keyword()) :: {:ok, term()} | {:error, term()}
  def init_segmentation(opts) when is_list(opts) do
    Segmentation.init(opts)
  end

  @spec build_frames(PDU.t(), map(), term()) ::
          {:ok, [map()], term()} | {:error, term()}
  def build_frames(%PDU{} = pdu, ctx, segmentation_state) when is_map(ctx) do
    with {:ok, sdu} <- encode_sdu(pdu, ctx),
         {:ok, frames, seg_state} <- segment_sdu(sdu, ctx, segmentation_state),
         {:ok, envelopes} <- encode_frames(frames, ctx) do
      {:ok, envelopes, seg_state}
    else
      {:error, reason} -> {:error, reason}
      {:error, reason, _seg_state} -> {:error, reason}
    end
  end

  defp encode_sdu(%PDU{} = pdu, ctx) do
    opts = [
      profile: :tc,
      direction: :uplink,
      scid: Map.get(ctx, :scid),
      vcid: Map.get(ctx, :vcid),
      map_id: Map.get(ctx, :map_id)
    ]

    case SDURegistry.fetch(pdu.type) do
      {:ok, codec} -> codec.encode(pdu, opts)
      :error -> {:error, :unknown_sdu_type}
    end
  end

  defp segment_sdu(sdu, ctx, segmentation_state) do
    seg_ctx = %{
      frame_size: Map.fetch!(ctx, :frame_size),
      bypass_flag: Map.get(ctx, :bypass_flag, 0),
      control_command_flag: Map.get(ctx, :control_command_flag, 0),
      segment_header_flag: Map.get(ctx, :segment_header_flag, 0)
    }

    Segmentation.segment(sdu, seg_ctx, segmentation_state)
  end

  defp encode_frames(frames, ctx) do
    frame_size = Map.fetch!(ctx, :frame_size)

    frames
    |> Enum.reduce({:ok, []}, fn frame, {:ok, acc} ->
      case FrameCodec.encode(frame, frame_size: frame_size) do
        {:ok, bytes} ->
          {:ok,
           [
             %{seq: frame.frame_seq, bytes: bytes, retries: 0}
             | acc
           ]}

        {:error, reason} ->
          {:error, reason}
      end
    end)
    |> case do
      {:ok, envelopes} -> {:ok, Enum.reverse(envelopes)}
      {:error, reason} -> {:error, reason}
    end
  end
end
