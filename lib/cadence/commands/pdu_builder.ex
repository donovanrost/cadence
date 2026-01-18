defmodule Cadence.Commands.PDUBuilder do
  @moduledoc """
  Builds CCSDS PDUs for command uplink.

  Commands are encoded into a Space Packet PDU with per-target APID selection.
  """

  alias Cadence.CCSDS.Core.PDU
  alias Cadence.CCSDS.SDU.SpacePacket

  @max_apid 2047

  @spec build(binary(), map(), map()) :: {:ok, PDU.t()} | {:error, term()}
  def build(encoded, target, meta \\ %{}) when is_binary(encoded) and is_map(target) do
    with {:ok, apid} <- command_apid(target) do
      timestamp = DateTime.utc_now()

      packet = %SpacePacket{
        apid: apid,
        type: 1,
        version: 0,
        secondary_header_flag: 1,
        sequence_flags: 3,
        sequence_count: nil,
        timestamp: timestamp,
        target_hash: 0,
        user_data: encoded
      }

      {:ok,
       %PDU{
         type: :space_packet,
         value: packet,
         quality: :good,
         timestamp: timestamp,
         meta: meta
       }}
    end
  end

  defp command_apid(target) do
    target
    |> fetch_config_value("command_apid")
    |> normalize_apid()
  end

  defp normalize_apid(nil), do: {:error, :missing_command_apid}

  defp normalize_apid(apid) when is_integer(apid) do
    validate_apid(apid, apid)
  end

  defp normalize_apid(apid) when is_binary(apid) do
    case Integer.parse(apid) do
      {value, ""} -> validate_apid(value, apid)
      _ -> {:error, {:invalid_command_apid, apid}}
    end
  end

  defp normalize_apid(apid), do: {:error, {:invalid_command_apid, apid}}

  defp validate_apid(value, _raw) when value >= 0 and value <= @max_apid, do: {:ok, value}
  defp validate_apid(_value, raw), do: {:error, {:invalid_command_apid, raw}}

  defp fetch_config_value(%{config: config}, key) when is_map(config) do
    Map.get(config, key) || Map.get(config, String.to_atom(key))
  rescue
    _ -> Map.get(config, key)
  end

  defp fetch_config_value(_, _key), do: nil
end
