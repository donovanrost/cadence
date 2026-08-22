defmodule CadenceSimulator.Provider.RouteProfiles do
  @moduledoc """
  Deterministic station/service route controls for fleet and failure scenarios.

  Route profiles let the simulator model a provider-owned exclusive service pool
  without making Cadence aware of simulator administration. They also provide
  bounded request latency, rate-limit responses, and opportunity expiry controls
  for qualification tests.
  """

  alias CadenceSimulator.Provider.{Contract, Store}

  @maximum_latency_ms 5_000
  @maximum_retry_after_seconds 3_600
  @maximum_expiry_offset_seconds 7 * 24 * 60 * 60

  @spec normalize(term(), [map()], [map()]) ::
          {:ok, [map()]} | {:error, {:invalid, binary()}}
  def normalize(profiles, stations, service_profiles)
      when is_list(profiles) and is_list(stations) and is_list(service_profiles) do
    station_ids = MapSet.new(stations, & &1["id"])
    service_profile_ids = MapSet.new(service_profiles, & &1["id"])

    profiles
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {profile, index}, {:ok, acc} ->
      case normalize_profile(profile, index, station_ids, service_profile_ids) do
        {:ok, normalized} -> {:cont, {:ok, [normalized | acc]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, normalized} ->
        normalized
        |> Enum.reverse()
        |> ensure_unique()

      error ->
        error
    end
  end

  def normalize(_profiles, _stations, _service_profiles),
    do: {:error, {:invalid, "route_profiles must be a list"}}

  @spec for_run(map()) :: [map()]
  def for_run(run) when is_map(run),
    do: get_in(run, ["scenario_snapshot", "route_profiles"]) || []

  @spec for_opportunity(map(), binary(), binary()) :: map() | nil
  def for_opportunity(run, station_ref, service_profile_ref) do
    Enum.find(for_run(run), fn profile ->
      profile["ground_station_ref"] == station_ref and
        profile["service_profile_ref"] == service_profile_ref
    end)
  end

  @spec apply_search_control(map(), binary(), [binary()]) ::
          {:ok, map() | nil} | {:error, {:rate_limited, map()}}
  def apply_search_control(run, service_profile_ref, station_refs)
      when is_map(run) and is_binary(service_profile_ref) and is_list(station_refs) do
    profile = search_profile(run, service_profile_ref, station_refs)

    if profile do
      maybe_delay(profile)

      fault_key = "route_rate_limit:#{profile["id"]}"

      if Store.consume_fault(
           run["id"],
           fault_key,
           profile["rate_limit_response_count"]
         ) do
        {:error,
         {:rate_limited,
          %{
            "route_profile_ref" => profile["id"],
            "ground_station_ref" => profile["ground_station_ref"],
            "service_profile_ref" => profile["service_profile_ref"],
            "retry_after_seconds" => profile["retry_after_seconds"]
          }}}
      else
        {:ok, profile}
      end
    else
      {:ok, nil}
    end
  end

  defp search_profile(run, service_profile_ref, station_refs) do
    candidates =
      for_run(run)
      |> Enum.filter(fn profile ->
        profile["service_profile_ref"] == service_profile_ref and station_refs != [] and
          profile["ground_station_ref"] in station_refs
      end)
      |> Enum.sort_by(& &1["id"])

    case candidates do
      [profile] -> profile
      _other -> nil
    end
  end

  defp normalize_profile(profile, index, station_ids, service_profile_ids)
       when is_map(profile) do
    profile = Contract.sanitize(profile)

    with {:ok, id} <- required_text(profile, "id", index),
         {:ok, station_ref} <- required_text(profile, "ground_station_ref", index),
         :ok <- known_ref(station_ids, station_ref, index, "ground_station_ref"),
         {:ok, service_profile_ref} <-
           required_text(profile, "service_profile_ref", index),
         :ok <-
           known_ref(
             service_profile_ids,
             service_profile_ref,
             index,
             "service_profile_ref"
           ),
         {:ok, resource_ref} <-
           required_text(profile, "antenna_or_service_pool_ref", index),
         {:ok, latency_ms} <-
           bounded_integer(
             profile,
             "request_latency_ms",
             0,
             0,
             @maximum_latency_ms,
             index
           ),
         {:ok, rate_limit_count} <-
           bounded_integer(
             profile,
             "rate_limit_response_count",
             0,
             0,
             1_000_000,
             index
           ),
         {:ok, retry_after_seconds} <-
           bounded_integer(
             profile,
             "retry_after_seconds",
             1,
             0,
             @maximum_retry_after_seconds,
             index
           ),
         {:ok, expiry_offset_seconds} <-
           bounded_integer(
             profile,
             "opportunity_expiry_offset_seconds",
             0,
             -@maximum_expiry_offset_seconds,
             @maximum_expiry_offset_seconds,
             index
           ) do
      {:ok,
       %{
         "id" => id,
         "ground_station_ref" => station_ref,
         "service_profile_ref" => service_profile_ref,
         "antenna_or_service_pool_ref" => resource_ref,
         "request_latency_ms" => latency_ms,
         "rate_limit_response_count" => rate_limit_count,
         "retry_after_seconds" => retry_after_seconds,
         "opportunity_expiry_offset_seconds" => expiry_offset_seconds
       }}
    end
  end

  defp normalize_profile(_profile, index, _station_ids, _service_profile_ids),
    do: {:error, {:invalid, "route_profiles[#{index}] must be an object"}}

  defp required_text(map, key, index) do
    case map[key] do
      value when is_binary(value) and value != "" -> {:ok, value}
      _other -> {:error, {:invalid, "route_profiles[#{index}].#{key} is required"}}
    end
  end

  defp known_ref(ids, value, index, key) do
    if MapSet.member?(ids, value),
      do: :ok,
      else: {:error, {:invalid, "route_profiles[#{index}].#{key} is unknown"}}
  end

  defp bounded_integer(map, key, default, minimum, maximum, index) do
    case Map.get(map, key, default) do
      value when is_integer(value) and value >= minimum and value <= maximum ->
        {:ok, value}

      _other ->
        {:error, {:invalid, "route_profiles[#{index}].#{key} is invalid"}}
    end
  end

  defp ensure_unique(profiles) do
    ids = Enum.map(profiles, & &1["id"])
    route_keys = Enum.map(profiles, &{&1["ground_station_ref"], &1["service_profile_ref"]})

    cond do
      MapSet.size(MapSet.new(ids)) != length(ids) ->
        {:error, {:invalid, "route_profiles ids must be unique"}}

      MapSet.size(MapSet.new(route_keys)) != length(route_keys) ->
        {:error,
         {:invalid,
          "route_profiles ground_station_ref and service_profile_ref pairs must be unique"}}

      true ->
        {:ok, profiles}
    end
  end

  defp maybe_delay(%{"request_latency_ms" => 0}), do: :ok

  defp maybe_delay(profile) do
    Process.sleep(profile["request_latency_ms"])
  end
end
