defmodule Cadence.GroundNetworks.PredictedPasses.SearchBasisTest do
  @moduledoc """
  The recompute runs record what they searched (#892): per spacecraft the element set and
  window, per station the geometry and from when, and the prune bound. Each run forgets what it
  can't vouch for.
  """
  use Cadence.DataCase, async: true

  import Ecto.Query

  alias Cadence.Comms.{GroundStation, GroundStationRow, GroundStationStore}
  alias Cadence.GroundNetworks.{ElementSets, PredictedPasses}
  alias Cadence.GroundNetworks.PredictedPasses.{Basis, Store}
  alias Cadence.Repo
  alias Cadence.SpacecraftStore.SpacecraftRow

  @now ~U[2026-11-27 00:00:00.000000Z]
  @day 86_400
  @actor %{"actor_kind" => "user", "user_id" => "user-search-basis"}

  setup do
    suffix = System.unique_integer([:positive])
    org = "org-basis-#{suffix}"
    mission = "mission-basis-#{suffix}"
    persist_mission_scope(org, mission)
    [a, deep] = insert_spacecraft!(org, mission, 2)
    svalbard = station!(org, mission, "svalbard", {78.23, 15.41})
    unlocated = station!(org, mission, "unlocated", nil)

    submit!(org, mission, [
      {a, omm(15.2, "2026-11-26T12:00:00")},
      {deep, omm(2.0, "2026-11-26T12:00:00")}
    ])

    {:ok, _} = PredictedPasses.run(org, mission, :full, @now)

    %{org: org, mission: mission, a: a, deep: deep, svalbard: svalbard, unlocated: unlocated}
  end

  test "a full run records the propagated spacecraft and the located stations from its start",
       c do
    basis = basis(c)
    [set] = ElementSets.current_for(c.org, c.mission, [c.a])
    horizon = DateTime.add(@now, 7 * @day)

    assert basis["spacecraft"] == %{
             c.a => %{
               "element_set_id" => set.element_set_id,
               "from" => DateTime.to_iso8601(@now),
               "to" => DateTime.to_iso8601(horizon)
             }
           }

    assert Map.keys(basis["stations"]) == [c.svalbard]

    assert basis["stations"][c.svalbard]["fingerprint"] ==
             Basis.fingerprint(station(c, c.svalbard))
  end

  test "a new set's spacecraft run restarts that entry with the new set from its own start", c do
    later = DateTime.add(@now, 3_600)
    submit!(c.org, c.mission, [{c.a, omm(15.2, "2026-11-26T18:00:00")}])
    [set] = ElementSets.current_for(c.org, c.mission, [c.a])

    {:ok, _} = PredictedPasses.run(c.org, c.mission, {:spacecraft, [c.a]}, later)

    assert %{"element_set_id" => id, "from" => from} = basis(c)["spacecraft"][c.a]
    assert id == set.element_set_id
    assert from == DateTime.to_iso8601(later)
  end

  test "an extension extends a spacecraft searched with the same set and drops one whose set changed",
       c do
    {:ok, _} = PredictedPasses.run(c.org, c.mission, :extend, DateTime.add(@now, @day))
    assert basis(c)["spacecraft"][c.a]["to"] == DateTime.to_iso8601(DateTime.add(@now, 8 * @day))

    # A new set whose spacecraft run hasn't happened: the extension's rows mix two sets.
    submit!(c.org, c.mission, [{c.a, omm(15.2, "2026-11-26T18:00:00")}])
    {:ok, _} = PredictedPasses.run(c.org, c.mission, :extend, DateTime.add(@now, 2 * @day))
    refute Map.has_key?(basis(c)["spacecraft"], c.a)
  end

  test "an extension drops a station whose geometry changed; its station run restarts it", c do
    {1, _} =
      GroundStationRow
      |> where([row], row.mission_id == ^c.mission and row.ground_station_id == ^c.svalbard)
      |> Repo.update_all(set: [elevation_mask_deg: 10.0])

    {:ok, _} = PredictedPasses.run(c.org, c.mission, :extend, DateTime.add(@now, @day))
    refute Map.has_key?(basis(c)["stations"], c.svalbard)

    later = DateTime.add(@now, @day + 60)
    {:ok, _} = PredictedPasses.run(c.org, c.mission, {:stations, [c.svalbard]}, later)

    assert basis(c)["stations"][c.svalbard] == %{
             "fingerprint" => Basis.fingerprint(station(c, c.svalbard)),
             "from" => DateTime.to_iso8601(later)
           }
  end

  test "the prune raises the lower bound and keeps the entries", c do
    prune_at = DateTime.add(@now, 10 * @day)
    {:ok, _} = PredictedPasses.run(c.org, c.mission, :prune, prune_at)

    basis = basis(c)
    assert basis["pruned_before"] == DateTime.to_iso8601(DateTime.add(prune_at, -7 * @day))
    assert Map.has_key?(basis["spacecraft"], c.a)
  end

  defp basis(c), do: Store.state(c.org, c.mission).search_basis

  defp station(c, id) do
    {:ok, station} = GroundStationStore.fetch_ground_station(c.org, c.mission, id)
    station
  end

  defp submit!(org, mission, items) do
    {:ok, _} =
      ElementSets.submit(
        org,
        mission,
        Enum.map(items, fn {id, omm} -> %{spacecraft_id: id, input: {:omm, omm}} end),
        actor: @actor,
        source: "manual",
        now: @now
      )
  end

  defp omm(mean_motion, epoch) do
    %{
      "EPOCH" => epoch,
      "MEAN_MOTION" => mean_motion,
      "ECCENTRICITY" => 0.0005,
      "INCLINATION" => 97.6,
      "RA_OF_ASC_NODE" => 10.0,
      "ARG_OF_PERICENTER" => 90.0,
      "MEAN_ANOMALY" => 270.0,
      "BSTAR" => 2.0e-5
    }
  end

  defp station!(org, mission, name, at) do
    location =
      case at do
        {lat, lon} -> %{latitude_deg: lat, longitude_deg: lon, height_m: 0.0}
        nil -> nil
      end

    id = "ground_station_#{name}_#{System.unique_integer([:positive])}"

    {:ok, _} =
      GroundStationStore.persist_ground_station(
        org,
        GroundStation.new(%{
          ground_station_id: id,
          organization_id: org,
          mission_id: mission,
          display_name: name,
          location: location
        })
      )

    id
  end

  defp insert_spacecraft!(org, mission, count) do
    suffix = System.unique_integer([:positive])

    rows =
      for i <- 1..count do
        %{
          spacecraft_id: "craft-#{suffix}-#{i}",
          organization_id: org,
          mission_id: mission,
          display_name: "Craft #{i}",
          scid: 100 + i,
          metadata: %{},
          lifecycle_state: "active",
          inserted_at: DateTime.utc_now()
        }
      end

    {^count, _} = Repo.insert_all(SpacecraftRow, rows)
    Enum.map(rows, & &1.spacecraft_id)
  end
end
