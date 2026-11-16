defmodule Cadence.Reads.Passes do
  @moduledoc """
  Passes in a time window for the console (ops M7 = scheduling S1): one row per
  provider reservation whose window overlaps `[from, to)`.

  Station and antenna come from the reservation's newest snapshot (Cadence
  accepted, then provider confirmed, then requested). The station is matched to
  a Cadence ground station by id or code when possible. Nothing is derived:
  elevation, cost and uplink capability are `nil` unless the provider supplied
  them, because there is no orbit propagation (DECISIONS #4).

  Provider opportunities (windows not yet booked) are not listed here; they
  need a live provider search per spacecraft.
  """

  alias Cadence.Comms.{GroundStationStore, StationRefs}
  alias Cadence.Contacts.ProviderReservation
  alias Cadence.Control.Contacts
  alias Cadence.Reads.PassEnders

  @default_limit 500
  @provider_booked [:confirmed, :active, :completed]
  @attestable [:pending, :unknown]
  @snapshots [
    :cadence_accepted_snapshot_document,
    :provider_confirmed_snapshot_document,
    :requested_snapshot_document
  ]

  @type filters :: %{
          optional(:spacecraft_id) => binary() | nil,
          optional(:station) => binary() | nil,
          optional(:states) => [binary()] | nil,
          optional(:limit) => pos_integer()
        }

  @spec load(binary(), binary(), DateTime.t(), DateTime.t(), filters()) :: map()
  def load(organization_id, mission_id, from, to, filters \\ %{}) do
    {reservations, truncated?} =
      Contacts.list_provider_reservations_in_window(organization_id, mission_id, from, to,
        spacecraft_id: Map.get(filters, :spacecraft_id),
        limit: Map.get(filters, :limit, @default_limit)
      )

    load_rows(organization_id, mission_id, reservations, %{
      from: from,
      to: to,
      truncated: truncated?,
      filters: filters
    })
  end

  @doc "One pass by its reservation id, in the same row shape (U32: Review opens any pass)."
  @spec fetch(binary(), binary(), binary()) :: {:ok, map()} | {:error, :pass_not_found}
  def fetch(organization_id, mission_id, reservation_id) do
    case Contacts.fetch_provider_reservation(organization_id, mission_id, reservation_id) do
      {:ok, %ProviderReservation{} = reservation} ->
        %{passes: [pass]} =
          load_rows(organization_id, mission_id, [reservation], %{
            from: nil,
            to: nil,
            truncated: false,
            filters: %{}
          })

        {:ok, pass}

      {:error, _reason} ->
        {:error, :pass_not_found}
    end
  end

  defp load_rows(organization_id, mission_id, reservations, window) do
    window
    |> Map.merge(%{
      reservations: reservations,
      enders: PassEnders.load(organization_id, mission_id, reservations),
      stations: GroundStationStore.list_ground_stations(organization_id, mission_id),
      spacecraft: Cadence.SpacecraftStore.list_spacecraft(organization_id, mission_id)
    })
    |> build()
  end

  @doc "Pure builder; see `load/5`."
  @spec build(map()) :: map()
  def build(%{reservations: reservations, stations: stations, filters: filters} = input) do
    index = StationRefs.build(stations)
    crafts = Map.new(Map.get(input, :spacecraft, []), &{&1.spacecraft_id, &1})
    states = filters |> Map.get(:states) |> List.wrap() |> MapSet.new()
    station = Map.get(filters, :station)

    enders = Map.get(input, :enders, %{})

    passes =
      reservations
      |> Enum.map(
        &(&1
          |> row(index, crafts)
          |> Map.put(:ended_by, PassEnders.ended_by(&1, enders)))
      )
      |> Enum.filter(&(state_match?(&1, states) and station_match?(&1, station)))

    %{from: input.from, to: input.to, truncated: input.truncated, passes: passes}
  end

  defp state_match?(pass, states), do: MapSet.size(states) == 0 or pass.state in states

  defp station_match?(_pass, nil), do: true

  defp station_match?(pass, station),
    do: station in [pass.station.ref, pass.station.id, pass.station.code]

  defp row(%ProviderReservation{} = reservation, index, crafts) do
    snapshot = snapshot(reservation)

    station_ref =
      text(snapshot, "ground_station_ref") || text(reservation.metadata, "ground_station_ref")

    antenna_ref =
      text(snapshot, "antenna_or_service_pool_ref") ||
        text(reservation.metadata, "antenna_or_service_pool_ref")

    extensions = (is_map(snapshot["extensions"]) && snapshot["extensions"]) || %{}

    %{
      id: reservation.provider_reservation_id,
      kind: "contact",
      state: atom_text(reservation.lifecycle_state),
      pass_phase: atom_text(reservation.pass_phase),
      delivery_state: atom_text(reservation.delivery_state),
      spacecraft_id: reservation.spacecraft_id,
      spacecraft: spacecraft(reservation.spacecraft_id, crafts),
      station: StationRefs.resolve(station_ref, index),
      antenna: antenna_ref && %{id: antenna_ref, label: nil},
      starts_at: reservation.starts_at,
      ends_at: reservation.ends_at,
      uplink_capable: boolean_or_nil(extensions["uplink_capable"]),
      source: %{
        provider: reservation.provider_id,
        provider_name: text(reservation.metadata, "provider_display_name"),
        synthetic: boolean_or_nil(Map.get(snapshot, "synthetic", extensions["synthetic"]))
      },
      max_elevation_deg: number_or_nil(extensions["max_elevation_deg"]),
      cost: cost(extensions["cost"]),
      plan:
        reservation.contact_plan_id &&
          %{id: reservation.contact_plan_id, version: reservation.contact_plan_version},
      # U74: the requirement it was booked for (ids; detail adds its name).
      requirement:
        reservation.contact_requirement_id &&
          %{
            id: reservation.contact_requirement_id,
            version: reservation.contact_requirement_version
          },
      reservation_id: reservation.provider_reservation_id,
      scheduled_contact_id: reservation.scheduled_contact_id,
      booking_evidence: booking_evidence(reservation),
      attested_by: attested_by(reservation),
      uplink_confirmed: uplink_confirmed(reservation),
      # The booking's open attention item (U32); the controller fills it for viewers who operate.
      attention: nil,
      # Live uplink readiness (U33); the controller fills it from the readiness view.
      uplink_readiness: nil,
      # D2 Release: the revision the client sends back, and whether this viewer may release it
      # (the controller fills `releasable`).
      provider_revision: reservation.provider_revision,
      releasable: nil,
      # L15: booked outside a plan (`booked_by.name` is filled by the controller), else nil.
      off_plan: off_plan(reservation.metadata)
    }
  end

  defp off_plan(%{"off_plan" => %{"booked_by" => %{"id" => id} = by} = off_plan}) do
    %{
      booked_by: %{kind: by["kind"], id: id, name: nil},
      booked_at: off_plan["booked_at"],
      note: text(off_plan, "note")
    }
  end

  defp off_plan(_metadata), do: nil

  # U32 / DECISIONS #53: the provider's word wins; an operator's attestation counts only while the
  # provider is silent.
  defp booking_evidence(%ProviderReservation{lifecycle_state: state})
       when state in @provider_booked,
       do: "provider"

  defp booking_evidence(%ProviderReservation{lifecycle_state: state} = reservation)
       when state in @attestable do
    if attestation(reservation), do: "operator_attested"
  end

  defp booking_evidence(_reservation), do: nil

  defp attested_by(reservation) do
    with "operator_attested" <- booking_evidence(reservation),
         %{} = actor <- attestation(reservation)["actor"] do
      %{kind: actor["kind"], id: actor["id"], name: actor["name"]}
    else
      _other -> nil
    end
  end

  defp attestation(%ProviderReservation{
         metadata: %{"operator_resolution" => %{"action" => "booked"} = marker}
       }),
       do: marker

  defp attestation(_reservation), do: nil

  # nil when no uplink leg was requested (downlink-only): there's nothing to confirm. False once
  # an accepted change dropped the leg (U46: the pass has no command window then).
  defp uplink_confirmed(%ProviderReservation{} = reservation) do
    if is_map(get_in(reservation.request_document || %{}, ["uplink"])) do
      get_in(reservation.provider_confirmed_snapshot_document || %{}, ["uplink", "status"]) ==
        "included" and not Contacts.uplink_leg_dropped?(reservation)
    end
  end

  defp snapshot(reservation) do
    Enum.find_value(@snapshots, %{}, fn key ->
      case Map.get(reservation, key) do
        %{} = doc when map_size(doc) > 0 -> doc
        _empty -> nil
      end
    end)
  end

  # Identity on every line (CommandFlow R01): name and SCID, nil when the spacecraft is gone.
  defp spacecraft(id, crafts) do
    case Map.get(crafts, id) do
      nil -> %{id: id, name: nil, scid: nil}
      craft -> %{id: id, name: craft.display_name, scid: craft.scid}
    end
  end

  defp cost(%{"amount" => amount, "currency" => currency})
       when is_number(amount) and is_binary(currency),
       do: %{amount: amount, currency: currency}

  defp cost(_cost), do: nil

  defp text(%{} = map, key) do
    case Map.get(map, key) do
      value when is_binary(value) and value != "" -> value
      _other -> nil
    end
  end

  defp text(_map, _key), do: nil

  defp atom_text(nil), do: nil
  defp atom_text(value), do: to_string(value)

  defp boolean_or_nil(value) when is_boolean(value), do: value
  defp boolean_or_nil(_value), do: nil

  defp number_or_nil(value) when is_number(value), do: value
  defp number_or_nil(_value), do: nil
end
