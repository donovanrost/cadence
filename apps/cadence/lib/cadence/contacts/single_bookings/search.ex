defmodule Cadence.Contacts.SingleBookings.Search do
  @moduledoc """
  Book a pass, search (L15, fe-ops' proposal with api): one spacecraft's offers over a window,
  fanned out over its ready downlink routes and merged. Route keys and evidence stay inside each
  offer's signed reserve token. Each offer says whether it can carry an uplink leg, and whether it
  overlaps a live booking of the same spacecraft or of another spacecraft on the same antenna
  (DECISIONS #78), so the console disables it with the reason.
  """

  alias Cadence.Comms.StationRefs
  alias Cadence.Contacts.{ProviderScheduling, ScheduleCommands, SingleBookings, UplinkLegs}
  alias Cadence.SpacecraftStore

  @max_window_s 7 * 86_400

  @doc """
  `params`: `%{"spacecraft_id", "from", "to", "direction" => "downlink" | "uplink",
  "station_ids" => [id] | nil}`. `{:ok, %{spacecraft, window, offers, hidden, not_ready,
  truncated}}`, or `{:error, {:invalid, %{field => message}}}`, `:not_found`, `:forbidden`,
  `:search_unavailable`. No ready route is not an error: `offers: []` with `not_ready`.
  """
  def run(scope, mission, params) when is_map(params) do
    org = scope.organization_id

    with {:ok, query} <- query(params),
         {:ok, sc} <- spacecraft(org, mission, query.spacecraft_id),
         {:ok, %{routes: routes, findings: findings}} <-
           ProviderScheduling.list_ready_downlink_routes(org, mission, sc.spacecraft_id),
         {:ok, found, failed, truncated} <- search_routes(scope, mission, query, routes) do
      offers = enrich(org, mission, sc, found)
      {kept, hidden} = filter(offers, query)

      {:ok,
       %{
         spacecraft: %{id: sc.spacecraft_id, name: sc.display_name, scid: sc.scid},
         window: %{from: query.from, to: query.to},
         offers: Enum.sort_by(kept, & &1.starts_at, DateTime),
         hidden: hidden,
         not_ready:
           Enum.map(findings, &%{code: to_string(&1.code), message: &1.message}) ++ failed,
         truncated: truncated
       }}
    end
  end

  def run(_scope, _mission, _params), do: {:error, {:invalid, %{"" => "Search for a spacecraft"}}}

  defp query(params) do
    with {:ok, from} <- time(params["from"], "from"),
         {:ok, to} <- time(params["to"], "to"),
         :ok <- window(from, to),
         direction when direction in ["downlink", "uplink"] <-
           params["direction"] || "downlink" do
      {:ok,
       %{
         spacecraft_id: params["spacecraft_id"],
         from: from,
         to: to,
         direction: direction,
         station_ids: params["station_ids"]
       }}
    else
      {:error, _invalid} = error -> error
      _direction -> {:error, {:invalid, %{"direction" => "Choose downlink or uplink"}}}
    end
  end

  defp time(value, field) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, at, _offset} -> {:ok, DateTime.truncate(at, :second)}
      _invalid -> {:error, {:invalid, %{field => "Use an ISO 8601 UTC time"}}}
    end
  end

  defp time(_value, field), do: {:error, {:invalid, %{field => "Choose a time"}}}

  defp window(from, to) do
    cond do
      not DateTime.after?(to, DateTime.utc_now()) ->
        {:error, {:invalid, %{"to" => "The window is in the past"}}}

      not DateTime.before?(from, to) ->
        {:error, {:invalid, %{"to" => "End after the start"}}}

      DateTime.diff(to, from) > @max_window_s ->
        {:error, {:invalid, %{"to" => "Search at most 7 days"}}}

      true ->
        :ok
    end
  end

  defp spacecraft(org, mission, id) when is_binary(id) do
    case SpacecraftStore.fetch_spacecraft(org, mission, id) do
      {:ok, sc} -> {:ok, sc}
      _missing -> {:error, :not_found}
    end
  end

  defp spacecraft(_org, _mission, _id),
    do: {:error, {:invalid, %{"spacecraft_id" => "Choose a spacecraft"}}}

  # One search per ready route (the shared, authorized command). A route whose provider search
  # fails becomes a not_ready line; only when every route fails is the search unavailable.
  defp search_routes(_scope, _mission, _query, []), do: {:ok, [], [], false}

  defp search_routes(scope, mission, query, routes) do
    results =
      Enum.map(routes, fn route ->
        {route,
         ScheduleCommands.execute(scope, mission, "search", %{
           "contact_search" => %{
             "spacecraft_id" => query.spacecraft_id,
             "route_key" => route.route_key,
             "starts_at" => DateTime.to_iso8601(query.from),
             "ends_at" => DateTime.to_iso8601(query.to)
           },
           "route_evidence" => ProviderScheduling.route_evidence(route)
         })}
      end)

    {ok, failed} = Enum.split_with(results, &match?({_route, {:ok, _}}, &1))

    cond do
      Enum.any?(failed, &match?({_route, {:error, :forbidden}}, &1)) ->
        {:error, :forbidden}

      ok == [] ->
        {:error, :search_unavailable}

      true ->
        found =
          distinct_offers(
            for {route, {:ok, result}} <- ok,
                offer <- result["opportunities"] || [],
                do: {route, offer}
          )

        not_ready =
          Enum.map(failed, fn {route, _error} ->
            %{
              code: "search_unavailable",
              message: "#{route.provider_display_name} didn't answer the search."
            }
          end)

        {:ok, found, not_ready, Enum.any?(ok, fn {_route, {:ok, r}} -> r["truncated"] end)}
    end
  end

  @doc false
  # One offer per provider opportunity. Two ready routes to the same provider (another routing
  # rule, transport or delivery profile) find the same pass; the first route in a fixed order
  # (provider, route name, route key) books it, as fe-ops saw each pass listed twice.
  def distinct_offers(found) do
    found
    |> Enum.sort_by(fn {route, offer} ->
      {route.provider_display_name, route.route_display_name, route.route_key, offer["starts_at"]}
    end)
    |> Enum.uniq_by(fn {route, offer} -> {route.provider_id, offer["id"]} end)
  end

  defp enrich(org, mission, sc, found) do
    stations = StationRefs.index(org, mission)
    occupancy = occupancy(org, mission, found)

    uplink =
      found
      |> Enum.map(fn {route, offer} -> {offer["station"], route.provider_id} end)
      |> Enum.uniq()
      |> Map.new(fn {station, provider} ->
        {{station, provider},
         is_map(UplinkLegs.for_booking(org, mission, sc.spacecraft_id, station, provider))}
      end)

    Enum.map(found, fn {route, offer} ->
      starts_at = at(offer["starts_at"])
      ends_at = at(offer["ends_at"])

      %{
        id: offer["id"],
        token: offer["token"],
        expires_at: at(offer["expires_at"]),
        starts_at: starts_at,
        ends_at: ends_at,
        station: StationRefs.resolve(offer["station"], stations),
        antenna: offer["antenna"] && %{id: offer["antenna"], label: nil},
        provider: %{id: route.provider_id, name: route.provider_display_name},
        availability: offer["availability"],
        uplink_capable: Map.get(uplink, {offer["station"], route.provider_id}, false),
        synthetic: offer["synthetic"] == true,
        cost: offer["cost"],
        overlaps:
          SingleBookings.overlap(occupancy, %{
            spacecraft_id: sc.spacecraft_id,
            antenna_ref: offer["antenna"],
            starts_at: starts_at,
            ends_at: ends_at
          })
      }
    end)
  end

  defp occupancy(_org, _mission, []), do: []

  defp occupancy(org, mission, found) do
    times = Enum.flat_map(found, fn {_route, o} -> [at(o["starts_at"]), at(o["ends_at"])] end)
    SingleBookings.occupancy(org, mission, Enum.min(times, DateTime), Enum.max(times, DateTime))
  end

  # Uplink: only offers that can carry an uplink leg; the stations left out are counted.
  defp filter(offers, query) do
    offers =
      case query.station_ids do
        ids when is_list(ids) and ids != [] -> Enum.filter(offers, &(&1.station.id in ids))
        _all -> offers
      end

    if query.direction == "uplink" do
      {kept, dropped} = Enum.split_with(offers, & &1.uplink_capable)

      {kept, %{no_uplink_route: dropped |> Enum.map(& &1.station.ref) |> Enum.uniq() |> length()}}
    else
      {offers, %{no_uplink_route: 0}}
    end
  end

  defp at(%DateTime{} = at), do: at

  defp at(text) when is_binary(text) do
    {:ok, at, _offset} = DateTime.from_iso8601(text)
    at
  end

  defp at(_none), do: nil
end
