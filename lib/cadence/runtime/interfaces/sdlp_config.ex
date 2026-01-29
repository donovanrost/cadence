defmodule Cadence.Runtime.Interfaces.SDLPConfig do
  @moduledoc """
  Helpers for extracting SDLP config from interface config maps.
  """

  alias Cadence.CCSDS.SDU.Mapping
  @type segmentation_mode :: :standard | :legacy_no_segment_header | :legacy_always_segment_header
  @type segmentation_strategy :: :auto | :disabled

  @type segmentation_config :: %{
          optional(:strategy) => segmentation_strategy(),
          optional(:mode) => segmentation_mode(),
          optional(:max_segments_per_command) => pos_integer(),
          optional(:max_command_bytes) => pos_integer()
        }

  @type tc_config :: %{
          optional(:default_scid) => non_neg_integer(),
          optional(:default_vcid) => non_neg_integer(),
          optional(:max_frame_bytes) => pos_integer(),
          optional(:segmentation) => segmentation_config()
        }

  @type uslp_config :: %{
          optional(:default_scid) => non_neg_integer(),
          optional(:default_vcid) => non_neg_integer(),
          optional(:default_map_id) => non_neg_integer(),
          optional(:max_frame_bytes) => pos_integer(),
          optional(:map) => map(),
          optional(:segmentation) => segmentation_config()
        }

  @spec fetch(map()) :: {:ok, %{mapping: Mapping.t(), opts: keyword()}} | :error
  def fetch(config) when is_map(config) do
    case framing_mode(config) do
      :sdlp ->
        sdlp_config = fetch_value(config, "sdlp") || %{}
        tc_config = fetch_value(config, "tc") || %{}
        uslp_config = fetch_value(config, "uslp") || %{}
        cop1_config = fetch_value(config, "cop1") || %{}
        build_from_config(sdlp_config, tc_config, uslp_config, cop1_config)

      _ ->
        :error
    end
  end

  @doc """
  Extracts TC-specific configuration including segmentation settings.
  Returns tc_config with derived segment_header_flag based on segmentation mode.
  """
  @spec fetch_tc_config(map()) :: {:ok, tc_config()} | :error
  def fetch_tc_config(config) when is_map(config) do
    tc_config = fetch_value(config, "tc") || %{}
    cop1_config = fetch_value(config, "cop1") || %{}
    sdlp_config = fetch_value(config, "sdlp") || %{}

    {:ok, build_tc_config(tc_config, cop1_config, sdlp_config)}
  end

  @doc """
  Extracts USLP-specific configuration including MAP settings.
  """
  @spec fetch_uslp_config(map()) :: {:ok, uslp_config()} | :error
  def fetch_uslp_config(config) when is_map(config) do
    uslp_config = fetch_value(config, "uslp") || %{}
    {:ok, build_uslp_config(uslp_config)}
  end

  @doc """
  Derives the segment_header_flag from segmentation mode.
  - :standard → 1 (segment header present)
  - :legacy_no_segment_header → 0 (no segment header)
  - :legacy_always_segment_header → 1 (segment header present)
  """
  @spec segment_header_flag_from_mode(segmentation_mode()) :: 0 | 1
  def segment_header_flag_from_mode(:standard), do: 1
  def segment_header_flag_from_mode(:legacy_no_segment_header), do: 0
  def segment_header_flag_from_mode(:legacy_always_segment_header), do: 1
  def segment_header_flag_from_mode(_), do: 1

  defp framing_mode(config) do
    case fetch_value(config, "framing") do
      "sdlp" -> :sdlp
      :sdlp -> :sdlp
      _ -> :other
    end
  end

  defp build_from_config(sdlp_config, tc_config, uslp_config, cop1_config) do
    with {:ok, profile} <- normalize_profile(fetch_value(sdlp_config, "profile")),
         {:ok, uplink_profile} <-
           normalize_uplink_profile(fetch_value(sdlp_config, "uplink_profile"), profile),
         {:ok, mapping} <- build_mapping(fetch_value(sdlp_config, "sdu_mapping")),
         {:ok, default_sdu_type} <-
           normalize_optional_sdu_type(fetch_value(sdlp_config, "default_sdu_type")) do
      mapping = %Mapping{mapping | default: default_sdu_type}

      # Build segmentation config from tc/uslp config, with cop1 backward compat
      segmentation =
        build_segmentation_config(tc_config, uslp_config, cop1_config, uplink_profile)

      # Get defaults from new tc/uslp config, falling back to sdlp_config for backward compat
      uplink_map_id =
        fetch_value(uslp_config, "default_map_id") ||
          fetch_value(sdlp_config, "uplink_map_id")

      max_frame_bytes =
        fetch_value(tc_config, "max_frame_bytes") ||
          fetch_value(uslp_config, "max_frame_bytes") ||
          fetch_value(sdlp_config, "uplink_frame_size")

      opts =
        [
          profile: profile,
          uplink_profile: uplink_profile,
          frame_size: fetch_value(sdlp_config, "frame_size"),
          uplink_frame_size: max_frame_bytes,
          secondary_header_length: fetch_value(sdlp_config, "secondary_header_length"),
          ocf_length: fetch_value(sdlp_config, "ocf_length"),
          oid_validation: fetch_value(sdlp_config, "oid_validation"),
          oid_validation_prefix_bytes: fetch_value(sdlp_config, "oid_validation_prefix_bytes"),
          scid_target_map: normalize_scid_target_map(fetch_value(sdlp_config, "scid_target_map")),
          default_target_id: fetch_value(sdlp_config, "default_target_id"),
          vcid_target_map: normalize_vcid_target_map(fetch_value(sdlp_config, "vcid_target_map")),
          default_vcid_map: normalize_vcid_map(fetch_value(sdlp_config, "default_vcid_map")),
          uplink_map_id: uplink_map_id,
          default_sdu_type: default_sdu_type,
          segmentation: segmentation
        ]
        |> Enum.reject(fn {_key, value} -> is_nil(value) end)

      {:ok, %{mapping: mapping, opts: opts}}
    else
      _ -> :error
    end
  end

  defp build_tc_config(tc_config, cop1_config, sdlp_config) do
    segmentation_config = fetch_value(tc_config, "segmentation") || %{}
    mode = normalize_segmentation_mode(fetch_value(segmentation_config, "mode"), cop1_config)

    %{
      default_scid:
        fetch_value(tc_config, "default_scid") ||
          fetch_value(sdlp_config, "uplink_scid"),
      default_vcid:
        fetch_value(tc_config, "default_vcid") ||
          fetch_value(sdlp_config, "uplink_vcid"),
      max_frame_bytes:
        fetch_value(tc_config, "max_frame_bytes") ||
          fetch_value(sdlp_config, "uplink_frame_size"),
      segmentation: %{
        strategy: normalize_segmentation_strategy(fetch_value(segmentation_config, "strategy")),
        mode: mode,
        max_segments_per_command: fetch_value(segmentation_config, "max_segments_per_command"),
        max_command_bytes: fetch_value(segmentation_config, "max_command_bytes")
      },
      # Derived flag based on segmentation mode
      segment_header_flag: segment_header_flag_from_mode(mode)
    }
  end

  defp build_uslp_config(uslp_config) do
    segmentation_config = fetch_value(uslp_config, "segmentation") || %{}
    map_config = fetch_value(uslp_config, "map") || %{}
    mode = normalize_segmentation_mode(fetch_value(segmentation_config, "mode"), %{})

    %{
      default_scid: fetch_value(uslp_config, "default_scid"),
      default_vcid: fetch_value(uslp_config, "default_vcid"),
      default_map_id: fetch_value(uslp_config, "default_map_id"),
      max_frame_bytes: fetch_value(uslp_config, "max_frame_bytes"),
      map: %{
        enabled: fetch_value(map_config, "enabled") == true,
        allowed_map_ids: fetch_value(map_config, "allowed_map_ids") || [0]
      },
      segmentation: %{
        strategy: normalize_segmentation_strategy(fetch_value(segmentation_config, "strategy")),
        mode: mode
      },
      segment_header_flag: segment_header_flag_from_mode(mode)
    }
  end

  defp build_segmentation_config(tc_config, uslp_config, cop1_config, uplink_profile) do
    # Try tc_config first, then uslp_config based on uplink profile
    config =
      case uplink_profile do
        :uslp ->
          fetch_value(uslp_config, "segmentation") || fetch_value(tc_config, "segmentation")

        _ ->
          fetch_value(tc_config, "segmentation") || fetch_value(uslp_config, "segmentation")
      end

    config = config || %{}

    mode = normalize_segmentation_mode(fetch_value(config, "mode"), cop1_config)

    %{
      strategy: normalize_segmentation_strategy(fetch_value(config, "strategy")),
      mode: mode,
      max_segments_per_command: fetch_value(config, "max_segments_per_command"),
      max_command_bytes: fetch_value(config, "max_command_bytes"),
      # Derived flag
      segment_header_flag: segment_header_flag_from_mode(mode)
    }
  end

  defp normalize_segmentation_strategy(nil), do: :auto
  defp normalize_segmentation_strategy("auto"), do: :auto
  defp normalize_segmentation_strategy(:auto), do: :auto
  defp normalize_segmentation_strategy("disabled"), do: :disabled
  defp normalize_segmentation_strategy(:disabled), do: :disabled
  defp normalize_segmentation_strategy(_), do: :auto

  defp normalize_segmentation_mode(nil, cop1_config) do
    # Backward compatibility: derive from cop1 segment_header_flag if present
    case fetch_value(cop1_config, "segment_header_flag") do
      flag when flag in [0, "0", false, "false"] -> :legacy_no_segment_header
      flag when flag in [1, "1", true, "true"] -> :standard
      _ -> :standard
    end
  end

  defp normalize_segmentation_mode("standard", _cop1), do: :standard
  defp normalize_segmentation_mode(:standard, _cop1), do: :standard

  defp normalize_segmentation_mode("legacy_no_segment_header", _cop1),
    do: :legacy_no_segment_header

  defp normalize_segmentation_mode(:legacy_no_segment_header, _cop1),
    do: :legacy_no_segment_header

  defp normalize_segmentation_mode("legacy_always_segment_header", _cop1),
    do: :legacy_always_segment_header

  defp normalize_segmentation_mode(:legacy_always_segment_header, _cop1),
    do: :legacy_always_segment_header

  defp normalize_segmentation_mode(_, _cop1), do: :standard

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

  defp normalize_uplink_profile(nil, profile), do: {:ok, profile}

  defp normalize_uplink_profile(profile, _default) when profile in [:tm, :aos, :uslp, :tc],
    do: {:ok, profile}

  defp normalize_uplink_profile("tm", _default), do: {:ok, :tm}
  defp normalize_uplink_profile("aos", _default), do: {:ok, :aos}
  defp normalize_uplink_profile("uslp", _default), do: {:ok, :uslp}
  defp normalize_uplink_profile("tc", _default), do: {:ok, :tc}
  defp normalize_uplink_profile(_profile, _default), do: {:error, :invalid_uplink_profile}

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
        {key, value}, acc when is_tuple(key) and tuple_size(key) in [3, 4] ->
          with {:ok, normalized_key} <- normalize_mapping_key(key),
               {:ok, sdu_type} <- normalize_sdu_type(value) do
            Map.put(acc, normalized_key, sdu_type)
          else
            _ -> acc
          end

        {_key, _value}, acc ->
          acc
      end)

    {:ok, Mapping.new(entries)}
  end

  defp build_mapping(_), do: {:error, :invalid_mapping}

  defp normalize_mapping_key({scid, vcid, map_id, direction}) do
    scid = parse_integer(scid)
    vcid = parse_integer(vcid)
    map_id = parse_integer(map_id)
    direction = normalize_direction(direction)

    with {:ok, vcid} <- require_integer(vcid),
         {:ok, direction} <- require_direction(direction) do
      {:ok, {scid, vcid, map_id, direction}}
    else
      _ -> :error
    end
  end

  defp normalize_mapping_key({vcid, map_id, direction}) do
    vcid = parse_integer(vcid)
    map_id = parse_integer(map_id)
    direction = normalize_direction(direction)

    with {:ok, vcid} <- require_integer(vcid),
         {:ok, direction} <- require_direction(direction) do
      {:ok, {nil, vcid, map_id, direction}}
    else
      _ -> :error
    end
  end

  defp normalize_mapping_key(_), do: :error

  defp normalize_mapping_entry(entry) when is_map(entry) do
    scid = parse_integer(Map.get(entry, "scid") || Map.get(entry, :scid))
    vcid = parse_integer(Map.get(entry, "vcid") || Map.get(entry, :vcid))
    map_id = parse_integer(Map.get(entry, "map_id") || Map.get(entry, :map_id))
    direction = normalize_direction(Map.get(entry, "direction") || Map.get(entry, :direction))
    sdu_type_value = Map.get(entry, "type") || Map.get(entry, :type)
    custom_name = Map.get(entry, "name") || Map.get(entry, :name)
    custom_version = Map.get(entry, "version") || Map.get(entry, :version)

    with {:ok, vcid} <- require_integer(vcid),
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
