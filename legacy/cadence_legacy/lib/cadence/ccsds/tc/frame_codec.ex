defmodule Cadence.CCSDS.TC.FrameCodec do
  @moduledoc """
  TC transfer frame codec.
  """

  @behaviour Cadence.CCSDS.SDLP.FrameCodec

  alias Cadence.CCSDS.Core.LinkFrame
  alias Cadence.CCSDS.TC.TransferFrame

  @impl true
  def profile, do: :tc

  @impl true
  def decode(bin, opts) when is_binary(bin) do
    frame_size = Keyword.fetch!(opts, :frame_size)
    timestamp = Keyword.get(opts, :timestamp)

    case TransferFrame.decode(bin, frame_size: frame_size) do
      {:ok, frames, rest} ->
        decoded = Enum.map(frames, &to_link_frame(&1, timestamp))
        {:ok, decoded, rest}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def encode(%LinkFrame{profile: :tc} = frame, opts) do
    frame_size = Keyword.fetch!(opts, :frame_size)

    tc_frame =
      %TransferFrame{
        version: Map.get(frame.meta, :version, 0),
        bypass_flag: Map.get(frame.meta, :bypass_flag, 0),
        control_command_flag: Map.get(frame.meta, :control_command_flag, 0),
        scid: frame.scid,
        vcid: frame.vcid,
        frame_length: Map.get(frame.meta, :frame_length),
        frame_seq: frame.frame_seq || 0,
        segment_header_flag: Map.get(frame.meta, :segment_header_flag, 0),
        spare: Map.get(frame.meta, :spare, 0),
        payload: frame.payload_octets
      }

    TransferFrame.encode(tc_frame, frame_size: frame_size)
  end

  def encode(_frame, _opts), do: {:error, :invalid_profile}

  defp to_link_frame(%TransferFrame{} = frame, timestamp) do
    %LinkFrame{
      profile: :tc,
      scid: frame.scid,
      vcid: frame.vcid,
      map_id: nil,
      frame_seq: frame.frame_seq,
      payload_octets: frame.payload,
      quality: :good,
      ocf: nil,
      timestamp: timestamp,
      meta: %{
        version: frame.version,
        bypass_flag: frame.bypass_flag,
        control_command_flag: frame.control_command_flag,
        frame_length: frame.frame_length,
        segment_header_flag: frame.segment_header_flag,
        spare: frame.spare
      }
    }
  end
end
