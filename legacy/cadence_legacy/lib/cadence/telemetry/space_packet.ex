defmodule Cadence.Telemetry.SpacePacket do
  @moduledoc """
  Minimal CCSDS Space Packet representation.
  """

  @type primary_header :: %{
          version: non_neg_integer(),
          type: non_neg_integer(),
          sec_hdr_flag: non_neg_integer(),
          apid: non_neg_integer(),
          seq_flags: non_neg_integer(),
          seq_count: non_neg_integer(),
          length: non_neg_integer()
        }

  @type raw_ref :: %{offset: non_neg_integer(), length: non_neg_integer()}

  @type t :: %__MODULE__{
          primary: primary_header,
          sec_header: binary() | nil,
          user_data: binary(),
          raw_ref: raw_ref | nil
        }

  defstruct [:primary, :sec_header, :user_data, :raw_ref]

  @spec parse(binary()) :: {:ok, t()} | {:error, term()}
  def parse(raw) when is_binary(raw) do
    size = byte_size(raw)

    if size < 6 do
      {:error, {:malformed, :insufficient_data, %{required: 6, actual: size}}}
    else
      <<
        version::3,
        type::1,
        sec_hdr_flag::1,
        apid::11,
        seq_flags::2,
        seq_count::14,
        length::16,
        rest::binary
      >> = raw

      header = %{
        version: version,
        type: type,
        sec_hdr_flag: sec_hdr_flag,
        apid: apid,
        seq_flags: seq_flags,
        seq_count: seq_count,
        length: length
      }

      parse_with_header(size, rest, header)
    end
  end

  defp parse_with_header(size, rest, header) do
    if header.version != 0 do
      {:error, {:no_match, :invalid_version, %{version: header.version}}}
    else
      data_length = header.length + 1
      expected_total = 6 + data_length

      with {:ok, data_field} <- split_data_field(size, rest, data_length, expected_total),
           {:ok, sec_header, user_data} <- split_secondary_header(header.sec_hdr_flag, data_field) do
        {:ok,
         %__MODULE__{
           primary: header,
           sec_header: sec_header,
           user_data: user_data,
           raw_ref: %{offset: 6, length: data_length}
         }}
      else
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp split_data_field(size, rest, data_length, expected_total) do
    if size < expected_total do
      {:error, {:malformed, :packet_length_mismatch, %{expected: expected_total, actual: size}}}
    else
      <<data_field::binary-size(data_length), _trailer::binary>> = rest
      {:ok, data_field}
    end
  end

  defp split_secondary_header(1, data_field) do
    if byte_size(data_field) >= 8 do
      <<sec_header::binary-size(8), user_data::binary>> = data_field
      {:ok, sec_header, user_data}
    else
      {:error,
       {:malformed, :missing_secondary_header, %{required: 8, actual: byte_size(data_field)}}}
    end
  end

  defp split_secondary_header(_, data_field), do: {:ok, nil, data_field}

  @spec get_apid(t()) :: non_neg_integer()
  def get_apid(%__MODULE__{primary: %{apid: apid}}), do: apid
end
