defmodule CadenceSimulator.Provider.ServiceProfiles do
  @moduledoc "Provider-owned service profiles exposed by a simulator run."

  alias CadenceSimulator.Provider.Contract

  @directions ["downlink", "uplink", "bidirectional"]
  @states ["active", "inactive"]

  @spec default() :: [map()]
  def default do
    [
      %{
        "id" => "service-realtime-ttc-downlink",
        "version" => 1,
        "display_name" => "Realtime TT&C downlink",
        "service_kind" => "realtime_telemetry",
        "direction" => "downlink",
        "supported_delivery_kinds" => ["realtime_stream"],
        "data_families" => ["ccsds_tm"],
        "minimum_duration_seconds" => 30,
        "state" => "active",
        "extensions" => %{}
      }
    ]
  end

  @spec normalize(term()) :: {:ok, [map()]} | {:error, {:invalid, binary()}}
  def normalize(profiles) when is_list(profiles) do
    profiles
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {profile, index}, {:ok, acc} ->
      case normalize_profile(profile, index) do
        {:ok, normalized} -> {:cont, {:ok, [normalized | acc]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, normalized} -> normalized |> Enum.reverse() |> ensure_unique_ids("service_profiles")
      error -> error
    end
  end

  def normalize(_profiles), do: {:error, {:invalid, "service_profiles must be a list"}}

  @spec for_run(map()) :: [map()]
  def for_run(run), do: get_in(run, ["scenario_snapshot", "service_profiles"]) || default()

  defp normalize_profile(profile, index) when is_map(profile) do
    profile = Contract.sanitize(profile)

    with {:ok, id} <- required_text(profile, "id", index),
         {:ok, display_name} <- required_text(profile, "display_name", index),
         {:ok, direction} <- member(profile, "direction", @directions, "downlink", index),
         {:ok, state} <- member(profile, "state", @states, "active", index),
         {:ok, version} <- positive_integer(profile, "version", 1, index),
         {:ok, minimum_duration} <-
           positive_integer(profile, "minimum_duration_seconds", 30, index),
         {:ok, delivery_kinds} <-
           string_list(
             profile,
             "supported_delivery_kinds",
             ["realtime_stream"],
             index
           ),
         {:ok, data_families} <-
           string_list(profile, "data_families", ["ccsds_tm"], index),
         {:ok, extensions} <- object(profile, "extensions", %{}, index) do
      {:ok,
       %{
         "id" => id,
         "version" => version,
         "display_name" => display_name,
         "service_kind" => Map.get(profile, "service_kind", "realtime_telemetry"),
         "direction" => direction,
         "supported_delivery_kinds" => delivery_kinds,
         "data_families" => data_families,
         "minimum_duration_seconds" => minimum_duration,
         "state" => state,
         "extensions" => extensions
       }}
    end
  end

  defp normalize_profile(_profile, index),
    do: {:error, {:invalid, "service_profiles[#{index}] must be an object"}}

  defp required_text(map, key, index) do
    case map[key] do
      value when is_binary(value) and value != "" -> {:ok, value}
      _other -> {:error, {:invalid, "service_profiles[#{index}].#{key} is required"}}
    end
  end

  defp member(map, key, allowed, default, index) do
    value = Map.get(map, key, default)

    if value in allowed,
      do: {:ok, value},
      else: {:error, {:invalid, "service_profiles[#{index}].#{key} is invalid"}}
  end

  defp positive_integer(map, key, default, index) do
    case Map.get(map, key, default) do
      value when is_integer(value) and value > 0 -> {:ok, value}
      _other -> {:error, {:invalid, "service_profiles[#{index}].#{key} is invalid"}}
    end
  end

  defp string_list(map, key, default, index) do
    case Map.get(map, key, default) do
      values when is_list(values) ->
        if Enum.all?(values, &(is_binary(&1) and &1 != "")),
          do: {:ok, values},
          else: {:error, {:invalid, "service_profiles[#{index}].#{key} is invalid"}}

      _other ->
        {:error, {:invalid, "service_profiles[#{index}].#{key} is invalid"}}
    end
  end

  defp object(map, key, default, index) do
    case Map.get(map, key, default) do
      value when is_map(value) -> {:ok, value}
      _other -> {:error, {:invalid, "service_profiles[#{index}].#{key} is invalid"}}
    end
  end

  defp ensure_unique_ids(profiles, field) do
    ids = Enum.map(profiles, & &1["id"])

    if MapSet.size(MapSet.new(ids)) == length(ids),
      do: {:ok, profiles},
      else: {:error, {:invalid, "#{field} ids must be unique"}}
  end
end
