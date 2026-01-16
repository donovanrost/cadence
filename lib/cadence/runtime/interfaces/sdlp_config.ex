defmodule Cadence.Runtime.Interfaces.SDLPConfig do
  @moduledoc """
  Helpers for extracting SDLP config from interface config maps.
  """

  alias Cadence.CCSDS.SDU.Mapping
  alias Cadence.Domain.Interfaces.Entities.Interface

  @spec fetch(Interface.t() | map()) :: {:ok, %{mapping: Mapping.t(), opts: keyword()}} | :error
  def fetch(%Interface{} = interface), do: fetch(interface.config || %{})

  def fetch(config) when is_map(config) do
    case framing_mode(config) do
      :sdlp ->
        sdlp_config = fetch_value(config, "sdlp") || %{}
        build_from_config(sdlp_config)

      _ ->
        :error
    end
  end

  defp framing_mode(config) do
    case fetch_value(config, "framing") do
      "sdlp" -> :sdlp
      :sdlp -> :sdlp
      _ -> :other
    end
  end

  defp build_from_config(config) do
    with {:ok, profile} <- normalize_profile(fetch_value(config, "profile")),
         {:ok, mapping} <- build_mapping(fetch_value(config, "sdu_mapping")),
         {:ok, default_sdu_type} <-
           normalize_optional_sdu_type(fetch_value(config, "default_sdu_type")) do
      mapping = %Mapping{mapping | default: default_sdu_type}

      opts =
        [
          profile: profile,
          frame_size: fetch_value(config, "frame_size"),
          secondary_header_length: fetch_value(config, "secondary_header_length"),
          ocf_length: fetch_value(config, "ocf_length"),
          oid_validation: fetch_value(config, "oid_validation"),
          oid_validation_prefix_bytes: fetch_value(config, "oid_validation_prefix_bytes"),
          scid_target_map: normalize_scid_target_map(fetch_value(config, "scid_target_map")),
          default_target_id: fetch_value(config, "default_target_id"),
          vcid_target_map: normalize_vcid_target_map(fetch_value(config, "vcid_target_map")),
          default_vcid_map: normalize_vcid_map(fetch_value(config, "default_vcid_map")),
          uplink_scid: fetch_value(config, "uplink_scid"),
          uplink_vcid: fetch_value(config, "uplink_vcid"),
          uplink_map_id: fetch_value(config, "uplink_map_id"),
          default_sdu_type: default_sdu_type
        ]
        |> Enum.reject(fn {_key, value} -> is_nil(value) end)

      {:ok, %{mapping: mapping, opts: opts}}
    else
      _ -> :error
    end
  end

  defp fetch_value(config, key) when is_map(config) do
    Map.get(config, key) || Map.get(config, String.to_atom(key))
  rescue
    _ -> Map.get(config, key)
  end

  defp normalize_profile(profile) when profile in [:tm, :aos, :uslp], do: {:ok, profile}
  defp normalize_profile("tm"), do: {:ok, :tm}
  defp normalize_profile("aos"), do: {:ok, :aos}
  defp normalize_profile("uslp"), do: {:ok, :uslp}
  defp normalize_profile(_), do: {:error, :invalid_profile}

  defp build_mapping(mapping) when is_list(mapping) do
    entries =
      Enum.reduce(mapping, %{}, fn entry, acc ->
        case normalize_mapping_entry(entry) do
          {:ok, key, sdu_type} -> Map.put(acc, key, sdu_type)
          :error -> acc
        end
      end)

    {:ok, Mapping.new(entries)}
  end

  defp build_mapping(%Mapping{} = mapping), do: {:ok, mapping}

  defp build_mapping(mapping) when is_map(mapping) do
    entries =
      Enum.reduce(mapping, %{}, fn
        {key, value}, acc when is_tuple(key) and tuple_size(key) == 4 ->
          case normalize_sdu_type(value) do
            {:ok, sdu_type} -> Map.put(acc, key, sdu_type)
            _ -> acc
          end

        {_key, _value}, acc ->
          acc
      end)

    {:ok, Mapping.new(entries)}
  end

  defp build_mapping(_), do: {:error, :invalid_mapping}

  defp normalize_mapping_entry(entry) when is_map(entry) do
    scid = parse_integer(Map.get(entry, "scid") || Map.get(entry, :scid))
    vcid = parse_integer(Map.get(entry, "vcid") || Map.get(entry, :vcid))
    map_id = parse_integer(Map.get(entry, "map_id") || Map.get(entry, :map_id))
    direction = normalize_direction(Map.get(entry, "direction") || Map.get(entry, :direction))
    sdu_type_value = Map.get(entry, "type") || Map.get(entry, :type)
    custom_name = Map.get(entry, "name") || Map.get(entry, :name)
    custom_version = Map.get(entry, "version") || Map.get(entry, :version)

    with {:ok, scid} <- require_integer(scid),
         {:ok, vcid} <- require_integer(vcid),
         {:ok, direction} <- require_direction(direction),
         {:ok, sdu_type} <- normalize_sdu_type(sdu_type_value, custom_name, custom_version) do
      {:ok, {scid, vcid, map_id, direction}, sdu_type}
    else
      _ -> :error
    end
  end

  defp normalize_mapping_entry(_), do: :error

  defp normalize_direction(nil), do: :downlink
  defp normalize_direction(:downlink), do: :downlink
  defp normalize_direction(:uplink), do: :uplink
  defp normalize_direction("downlink"), do: :downlink
  defp normalize_direction("uplink"), do: :uplink
  defp normalize_direction(_), do: :invalid

  defp require_direction(:invalid), do: {:error, :invalid_direction}
  defp require_direction(direction), do: {:ok, direction}

  defp normalize_optional_sdu_type(nil), do: {:ok, nil}
  defp normalize_optional_sdu_type(value), do: normalize_sdu_type(value)

  defp normalize_sdu_type("space_packet"), do: {:ok, :space_packet}
  defp normalize_sdu_type("encap"), do: {:ok, :encap}
  defp normalize_sdu_type(:space_packet), do: {:ok, :space_packet}
  defp normalize_sdu_type(:encap), do: {:ok, :encap}

  defp normalize_sdu_type(value) when is_binary(value) do
    case String.split(value, ":") do
      ["custom", name, version] ->
        case Integer.parse(version) do
          {int, ""} -> {:ok, {:custom, name, int}}
          _ -> {:error, :invalid_custom_version}
        end

      _ ->
        {:error, :invalid_sdu_type}
    end
  end

  defp normalize_sdu_type(value, name, version) when value in ["custom", :custom] do
    with {:ok, name} <- require_string(name),
         {:ok, version} <- require_integer(parse_integer(version)) do
      {:ok, {:custom, name, version}}
    end
  end

  defp normalize_sdu_type(value, _name, _version), do: normalize_sdu_type(value)

  defp require_integer(nil), do: {:error, :invalid_integer}
  defp require_integer(value) when is_integer(value), do: {:ok, value}
  defp require_integer(_), do: {:error, :invalid_integer}

  defp require_string(value) when is_binary(value) and value != "", do: {:ok, value}
  defp require_string(_), do: {:error, :invalid_string}

  # Normalize scid_target_map: convert string keys to integers
  # Input: %{"1" => "SAT-1", "2" => "SAT-2"} or %{1 => "SAT-1"}
  # Output: %{1 => "SAT-1", 2 => "SAT-2"}
  defp normalize_scid_target_map(nil), do: nil

  defp normalize_scid_target_map(map) when is_map(map) do
    Map.new(map, fn {key, value} ->
      {to_integer_key(key), value}
    end)
  end

  defp normalize_scid_target_map(_), do: nil

  # Normalize vcid_target_map: convert both scid and vcid string keys to integers
  # Input: %{"1" => %{"0" => %{...}}} (scid => vcid => metadata)
  # Output: %{1 => %{0 => %{...}}}
  defp normalize_vcid_target_map(nil), do: nil

  defp normalize_vcid_target_map(map) when is_map(map) do
    Map.new(map, fn {scid_key, vcid_map} ->
      normalized_vcid_map =
        if is_map(vcid_map) do
          normalize_vcid_map(vcid_map)
        else
          vcid_map
        end

      {to_integer_key(scid_key), normalized_vcid_map}
    end)
  end

  defp normalize_vcid_target_map(_), do: nil

  # Normalize vcid map (vcid => metadata)
  defp normalize_vcid_map(nil), do: nil

  defp normalize_vcid_map(map) when is_map(map) do
    Map.new(map, fn {vcid_key, metadata} ->
      {to_integer_key(vcid_key), metadata}
    end)
  end

  defp normalize_vcid_map(_), do: nil

  # Convert a key to integer if it's a string representation of an integer
  defp to_integer_key(key) when is_integer(key), do: key

  defp to_integer_key(key) when is_binary(key) do
    case Integer.parse(key) do
      {int, ""} -> int
      _ -> key
    end
  end

  defp to_integer_key(key), do: key

  defp parse_integer(nil), do: nil
  defp parse_integer(value) when is_integer(value), do: value

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp parse_integer(_), do: nil
end
