defmodule Cadence.Catalog.SpacecraftConfigurationInput do
  @moduledoc "Finite editable inputs for the onboard computer configuration workspace."

  @fields ~w(catalog_revision_id telemetry_enabled commanding_enabled telemetry_source_endpoint_id handled_apids protocol)
  @protocol_fields ~w(downlink uplink frame_size secondary_header_length insert_zone_length ocf_length truncated_primary_header)

  def empty do
    %{
      "catalog_revision_id" => nil,
      "telemetry_enabled" => false,
      "commanding_enabled" => false,
      "telemetry_source_endpoint_id" => nil,
      "handled_apids" => [],
      "protocol" => nil
    }
  end

  def decode(input) when is_map(input) and map_size(input) == length(@fields) do
    with true <- Enum.sort(Map.keys(input)) == Enum.sort(@fields),
         true <- reference?(input["catalog_revision_id"]),
         true <- reference?(input["telemetry_source_endpoint_id"]),
         true <- is_boolean(input["telemetry_enabled"]),
         true <- is_boolean(input["commanding_enabled"]),
         true <- apids?(input["handled_apids"]),
         true <- protocol?(input["protocol"]) do
      {:ok, Map.update!(input, "handled_apids", &Enum.sort/1)}
    else
      _ -> {:error, :invalid_spacecraft_configuration}
    end
  end

  def decode(_), do: {:error, :invalid_spacecraft_configuration}

  def from_profile(nil), do: nil

  def from_profile(profile) do
    %{
      "downlink" => to_string(profile.downlink_protocol),
      "uplink" => to_string(profile.uplink_protocol),
      "frame_size" => profile.frame_parameters["frame_size"] || 1115,
      "secondary_header_length" => profile.frame_parameters["secondary_header_length"] || 0,
      "insert_zone_length" => profile.frame_parameters["insert_zone_length"] || 0,
      "ocf_length" => profile.frame_parameters["ocf_length"] || 0,
      "truncated_primary_header" => profile.frame_parameters["truncated_primary_header"] || false
    }
  end

  defp reference?(nil), do: true

  defp reference?(value),
    do: is_binary(value) and byte_size(value) in 1..255 and Cadence.Ids.valid_identifier?(value)

  defp apids?(values) when is_list(values) and length(values) <= 2048,
    do:
      Enum.all?(values, &(is_integer(&1) and &1 in 0..2047)) and
        length(values) == length(Enum.uniq(values))

  defp apids?(_), do: false
  defp protocol?(nil), do: true

  defp protocol?(value) when is_map(value) and map_size(value) == length(@protocol_fields) do
    Enum.sort(Map.keys(value)) == Enum.sort(@protocol_fields) and
      supported_protocols?(value) and
      integer?(value["frame_size"], 1, 65_536) and
      integer?(value["secondary_header_length"], 0, 255) and
      integer?(value["insert_zone_length"], 0, 65_535) and value["ocf_length"] in [0, 4] and
      is_boolean(value["truncated_primary_header"]) and
      value["secondary_header_length"] + value["insert_zone_length"] + value["ocf_length"] <
        value["frame_size"]
  end

  defp protocol?(_), do: false

  defp supported_protocols?(value),
    do: value["downlink"] in ["tm", "aos", "uslp"] and value["uplink"] in ["tc", "uslp"]

  defp integer?(value, minimum, maximum), do: is_integer(value) and value in minimum..maximum
end
