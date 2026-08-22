defmodule CCSDS.TC.TransferFrame do
  @moduledoc """
  Encoder and streaming decoder for CCSDS TC transfer frames.

  `:frame_size` is the managed maximum frame size. Individual TC frames may be
  shorter; their actual boundary is carried by the Frame Length field.

  FECF presence is a managed option supplied as `fecf: true` on encode and
  decode. The Frame Length field includes the FECF when it is present.
  """

  alias CCSDS.FrameErrorControl

  @primary_header_size 5
  @maximum_frame_size 1024

  @type t :: %__MODULE__{
          version: non_neg_integer(),
          bypass_flag: 0 | 1,
          control_command_flag: 0 | 1,
          spare: 0..3,
          scid: non_neg_integer(),
          vcid: non_neg_integer(),
          frame_length: non_neg_integer(),
          frame_seq: non_neg_integer(),
          payload: binary(),
          fecf: FrameErrorControl.value() | nil
        }

  defstruct [
    :version,
    :bypass_flag,
    :control_command_flag,
    :spare,
    :scid,
    :vcid,
    :frame_length,
    :frame_seq,
    :payload,
    :fecf
  ]

  @spec encode(t(), keyword()) :: {:ok, binary()} | {:error, term()}
  def encode(%__MODULE__{} = frame, opts) do
    maximum_frame_size = Keyword.fetch!(opts, :frame_size)
    fecf? = Keyword.get(opts, :fecf, false)
    fecf_size = fecf_length_bytes(fecf?)

    with :ok <- validate_fecf_presence(fecf?),
         :ok <- validate_maximum_frame_size(maximum_frame_size, fecf_size),
         {:ok, payload, frame_length} <-
           normalize_payload(frame, maximum_frame_size, fecf_size),
         {:ok, header_fields} <-
           validate_header_fields(frame, frame_length, maximum_frame_size),
         {:ok, header} <- build_header(header_fields) do
      encoded = header <> payload
      {:ok, if(fecf?, do: FrameErrorControl.append(encoded), else: encoded)}
    end
  end

  @spec decode(binary(), keyword()) :: {:ok, [t()], binary()} | {:error, term()}
  def decode(buffer, opts) when is_binary(buffer) do
    maximum_frame_size = Keyword.fetch!(opts, :frame_size)
    fecf? = Keyword.get(opts, :fecf, false)
    fecf_size = fecf_length_bytes(fecf?)

    with :ok <- validate_fecf_presence(fecf?),
         :ok <- validate_maximum_frame_size(maximum_frame_size, fecf_size) do
      decode_frames(buffer, maximum_frame_size, fecf?, [])
    end
  end

  defp decode_frame(frame, fecf?) do
    with {:ok, frame_without_fecf, fecf} <- validate_and_strip_fecf(frame, fecf?),
         {:ok, %__MODULE__{} = decoded} <- decode_frame_body(frame_without_fecf) do
      {:ok, %{decoded | fecf: fecf}}
    end
  end

  defp decode_frame_body(<<
         version::2,
         bypass_flag::1,
         control_command_flag::1,
         spare::2,
         scid::10,
         vcid::6,
         frame_length::10,
         frame_seq::8,
         payload::binary
       >>) do
    frame = %__MODULE__{
      version: version,
      bypass_flag: bypass_flag,
      control_command_flag: control_command_flag,
      spare: spare,
      scid: scid,
      vcid: vcid,
      frame_length: frame_length,
      frame_seq: frame_seq,
      payload: payload
    }

    with :ok <- validate_version(version),
         :ok <- validate_flag(bypass_flag, :bypass_flag),
         :ok <- validate_flag(control_command_flag, :control_command_flag),
         :ok <- validate_frame_type(bypass_flag, control_command_flag),
         :ok <- validate_spare(spare),
         :ok <- validate_data_field(payload) do
      {:ok, frame}
    end
  end

  defp decode_frame_body(_frame), do: {:error, :invalid_frame}

  defp decode_frames(buffer, _maximum_frame_size, _fecf?, acc)
       when byte_size(buffer) < @primary_header_size do
    {:ok, Enum.reverse(acc), buffer}
  end

  defp decode_frames(
         <<_prefix::22, frame_length::10, _frame_seq::8, _rest::binary>> = buffer,
         maximum_frame_size,
         fecf?,
         acc
       ) do
    frame_size = frame_length + 1

    cond do
      frame_size <= @primary_header_size ->
        {:error, {:frame_too_short, frame_size}}

      frame_size > maximum_frame_size ->
        {:error, {:frame_size_exceeds_managed_maximum, frame_size, maximum_frame_size}}

      byte_size(buffer) < frame_size ->
        {:ok, Enum.reverse(acc), buffer}

      true ->
        <<frame_binary::binary-size(^frame_size), rest::binary>> = buffer

        case decode_frame(frame_binary, fecf?) do
          {:ok, frame} -> decode_frames(rest, maximum_frame_size, fecf?, [frame | acc])
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp normalize_payload(%__MODULE__{} = frame, maximum_frame_size, fecf_size) do
    max_payload = maximum_frame_size - @primary_header_size - fecf_size
    payload = frame.payload || <<>>
    payload_size = byte_size(payload)

    cond do
      payload_size == 0 ->
        {:error, :empty_data_field}

      payload_size > max_payload ->
        {:error, {:data_field_too_large, payload_size, max_payload}}

      true ->
        actual_frame_length = @primary_header_size + payload_size + fecf_size - 1

        case frame.frame_length do
          nil ->
            {:ok, payload, actual_frame_length}

          ^actual_frame_length ->
            {:ok, payload, actual_frame_length}

          configured ->
            {:error, {:invalid_frame_length, configured, actual_frame_length}}
        end
    end
  end

  defp validate_header_fields(%__MODULE__{} = frame, frame_length, maximum_frame_size) do
    fields = %{
      version: frame.version || 0,
      bypass_flag: frame.bypass_flag || 0,
      control_command_flag: frame.control_command_flag || 0,
      spare: frame.spare || 0,
      scid: frame.scid,
      vcid: frame.vcid,
      frame_seq: frame.frame_seq || 0,
      frame_length: frame_length
    }

    with :ok <- validate_version(fields.version),
         :ok <- validate_frame_length(fields.frame_length, maximum_frame_size),
         :ok <- validate_flag(fields.bypass_flag, :bypass_flag),
         :ok <- validate_flag(fields.control_command_flag, :control_command_flag),
         :ok <- validate_frame_type(fields.bypass_flag, fields.control_command_flag),
         :ok <- validate_spare(fields.spare),
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
       fields.spare::2,
       fields.scid::10,
       fields.vcid::6,
       fields.frame_length::10,
       fields.frame_seq::8
     >>}
  end

  defp validate_maximum_frame_size(frame_size, fecf_size)
       when is_integer(frame_size) and frame_size > @primary_header_size + fecf_size and
              frame_size <= @maximum_frame_size,
       do: :ok

  defp validate_maximum_frame_size(frame_size, _fecf_size),
    do: {:error, {:invalid_maximum_frame_size, frame_size}}

  defp validate_version(0), do: :ok
  defp validate_version(value), do: {:error, {:unsupported_version, value}}

  defp validate_frame_length(frame_length, maximum_frame_size) do
    if frame_length + 1 <= maximum_frame_size do
      :ok
    else
      {:error, {:frame_size_exceeds_managed_maximum, frame_length + 1, maximum_frame_size}}
    end
  end

  defp validate_flag(value, _field) when value in [0, 1], do: :ok
  defp validate_flag(value, field), do: {:error, {:invalid_flag, field, value}}

  defp validate_frame_type(0, 1), do: {:error, :reserved_frame_type}
  defp validate_frame_type(_bypass_flag, _control_command_flag), do: :ok

  defp validate_spare(0), do: :ok
  defp validate_spare(value), do: {:error, {:reserved_spare_not_zero, value}}

  defp validate_data_field(<<>>), do: {:error, :empty_data_field}
  defp validate_data_field(_payload), do: :ok

  defp validate_and_strip_fecf(frame, true), do: FrameErrorControl.validate_and_strip(frame)
  defp validate_and_strip_fecf(frame, false), do: {:ok, frame, nil}

  defp fecf_length_bytes(true), do: FrameErrorControl.size()
  defp fecf_length_bytes(false), do: 0
  defp fecf_length_bytes(_other), do: 0

  defp validate_fecf_presence(value) when is_boolean(value), do: :ok
  defp validate_fecf_presence(value), do: {:error, {:invalid_fecf_presence, value}}

  defp validate_range(nil, _min, _max, field), do: {:error, {:missing_field, field}}

  defp validate_range(value, min, max, _field)
       when is_integer(value) and value >= min and value <= max,
       do: :ok

  defp validate_range(value, _min, _max, field), do: {:error, {:invalid_field, field, value}}
end
