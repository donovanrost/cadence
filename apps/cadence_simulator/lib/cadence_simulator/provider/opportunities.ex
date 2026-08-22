defmodule CadenceSimulator.Provider.Opportunities do
  @moduledoc "Environment-scoped opportunity search for Provider Contract v1."

  alias CadenceSimulator.Provider

  alias CadenceSimulator.Provider.{
    Capabilities,
    OrbitReadiness,
    RouteProfiles,
    ServiceProfiles,
    Store
  }

  @spec search(map(), map()) ::
          {:ok, %{data: [map()], next_cursor: binary() | nil, truncated: boolean()}}
          | {:error, term()}
  def search(run, params) when is_map(run) and is_map(params) do
    behavior = Capabilities.for_run(run)
    search_limits = behavior["search"]

    with {:ok, service_profile} <- service_profile(run, params["service_profile_ref"]),
         {:ok, orbit_readiness} <- OrbitReadiness.for_search(run, params),
         {:ok, spacecraft_refs} <- reference_list(params, "spacecraft_refs"),
         {:ok, ground_station_refs} <- reference_list(params, "ground_station_refs"),
         {:ok, _route_profile} <-
           RouteProfiles.apply_search_control(
             run,
             service_profile["id"],
             ground_station_refs
           ),
         :ok <-
           within_limit(
             spacecraft_refs,
             search_limits["spacecraft_batch_limit"],
             "spacecraft_refs"
           ),
         :ok <-
           within_limit(
             ground_station_refs,
             search_limits["station_batch_limit"],
             "ground_station_refs"
           ),
         {:ok, page_size} <- page_size(params["page_size"], search_limits["page_size_limit"]),
         {:ok, offset} <- cursor(params["cursor"]),
         {:ok, legacy_page} <-
           Provider.search_opportunities(%{
             "run_id" => run["id"],
             "spacecraft_ids" => spacecraft_refs,
             "ground_station_ids" => ground_station_refs,
             "starts_at" => params["starts_at"],
             "ends_at" => params["ends_at"],
             "limit" => min(500, offset + page_size + 1)
           }) do
      opportunities =
        legacy_page["data"]
        |> Enum.map(&normalize(&1, run, service_profile, orbit_readiness))

      page = opportunities |> Enum.drop(offset) |> Enum.take(page_size)
      Enum.each(page, &Store.put(:opportunity, &1))

      truncated = length(opportunities) > offset + page_size
      next_cursor = if truncated, do: Integer.to_string(offset + page_size), else: nil

      {:ok,
       %{
         data: Enum.map(page, &public/1),
         next_cursor: next_cursor,
         truncated: truncated,
         provider_evidence: %{"orbit_readiness" => orbit_readiness}
       }}
    end
  end

  @spec fetch(map(), binary()) :: {:ok, map()} | {:error, :not_found}
  def fetch(run, id) when is_binary(id) do
    expected_run_id = run["id"]

    case Store.fetch(:opportunity, id) do
      {:ok, %{"run_id" => ^expected_run_id} = opportunity} ->
        {:ok, opportunity}

      _other ->
        {:error, :not_found}
    end
  end

  defp service_profile(_run, nil),
    do: {:error, {:invalid, "service_profile_ref is required"}}

  defp service_profile(run, id) when is_binary(id) do
    case Enum.find(ServiceProfiles.for_run(run), &(&1["id"] == id and &1["state"] == "active")) do
      nil -> {:error, {:invalid, "service_profile_ref is invalid"}}
      profile -> {:ok, profile}
    end
  end

  defp service_profile(_run, _id),
    do: {:error, {:invalid, "service_profile_ref is invalid"}}

  defp reference_list(params, key) do
    case Map.get(params, key, []) do
      values when is_list(values) ->
        if Enum.all?(values, &(is_binary(&1) and &1 != "")),
          do: {:ok, values},
          else: {:error, {:invalid, "#{key} is invalid"}}

      _other ->
        {:error, {:invalid, "#{key} must be a list"}}
    end
  end

  defp within_limit(values, limit, key) do
    if length(values) <= limit,
      do: :ok,
      else: {:error, {:invalid, "#{key} exceeds the environment limit of #{limit}"}}
  end

  defp page_size(nil, limit), do: {:ok, min(100, limit)}

  defp page_size(value, limit) when is_integer(value) and value > 0,
    do: {:ok, min(value, limit)}

  defp page_size(_value, _limit), do: {:error, {:invalid, "page_size is invalid"}}

  defp cursor(nil), do: {:ok, 0}
  defp cursor(""), do: {:ok, 0}

  defp cursor(value) when is_binary(value) do
    case Integer.parse(value) do
      {offset, ""} when offset >= 0 -> {:ok, offset}
      _other -> {:error, {:invalid, "cursor is invalid"}}
    end
  end

  defp cursor(_value), do: {:error, {:invalid, "cursor is invalid"}}

  defp normalize(opportunity, run, service_profile, orbit_readiness) do
    route_profile =
      RouteProfiles.for_opportunity(
        run,
        opportunity["ground_station_id"],
        service_profile["id"]
      )

    resource_ref =
      if route_profile,
        do: route_profile["antenna_or_service_pool_ref"],
        else: opportunity["antenna_id"]

    expires_at =
      if route_profile do
        shift_time(
          opportunity["starts_at"],
          route_profile["opportunity_expiry_offset_seconds"]
        )
      else
        opportunity["starts_at"]
      end

    %{
      "id" => opportunity["id"],
      "run_id" => opportunity["run_id"],
      "spacecraft_ref" => opportunity["spacecraft_id"],
      "ground_station_ref" => opportunity["ground_station_id"],
      "antenna_or_service_pool_ref" => resource_ref,
      "service_profile_ref" => service_profile["id"],
      "starts_at" => opportunity["starts_at"],
      "ends_at" => opportunity["ends_at"],
      "expires_at" => expires_at,
      "availability" => "available",
      "synthetic" => true,
      "extensions" => %{
        "model" => opportunity["model"],
        "orbit_readiness" => orbit_readiness,
        "route_profile_ref" => route_profile && route_profile["id"]
      }
    }
  end

  defp public(opportunity), do: Map.drop(opportunity, ["run_id"])

  defp shift_time(value, seconds) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} ->
        datetime |> DateTime.add(seconds, :second) |> DateTime.to_iso8601()

      _error ->
        value
    end
  end
end
