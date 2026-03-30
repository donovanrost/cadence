defmodule Cadence.CCSDS.TC.TransferFrame do
  @moduledoc """
  Minimal encoder/decoder for CCSDS TC transfer frames with the primary header.
  """

  @primary_header_size 5

  @type t :: %__MODULE__{
          version: non_neg_integer(),
          bypass_flag: 0 | 1,
          control_command_flag: 0 | 1,
          scid: non_neg_integer(),
          vcid: non_neg_integer(),
          frame_length: non_neg_integer(),
          frame_seq: non_neg_integer(),
          segment_header_flag: 0 | 1,
          spare: 0 | 1,
          payload: binary()
        }

  defstruct [
    :version,
    :bypass_flag,
    :control_command_flag,
    :scid,
    :vcid,
    :frame_length,
    :frame_seq,
    :segment_header_flag,
    :spare,
    :payload
  ]

  @spec encode(t(), keyword()) :: {:ok, binary()} | {:error, term()}
  def encode(%__MODULE__{} = frame, opts) do
    frame_size = Keyword.fetch!(opts, :frame_size)

    with {:ok, payload, frame_length} <- normalize_payload(frame, frame_size),
         {:ok, header_fields} <- validate_header_fields(frame, frame_length, frame_size),
         {:ok, header} <- build_header(header_fields) do
      {:ok, header <> payload}
    end
  end

  @spec decode(binary(), keyword()) :: {:ok, [t()], binary()} | {:error, term()}
  def decode(buffer, opts) when is_binary(buffer) do
    frame_size = Keyword.fetch!(opts, :frame_size)

    case validate_frame_size(frame_size) do
      :ok -> decode_frames(buffer, frame_size)
      {:error, reason} -> {:error, reason}
    end
  end

  defp split_frames(buffer, frame_size) do
    if byte_size(buffer) < frame_size do
      {:incomplete, buffer}
    else
      frame_count = div(byte_size(buffer), frame_size)
      total_size = frame_count * frame_size
      <<frames_bin::binary-size(total_size), rest::binary>> = buffer
      frames = for <<frame::binary-size(frame_size) <- frames_bin>>, do: frame
      {frames, rest}
    end
  end

  defp decode_frame(<<
         version::2,
         bypass_flag::1,
         control_command_flag::1,
         scid::10,
         vcid::6,
         frame_length::10,
         frame_seq::8,
         segment_header_flag::1,
         spare::1,
         payload::binary
       >>) do
    {:ok,
     %__MODULE__{
       version: version,
       bypass_flag: bypass_flag,
       control_command_flag: control_command_flag,
       scid: scid,
       vcid: vcid,
       frame_length: frame_length,
       frame_seq: frame_seq,
       segment_header_flag: segment_header_flag,
       spare: spare,
       payload: payload
     }}
  end

  defp decode_frame(_frame), do: {:error, :invalid_frame}

  defp decode_frames(buffer, frame_size) do
    case split_frames(buffer, frame_size) do
      {:incomplete, rest} ->
        {:ok, [], rest}

      {frames, rest} ->
        decoded =
          frames
          |> Enum.map(&decode_frame/1)
          |> Enum.filter(&match?({:ok, %__MODULE__{}}, &1))
          |> Enum.map(fn {:ok, frame} -> frame end)

        {:ok, decoded, rest}
    end
  end

  defp normalize_payload(%__MODULE__{} = frame, frame_size) do
    max_payload = frame_size - @primary_header_size

    if max_payload <= 0 do
      {:error, :frame_size_too_small}
    else
      payload = frame.payload || <<>>

      if byte_size(payload) != max_payload do
        {:error, {:invalid_data_field_length, byte_size(payload), max_payload}}
      else
        frame_length = frame.frame_length || frame_size - 1
        {:ok, payload, frame_length}
      end
    end
  end

  defp validate_header_fields(%__MODULE__{} = frame, frame_length, frame_size) do
    fields = %{
      version: frame.version || 0,
      bypass_flag: frame.bypass_flag || 0,
      control_command_flag: frame.control_command_flag || 0,
      segment_header_flag: frame.segment_header_flag || 0,
      spare: frame.spare || 0,
      scid: frame.scid,
      vcid: frame.vcid,
      frame_seq: frame.frame_seq || 0,
      frame_length: frame_length
    }

    with :ok <- validate_version(fields.version),
         :ok <- validate_frame_length(fields.frame_length, frame_size),
         :ok <- validate_flag(fields.bypass_flag, :bypass_flag),
         :ok <- validate_flag(fields.control_command_flag, :control_command_flag),
         :ok <- validate_flag(fields.segment_header_flag, :segment_header_flag),
         :ok <- validate_flag(fields.spare, :spare),
         :ok <- validate_range(fields.scid, 0, 1023, :scid),
         :ok <- validate_range(fields.vcid, 0, 63, :vcid),
         :ok <- validate_range(fields.frame_length, 0, 1023, :frame_length),
         :ok <- validate_range(fields.frame_seq, 0, 255, :frame_seq) do
      {:ok, fields}
    end
  end

  defp build_header(fields) do
    {:ok,
     <<
       fields.version::2,
       fields.bypass_flag::1,
       fields.control_command_flag::1,
       fields.scid::10,
       fields.vcid::6,
       fields.frame_length::10,
       fields.frame_seq::8,
       fields.segment_header_flag::1,
       fields.spare::1
     >>}
  end

  defp validate_frame_size(frame_size) when frame_size > @primary_header_size, do: :ok
  defp validate_frame_size(_frame_size), do: {:error, :frame_size_too_small}

  defp validate_version(0), do: :ok
  defp validate_version(value), do: {:error, {:unsupported_version, value}}

  defp validate_frame_length(frame_length, frame_size) do
    expected = frame_size - 1

    if frame_length == expected do
      :ok
    else
      {:error, {:invalid_frame_length, frame_length, expected}}
    end
  end

  defp validate_flag(value, _field) when value in [0, 1], do: :ok
  defp validate_flag(value, field), do: {:error, {:invalid_flag, field, value}}

  defp validate_range(nil, _min, _max, field), do: {:error, {:missing_field, field}}

  defp validate_range(value, min, max, _field)
       when is_integer(value) and value >= min and value <= max,
       do: :ok

  defp validate_range(value, _min, _max, field), do: {:error, {:invalid_field, field, value}}
end
