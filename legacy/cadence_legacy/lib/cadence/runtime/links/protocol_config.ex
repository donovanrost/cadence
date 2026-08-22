defmodule Cadence.Runtime.Links.ProtocolConfig do
  @moduledoc """
  Normalizes protocol configuration for link/channel runtime usage.
  """

  alias Cadence.Runtime.Interfaces.SDLPConfig
  alias Cadence.Runtime.Transport.COP1.Config, as: COP1Config

  @type t :: %{
          required(:cop1) => map(),
          required(:sdlp) => {:ok, %{mapping: term(), opts: keyword()}} | :error,
          required(:cop1_report_apids) => [non_neg_integer()]
        }

  @spec normalize(map()) :: t()
  def normalize(config) when is_map(config) do
    config = drop_transport_id(config)
    cop1 = COP1Config.config(config)

    %{
      cop1: cop1,
      sdlp: SDLPConfig.fetch(config),
      cop1_report_apids: report_apids_from_cop1(cop1)
    }
  end

  @spec effective_config(map() | nil, map() | nil, keyword()) :: t()
  def effective_config(defaults, overrides, opts \\ [])
      when is_map(defaults) or is_map(overrides) do
    merged = effective_raw_config(defaults || %{}, overrides || %{})
    config = normalize(merged)
    bind_scid(config, Keyword.get(opts, :scid))
  end

  @spec effective_raw_config(map(), map()) :: map()
  def effective_raw_config(defaults, overrides) when is_map(defaults) and is_map(overrides) do
    deep_merge(defaults, overrides)
  end

  defp report_apids_from_cop1(config) when is_map(config) do
    apids = fetch_value(config, ["report_apids", :report_apids, "report_apid", :report_apid])

    normalize_apids(apids)
  end

  defp report_apids_from_cop1(_), do: []

  defp normalize_apids(nil), do: []

  defp normalize_apids(apids) when is_list(apids) do
    apids
    |> Enum.map(&parse_integer/1)
    |> Enum.filter(&is_integer/1)
  end

  defp normalize_apids(value) do
    case parse_integer(value) do
      nil -> []
      apid -> [apid]
    end
  end

  defp fetch_value(config, keys) when is_list(keys) do
    Enum.find_value(keys, fn key -> Map.get(config, key) end)
  end

  defp parse_integer(nil), do: nil
  defp parse_integer(value) when is_integer(value), do: value

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp parse_integer(_), do: nil

  defp deep_merge(defaults, overrides) when is_map(defaults) and is_map(overrides) do
    Map.merge(defaults, overrides, fn _key, default_val, override_val ->
      cond do
        is_nil(override_val) ->
          default_val

        is_map(default_val) and is_map(override_val) ->
          deep_merge(default_val, override_val)

        true ->
          override_val
      end
    end)
  end

  defp drop_transport_id(config) when is_map(config) do
    config
    |> Map.delete(:transport_id)
    |> Map.delete("transport_id")
  end

  defp bind_scid(config, scid) when is_integer(scid) do
    case Map.get(config, :sdlp) do
      {:ok, %{mapping: mapping} = sdlp} ->
        %{config | sdlp: {:ok, %{sdlp | mapping: bind_mapping_scid(mapping, scid)}}}

      _ ->
        config
    end
  end

  defp bind_scid(config, _scid), do: config

  defp bind_mapping_scid(%Cadence.CCSDS.SDU.Mapping{} = mapping, scid) do
    entries =
      mapping.entries
      |> Enum.reduce(%{}, fn
        {{nil, vcid, map_id, direction}, sdu_type}, acc ->
          Map.put_new(acc, {scid, vcid, map_id, direction}, sdu_type)

        {key, sdu_type}, acc ->
          Map.put(acc, key, sdu_type)
      end)

    %Cadence.CCSDS.SDU.Mapping{mapping | entries: entries}
  end
end
