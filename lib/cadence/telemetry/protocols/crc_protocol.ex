defmodule Cadence.Telemetry.Protocols.CRCProtocol do
  @moduledoc """
  CRC validation protocol for packet integrity checking.

  This protocol validates incoming packets by checking their CRC trailer
  and appends CRC trailers to outgoing packets. It supports multiple
  CRC algorithms and configurable failure handling.

  ## Configuration

  - `algorithm` - CRC algorithm to use (default: `:crc16_ccitt`)
    - `:crc32` - CRC-32 (Ethernet, ZIP)
    - `:crc16_ccitt` - CRC-16-CCITT (CCSDS, X.25)
    - `:crc16_xmodem` - CRC-16-XMODEM
    - `:crc8` - CRC-8
    - `:xor_checksum` - Simple XOR checksum

  - `endian` - Byte order of CRC in packet (default: `:big`)
    - `:big` - Big-endian (network byte order)
    - `:little` - Little-endian

  - `on_failure` - How to handle CRC validation failures (default: `:skip`)
    - `:disconnect` - Return `{:disconnect, reason}` to trigger reconnect
    - `:skip` - Log warning, don't return packet, continue processing
    - `:pass` - Log warning, return packet anyway with `:crc_invalid` flag

  ## Protocol Chain Position

  The CRC protocol should typically be placed after the deframing protocol
  (e.g., TemplateProtocol) so it receives complete packets with CRC trailers.

  ```
  Read chain:  [TemplateProtocol] → [CRCProtocol] → validated packets
  Write chain: [CRCProtocol] → [TemplateProtocol] → framed packets with CRC
  ```

  ## Example Configuration

      %{
        "algorithm" => "crc16_ccitt",
        "endian" => "big",
        "on_failure" => "skip"
      }

  ## CCSDS Usage

  For CCSDS packets with CRC-16-CCITT:

      %{
        "algorithm" => "crc16_ccitt",
        "endian" => "big",
        "on_failure" => "skip"
      }
  """

  use Cadence.Telemetry.Protocol

  require Logger

  alias Cadence.Telemetry.CRC

  @supported_algorithms [:crc32, :crc16_ccitt, :crc16_xmodem, :crc8, :xor_checksum]
  @supported_on_failure [:disconnect, :skip, :pass]

  defstruct [
    :algorithm,
    :endian,
    :on_failure,
    :crc_size,
    packets_validated: 0,
    packets_failed: 0
  ]

  @doc """
  Creates a new CRC protocol state.

  ## Options

  - `:algorithm` - CRC algorithm (default: `:crc16_ccitt`)
  - `:endian` - Byte order (default: `:big`)
  - `:on_failure` - Failure handling (default: `:skip`)
  """
  def new(opts \\ []) do
    algorithm = normalize_algorithm(Keyword.get(opts, :algorithm, :crc16_ccitt))
    endian = normalize_endian(Keyword.get(opts, :endian, :big))
    on_failure = normalize_on_failure(Keyword.get(opts, :on_failure, :skip))

    unless algorithm in @supported_algorithms do
      raise ArgumentError,
            "Unsupported CRC algorithm: #{inspect(algorithm)}. " <>
              "Supported: #{inspect(@supported_algorithms)}"
    end

    %__MODULE__{
      algorithm: algorithm,
      endian: endian,
      on_failure: on_failure,
      crc_size: CRC.size(algorithm)
    }
  end

  @doc """
  Validates CRC on incoming packets and strips the CRC trailer.

  Returns:
  - `{:ok, [validated_packets], state}` - Packets with valid CRC
  - `{:stop, state}` - Waiting for more data (shouldn't happen for CRC)
  - `{:disconnect, reason}` - CRC failure with `:disconnect` mode
  """
  def read_data(data, state) when byte_size(data) <= state.crc_size do
    # Packet too small to contain CRC
    Logger.warning("CRC protocol received packet smaller than CRC size: #{byte_size(data)} bytes")
    {:ok, [], state}
  end

  def read_data(data, state) do
    case CRC.verify(data, state.algorithm, state.endian) do
      {:ok, validated_data} ->
        new_state = %{state | packets_validated: state.packets_validated + 1}
        {:ok, [validated_data], new_state}

      {:error, {:crc_mismatch, expected, actual}} ->
        handle_crc_failure(state, expected, actual, data)

      {:error, :insufficient_data} ->
        Logger.warning("CRC protocol received insufficient data")
        {:ok, [], state}
    end
  end

  @doc """
  Appends CRC trailer to outgoing packets.
  """
  def write_data(data, state) do
    crc = CRC.calculate(state.algorithm, data)
    crc_bytes = CRC.encode(crc, state.algorithm, state.endian)
    {:ok, [data <> crc_bytes], state}
  end

  @doc """
  Returns `:raw` since CRC validation doesn't change the packet format.
  """
  def packet_format, do: :raw

  ## Private Functions

  defp handle_crc_failure(state, expected, actual, data) do
    new_state = %{state | packets_failed: state.packets_failed + 1}

    case state.on_failure do
      :disconnect ->
        {:disconnect,
         "CRC mismatch: expected 0x#{Integer.to_string(expected, 16)}, " <>
           "got 0x#{Integer.to_string(actual, 16)}"}

      :skip ->
        Logger.warning(
          "CRC mismatch (skipping packet): expected 0x#{Integer.to_string(expected, 16)}, " <>
            "got 0x#{Integer.to_string(actual, 16)}, packet_size=#{byte_size(data)}"
        )

        {:ok, [], new_state}

      :pass ->
        Logger.warning(
          "CRC mismatch (passing packet): expected 0x#{Integer.to_string(expected, 16)}, " <>
            "got 0x#{Integer.to_string(actual, 16)}, packet_size=#{byte_size(data)}"
        )

        # Strip CRC and return data anyway
        data_size = byte_size(data) - state.crc_size
        <<validated_data::binary-size(data_size), _crc::binary>> = data
        {:ok, [validated_data], new_state}
    end
  end

  defp normalize_algorithm(algorithm) when is_atom(algorithm), do: algorithm

  defp normalize_algorithm(algorithm) when is_binary(algorithm) do
    case algorithm do
      "crc32" -> :crc32
      "crc16_ccitt" -> :crc16_ccitt
      "crc16-ccitt" -> :crc16_ccitt
      "crc16_xmodem" -> :crc16_xmodem
      "crc16-xmodem" -> :crc16_xmodem
      "crc8" -> :crc8
      "xor_checksum" -> :xor_checksum
      "xor" -> :xor_checksum
      _ -> String.to_atom(algorithm)
    end
  end

  defp normalize_endian(endian) when endian in [:big, :little], do: endian
  defp normalize_endian("big"), do: :big
  defp normalize_endian("little"), do: :little
  defp normalize_endian(_), do: :big

  defp normalize_on_failure(on_failure) when on_failure in @supported_on_failure, do: on_failure
  defp normalize_on_failure("disconnect"), do: :disconnect
  defp normalize_on_failure("skip"), do: :skip
  defp normalize_on_failure("pass"), do: :pass
  defp normalize_on_failure(_), do: :skip
end
