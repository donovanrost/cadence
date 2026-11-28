defmodule Cadence.Control.ConfigUsers do
  @moduledoc """
  What still uses a mission's transport or ground station (director 11-16, ux U82), so archiving
  one is refused while anything does. Configured as `:config_users` so the comms ground-station
  kind needs no compile-time edge to contacts.

  Uses, every kind always present: `%{routes, profile_routes, booked_passes, listening_now,
  transports}`. Each is `%{count, items}` (items: at most 3, and only those whose line has the
  name it needs; `count` is always the full number), except `booked_passes`, which is
  `%{count, next_at}`. `transports` is a station's own (always 0 for a transport).

  - routes: active routing rules from profiles and extra routes on it; a rule without a
    station is at its transport's station.
  - profile_routes: the latest version of each profile whose rules name it (a station entry
    without a transport means that station's transport).
  - booked_passes: reservations still booked ahead (ReservationActivity.booked_ahead/3).
  - listening_now: open contacts (defined, active) on it.
  """

  alias Cadence.Comms.{GroundStationStore, RoutingRuleStore, StationRefs, TransportStore}
  alias Cadence.Contacts.{OpenContacts, ReservationActivity}
  alias Cadence.SourceEndpoints
  alias Cadence.SpacecraftStore
  alias Cadence.SpacecraftTypeStore

  @listed 3

  @doc "`except:` uses being deleted beside it, as `{kind, entity_id}` (Staging's `deleting`)."
  @spec transport_uses(binary(), binary(), binary(), keyword()) :: map()
  def transport_uses(org, mission, transport_id, opts \\ []) do
    ctx = context(org, mission, Keyword.get(opts, :except, MapSet.new()))
    station = transport_station(ctx, transport_id)

    %{
      routes: routes(ctx, &(&1.transport_id == transport_id)),
      profile_routes:
        profile_routes(ctx, &profile_entry_uses_transport?(&1, transport_id, station)),
      booked_passes: booked(org, mission, &reservation_transport?(&1, transport_id)),
      listening_now: listening(ctx, org, mission, &(&1.metadata["transport_id"] == transport_id)),
      transports: listed([], & &1)
    }
  end

  @spec station_uses(binary(), binary(), binary(), keyword()) :: map()
  def station_uses(org, mission, station_id, opts \\ []) do
    ctx = context(org, mission, Keyword.get(opts, :except, MapSet.new()))
    at_station? = &(transport_station(ctx, &1) == station_id)

    %{
      routes: routes(ctx, &(rule_station(ctx, &1) == station_id)),
      profile_routes:
        profile_routes(
          ctx,
          &(&1["ground_station_id"] == station_id or at_station?.(&1["transport_id"]))
        ),
      booked_passes: booked(org, mission, &(station_id in reservation_stations(ctx, &1))),
      listening_now: listening(ctx, org, mission, &at_station?.(&1.metadata["transport_id"])),
      transports:
        ctx.transports
        |> Map.values()
        |> Enum.filter(&(&1.ground_station_id == station_id))
        |> Enum.reject(&MapSet.member?(ctx.except, {"transport", &1.transport_id}))
        |> Enum.sort_by(& &1.display_name)
        |> listed(&(is_binary(&1.display_name) && %{id: &1.transport_id, name: &1.display_name}))
    }
  end

  @doc "Whether any use counts (the refusal holds)."
  @spec in_use?(map()) :: boolean()
  def in_use?(uses), do: Enum.any?(uses, fn {_kind, %{count: count}} -> count > 0 end)

  defp context(org, mission, except) do
    transports = Map.new(TransportStore.list_transports(org, mission), &{&1.transport_id, &1})
    stations = GroundStationStore.list_ground_stations(org, mission)

    %{
      transports: transports,
      stations: Map.new(stations, &{&1.ground_station_id, &1}),
      station_index: StationRefs.index(org, mission),
      spacecraft: Map.new(SpacecraftStore.list_spacecraft(org, mission), &{&1.spacecraft_id, &1}),
      rules:
        org |> RoutingRuleStore.list_routing_rules(mission) |> Enum.reject(&going?(&1, except)),
      profiles:
        org
        |> SpacecraftTypeStore.list_spacecraft_types(mission)
        |> Enum.reject(&MapSet.member?(except, {"spacecraft_profile", &1.spacecraft_type_id})),
      except: except
    }
  end

  defp going?(rule, except),
    do:
      rule.origin == :spacecraft and
        MapSet.member?(except, {"spacecraft_route", rule.profile_rule_id})

  defp transport_station(ctx, transport_id) do
    case Map.get(ctx.transports, transport_id) do
      %{ground_station_id: station} -> station
      nil -> nil
    end
  end

  defp rule_station(ctx, rule),
    do:
      rule.ground_station_id ||
        transport_station(ctx, rule.transport_id)

  defp routes(ctx, uses?) do
    ctx.rules
    |> Enum.filter(&(&1.lifecycle_state == :active and uses?.(&1)))
    |> listed(fn rule ->
      case ctx.spacecraft[rule.spacecraft_id] do
        %{display_name: name} when is_binary(name) ->
          station = ctx.stations[rule_station(ctx, rule)]

          %{
            routing_rule_id: rule.routing_rule_id,
            name: rule.display_name,
            spacecraft: %{id: rule.spacecraft_id, name: name},
            station:
              station &&
                %{id: station.ground_station_id, code: station.code, name: station.display_name},
            direction: if(rule.direction == :outbound, do: "uplink", else: "downlink")
          }

        _unnamed ->
          nil
      end
    end)
  end

  defp profile_routes(ctx, entry_uses?) do
    for profile <- ctx.profiles,
        rule <- profile.routing_rules || [],
        Enum.any?(rule["stations"] || [], entry_uses?) do
      {profile, rule}
    end
    |> listed(fn {profile, rule} ->
      is_binary(profile.display_name) &&
        %{
          profile: %{id: profile.spacecraft_type_id, name: profile.display_name},
          rule_id: rule["id"],
          label: rule["label"]
        }
    end)
  end

  # A profile station entry without a transport means that station's transport for each leg.
  defp profile_entry_uses_transport?(entry, transport_id, station),
    do:
      entry["transport_id"] == transport_id or
        (is_nil(entry["transport_id"]) and is_binary(station) and
           entry["ground_station_id"] == station)

  defp booked(org, mission, uses?) do
    reservations =
      org
      |> ReservationActivity.booked_ahead(mission, DateTime.utc_now())
      |> Enum.filter(uses?)

    %{
      count: length(reservations),
      next_at: reservations |> Enum.map(& &1.starts_at) |> Enum.min(DateTime, fn -> nil end)
    }
  end

  # The downlink transport, or an uplink leg's.
  defp reservation_transport?(reservation, transport_id),
    do:
      reservation.transport_id == transport_id or
        get_in(reservation.request_document || %{}, ["uplink", "transport_id"]) == transport_id

  defp reservation_stations(ctx, reservation) do
    ref =
      Enum.find_value(
        [
          reservation.provider_confirmed_snapshot_document,
          Map.get(reservation, :requested_snapshot_document),
          reservation.request_document
        ],
        &(is_map(&1) && &1["ground_station_ref"])
      )

    transport_station = transport_station(ctx, reservation.transport_id)
    Enum.reject([StationRefs.resolve(ref, ctx.station_index).id, transport_station], &is_nil/1)
  end

  defp listening(ctx, org, mission, uses?) do
    org
    |> OpenContacts.list(mission)
    |> Enum.filter(&uses?.(%{&1 | metadata: &1.metadata || %{}}))
    |> listed(fn contact ->
      with id when is_binary(id) <- spacecraft_id(contact),
           %{display_name: name} when is_binary(name) <- ctx.spacecraft[id] do
        station = ctx.stations[transport_station(ctx, contact.metadata["transport_id"])]

        %{
          realized_contact_id: contact.realized_contact_id,
          spacecraft: %{id: id, name: name},
          station_code: station && station.code,
          starts_at: contact.realized_at || contact.initial_time
        }
      else
        _unnamed -> nil
      end
    end)
  end

  defp spacecraft_id(contact),
    do:
      Enum.find_value(
        contact.source_endpoint_refs || [],
        &SourceEndpoints.spacecraft_id_from_managed_source_endpoint/1
      )

  # The full count; at most @listed items, only those with the name their line needs.
  defp listed(uses, item) do
    %{
      count: length(uses),
      items: uses |> Enum.map(item) |> Enum.filter(& &1) |> Enum.take(@listed)
    }
  end
end
