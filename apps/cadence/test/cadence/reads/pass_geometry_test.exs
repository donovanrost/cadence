defmodule Cadence.Reads.PassGeometryTest do
  @moduledoc """
  Predicted geometry on contacts and opportunities (#892): the match rule (overlap, longest
  overlap, ties), the provider's elevation winning, hand-started windows, the opportunity flag
  and its "can't say" state, and one match query per page.
  """
  use Cadence.DataCase, async: true

  alias Cadence.Comms.{GroundStation, GroundStationStore}
  alias Cadence.GroundNetworks.ElementSets
  alias Cadence.GroundNetworks.PredictedPasses.{PredictedPassRow, Store}
  alias Cadence.Reads.PassGeometry
  alias Cadence.Repo
  alias Cadence.SpacecraftStore.SpacecraftRow

  @t0 ~U[2026-11-28 00:00:00.000000Z]
  @actor %{"actor_kind" => "user", "user_id" => "user-pass-geometry"}

  setup do
    suffix = System.unique_integer([:positive])
    org = "org-geometry-#{suffix}"
    mission = "mission-geometry-#{suffix}"
    persist_mission_scope(org, mission)

    [a, b] = insert_spacecraft!(org, mission, 2)
    located = station!(org, mission, "located", {78.23, 15.41})
    unlocated = station!(org, mission, "unlocated", nil)

    {:ok, _} =
      ElementSets.submit(org, mission, [%{spacecraft_id: a, input: {:omm, omm()}}],
        actor: @actor,
        source: "manual",
        now: @t0
      )

    Store.put_state!(org, mission, %{
      horizon_end: at(7 * 24 * 60),
      computed_at: at(1),
      unpropagated: %{},
      not_bracketed: %{}
    })

    # Two passes of `a` over `located`: 10:00–10:10 (peak 40°) and 10:20–10:30 (peak 70°).
    pass!(org, mission, a, located, "pass-early", {600, 610}, 40.0)
    pass!(org, mission, a, located, "pass-late", {620, 630}, 70.0)

    %{org: org, mission: mission, a: a, b: b, located: located, unlocated: unlocated}
  end

  describe "contacts" do
    test "the longest overlap wins, ties go to the earlier AOS, no overlap is nil", c do
      rows = [
        # 10:05–10:25 overlaps early by 5 min and late by 5 min: a tie, the earlier AOS wins.
        contact(c.a, c.located, {605, 625}),
        # 10:08–10:28 overlaps early by 2 min and late by 8 min: late wins.
        contact(c.a, c.located, {608, 628}),
        # 11:00–11:10 overlaps nothing.
        contact(c.a, c.located, {660, 670}),
        # Another spacecraft, or no station: nothing to match.
        contact(c.b, c.located, {600, 610}),
        contact(c.a, nil, {600, 610})
      ]

      assert [tie, longest, none, other, no_station] =
               PassGeometry.contacts(c.org, c.mission, rows)

      assert %{predicted_pass_id: "pass-early", max_elevation_deg: 40.0} = tie
      assert tie.elevation_source == "predicted"
      assert %{predicted_pass_id: "pass-late", max_elevation_deg: 70.0} = longest

      for row <- [none, other, no_station] do
        assert %{predicted_pass_id: nil, max_elevation_deg: nil, elevation_source: nil} = row
      end
    end

    test "the provider's elevation wins, and the predicted pass is still linked", c do
      row = c.a |> contact(c.located, {600, 610}) |> Map.put(:max_elevation_deg, 33.0)

      assert [
               %{
                 max_elevation_deg: 33.0,
                 elevation_source: "provider",
                 predicted_pass_id: "pass-early"
               }
             ] =
               PassGeometry.contacts(c.org, c.mission, [row])
    end

    test "a live hand-started contact is matched up to now", c do
      row = %{contact(c.a, c.located, {621, 0}) | ends_at: nil}

      assert [%{predicted_pass_id: "pass-late", elevation_source: "predicted"}] =
               PassGeometry.contacts(c.org, c.mission, [row], at(625))
    end

    test "a page of 200 contacts is matched in one query", c do
      rows = for i <- 1..200, do: contact(c.a, c.located, {600 + rem(i, 9), 601 + rem(i, 9)})

      {queries, annotated} =
        count_queries(fn -> PassGeometry.contacts(c.org, c.mission, rows) end)

      assert queries == 1
      assert length(annotated) == 200
      assert Enum.all?(annotated, &is_binary(&1.predicted_pass_id))
    end
  end

  describe "opportunities" do
    test "flags a covered window no predicted pass backs, and only that", c do
      opportunities = [
        contact(c.a, c.located, {600, 610}),
        # Covered (element set, located station, inside the horizon) but no pass: flagged.
        contact(c.a, c.located, {700, 710}),
        # The station has no location: prediction can't say.
        contact(c.a, c.unlocated, {700, 710}),
        # Beyond the predicted horizon: prediction can't say.
        contact(c.a, c.located, {8 * 24 * 60, 8 * 24 * 60 + 10})
      ]

      assert [matched, flagged, unlocated, beyond] =
               PassGeometry.opportunities(c.org, c.mission, c.a, opportunities)

      assert %{no_predicted_pass: false, predicted_pass_id: "pass-early"} = matched
      assert matched.tca == at(605)
      assert %{no_predicted_pass: true, predicted_pass_id: nil, tca: nil} = flagged
      assert %{no_predicted_pass: nil} = unlocated
      assert %{no_predicted_pass: nil} = beyond
    end

    test "a spacecraft with no element set is never flagged", c do
      assert [%{no_predicted_pass: nil}] =
               PassGeometry.opportunities(c.org, c.mission, c.b, [
                 contact(c.b, c.located, {700, 710})
               ])
    end

    test "an element set newer than the last run is not flagged until the run catches up", c do
      Store.put_state!(c.org, c.mission, %{
        horizon_end: at(7 * 24 * 60),
        computed_at: DateTime.add(@t0, -60),
        unpropagated: %{},
        not_bracketed: %{}
      })

      assert [%{no_predicted_pass: nil}] =
               PassGeometry.opportunities(c.org, c.mission, c.a, [
                 contact(c.a, c.located, {700, 710})
               ])
    end

    test "a deep-space or decayed spacecraft the last run could not propagate is not flagged",
         c do
      Store.put_state!(c.org, c.mission, %{
        horizon_end: at(7 * 24 * 60),
        computed_at: at(1),
        unpropagated: %{c.a => "deep_space_not_supported"},
        not_bracketed: %{}
      })

      assert [%{no_predicted_pass: nil}] =
               PassGeometry.opportunities(c.org, c.mission, c.a, [
                 contact(c.a, c.located, {700, 710})
               ])
    end
  end

  defp contact(spacecraft_id, station_id, {from_min, to_min}) do
    %{
      spacecraft_id: spacecraft_id,
      station: %{id: station_id},
      starts_at: at(from_min),
      ends_at: at(to_min),
      max_elevation_deg: nil
    }
  end

  defp at(minutes), do: DateTime.add(@t0, minutes * 60)

  defp pass!(org, mission, spacecraft_id, station_id, id, {aos_min, los_min}, elevation) do
    Repo.insert!(%PredictedPassRow{
      predicted_pass_id: id,
      organization_id: org,
      mission_id: mission,
      spacecraft_id: spacecraft_id,
      ground_station_id: station_id,
      element_set_id: "elset-#{id}",
      aos: at(aos_min),
      tca: at(div(aos_min + los_min, 2)),
      los: at(los_min),
      max_elevation_deg: elevation,
      aos_azimuth_deg: 10.0,
      los_azimuth_deg: 200.0,
      computed_at: at(1)
    })
  end

  defp station!(org, mission, name, location) do
    id = "ground_station_#{name}_#{System.unique_integer([:positive])}"

    location =
      case location do
        {lat, lon} -> %{latitude_deg: lat, longitude_deg: lon, height_m: 0.0}
        nil -> nil
      end

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

  defp omm do
    %{
      "EPOCH" => "2026-11-27T12:00:00",
      "MEAN_MOTION" => 15.2,
      "ECCENTRICITY" => 0.0005,
      "INCLINATION" => 97.6,
      "RA_OF_ASC_NODE" => 10.0,
      "ARG_OF_PERICENTER" => 90.0,
      "MEAN_ANOMALY" => 270.0,
      "BSTAR" => 2.0e-5
    }
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

  defp count_queries(fun) do
    owner = self()
    handler = "pass-geometry-#{System.unique_integer([:positive])}"

    :telemetry.attach(
      handler,
      [:cadence, :repo, :query],
      fn _event, _measurements, _meta, _config -> if self() == owner, do: send(owner, :query) end,
      nil
    )

    try do
      result = fun.()
      {drain(0), result}
    after
      :telemetry.detach(handler)
    end
  end

  defp drain(n) do
    receive do
      :query -> drain(n + 1)
    after
      0 -> n
    end
  end
end
