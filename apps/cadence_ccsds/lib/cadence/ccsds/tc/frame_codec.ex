defmodule Cadence.CCSDS.TC.FrameCodec do
  @moduledoc """
  TC transfer frame codec.
  """

  @behaviour Cadence.CCSDS.SDLP.FrameCodec

  alias Cadence.CCSDS.Core.LinkFrame
  alias Cadence.CCSDS.TC.{SegmentHeader, TransferFrame}

  @impl true
  def profile, do: :tc

  @impl true
  def decode(bin, opts) when is_binary(bin) do
    frame_size = Keyword.fetch!(opts, :frame_size)
    timestamp = Keyword.get(opts, :timestamp)

    case TransferFrame.decode(bin, frame_size: frame_size) do
      {:ok, frames, rest} ->
        with {:ok, decoded} <- decode_frames(frames, timestamp, opts) do
          {:ok, decoded, rest}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def encode(%LinkFrame{profile: :tc} = frame, opts) do
    frame_size = Keyword.fetch!(opts, :frame_size)

    with {:ok, payload} <- encode_data_field(frame) do
      tc_frame =
        %TransferFrame{
          version: Map.get(frame.meta, :version, 0),
          bypass_flag: Map.get(frame.meta, :bypass_flag, 0),
          control_command_flag: Map.get(frame.meta, :control_command_flag, 0),
          spare: Map.get(frame.meta, :spare, 0),
          scid: frame.scid,
          vcid: frame.vcid,
          frame_length: Map.get(frame.meta, :frame_length),
          frame_seq: frame.frame_seq || 0,
          payload: payload
        }

      TransferFrame.encode(tc_frame, frame_size: frame_size)
    end
  end

  def encode(_frame, _opts), do: {:error, :invalid_profile}

  defp decode_frames(frames, timestamp, opts) do
    Enum.reduce_while(frames, {:ok, []}, fn frame, {:ok, acc} ->
      case to_link_frame(frame, timestamp, opts) do
        {:ok, link_frame} -> {:cont, {:ok, [link_frame | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, decoded} -> {:ok, Enum.reverse(decoded)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp to_link_frame(%TransferFrame{} = frame, timestamp, opts) do
    segment_header_flag = managed_segment_header_flag(frame.vcid, opts)

    with :ok <-
           validate_segment_header_for_frame_type(
             segment_header_flag,
             frame.control_command_flag
           ),
         {:ok, map_id, sequence_flag, payload} <-
           decode_data_field(frame.payload, segment_header_flag) do
      {:ok,
       %LinkFrame{
         profile: :tc,
         scid: frame.scid,
         vcid: frame.vcid,
         map_id: map_id,
         frame_seq: frame.frame_seq,
         payload_octets: payload,
         quality: :good,
         ocf: nil,
         timestamp: timestamp,
         meta: %{
           version: frame.version,
           bypass_flag: frame.bypass_flag,
           control_command_flag: frame.control_command_flag,
           frame_length: frame.frame_length,
           segment_header_flag: segment_header_flag,
           sequence_flag: sequence_flag,
           spare: frame.spare
         }
       }}
    end
  end

  defp encode_data_field(%LinkFrame{} = frame) do
    segment_header_flag = Map.get(frame.meta, :segment_header_flag, 0)
    control_command_flag = Map.get(frame.meta, :control_command_flag, 0)

    with :ok <-
           validate_segment_header_for_frame_type(
             segment_header_flag,
             control_command_flag
           ) do
      do_encode_data_field(frame, segment_header_flag)
    end
  end

  defp do_encode_data_field(%LinkFrame{} = frame, 0), do: {:ok, frame.payload_octets}

  defp do_encode_data_field(%LinkFrame{} = frame, 1) do
    header = %SegmentHeader{
      sequence_flag: Map.get(frame.meta, :sequence_flag),
      map_id: frame.map_id
    }

    with {:ok, encoded_header} <- SegmentHeader.encode(header) do
      {:ok, encoded_header <> frame.payload_octets}
    end
  end

  defp do_encode_data_field(_frame, value),
    do: {:error, {:invalid_segment_header_flag, value}}

  defp decode_data_field(payload, 0), do: {:ok, nil, nil, payload}

  defp decode_data_field(payload, 1) do
    with {:ok, %SegmentHeader{} = header, user_data} <- SegmentHeader.decode(payload) do
      {:ok, header.map_id, header.sequence_flag, user_data}
    end
  end

  defp decode_data_field(_payload, value),
    do: {:error, {:invalid_segment_header_flag, value}}

  defp managed_segment_header_flag(vcid, opts) do
    by_vcid = Keyword.get(opts, :segment_header_by_vcid, %{})
    configured = Map.get(by_vcid, vcid, Keyword.get(opts, :segment_header_flag, 0))

    case configured do
      true -> 1
      false -> 0
      value -> value
    end
  end

  defp validate_segment_header_for_frame_type(1, 1),
    do: {:error, :segment_header_forbidden_on_control_command}

  defp validate_segment_header_for_frame_type(value, _control_command_flag)
       when value in [0, 1],
       do: :ok

  defp validate_segment_header_for_frame_type(value, _control_command_flag),
    do: {:error, {:invalid_segment_header_flag, value}}
end
