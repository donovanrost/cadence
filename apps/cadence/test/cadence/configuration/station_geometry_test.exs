defmodule Cadence.Configuration.StationGeometryTest do
  @moduledoc """
  A ground station's location and elevation mask (#890, slice 2 of #732): the mission's own
  location goes through the `ground_station` change-set kind; a provider's reported location is
  kept apart and never overwrites it; reads use the mission's when set, else the provider's.
  """
  use Cadence.DataCase, async: false

  import Ecto.Query

  import Cadence.ConfigurationFixtures

  alias Cadence.Comms.{GroundStation, GroundStationStore, StationLocations}
  alias Cadence.Control.Configuration
  alias Cadence.Jobs.BackgroundJobRow
  alias Cadence.Reads.{CommsDirectory, ConfigKindSchema}

  @synced_at ~U[2026-11-27 12:00:00.000000Z]

  setup do
    on_exit(with_approval_required(false))
    %{organization_id: org, mission_id: mission} = configuration_mission("station-geometry")
    %{org: org, mission: mission, alice: member_scope(org, :member, "Alice")}
  end

  describe "the mission's location through the change-set kind" do
    test "a geometry change or an archive asks for that station's pass recompute (#891)", ctx do
      [id] =
        apply_ops(ctx, "Svalbard", [
          create(%{"display_name" => "Svalbard", "latitude_deg" => 78.23, "longitude_deg" => 15})
        ])

      assert station_jobs(ctx.mission) == [[id]]

      apply_ops(ctx, "Rename", [edit(id, [{"display_name", "SvalSat"}])])
      assert station_jobs(ctx.mission) == [[id]]

      apply_ops(ctx, "Mask", [edit(id, [{"elevation_mask_deg", 10}])])
      apply_ops(ctx, "Archive", [delete(id)])
      assert station_jobs(ctx.mission) == [[id], [id], [id]]
    end

    test "is stored with its mask; a missing height is 0 m and the mask defaults to 5°", ctx do
      [id] =
        apply_ops(ctx, "Svalbard", [
          create(%{"display_name" => "Svalbard", "latitude_deg" => 78.23, "longitude_deg" => 15})
        ])

      assert {:ok, %GroundStation{} = station} =
               GroundStationStore.fetch_ground_station(ctx.org, ctx.mission, id)

      assert station.location == %{latitude_deg: 78.23, longitude_deg: 15.0, height_m: 0.0}
      assert station.elevation_mask_deg == 5.0

      apply_ops(ctx, "Mask", [edit(id, [{"elevation_mask_deg", 10}, {"height_m", 450}])])

      assert {:ok, %{location: %{height_m: 450.0}, elevation_mask_deg: 10.0}} =
               GroundStationStore.fetch_ground_station(ctx.org, ctx.mission, id)
    end

    test "can be cleared, which leaves the mask", ctx do
      [id] =
        apply_ops(ctx, "Troll", [
          create(%{
            "display_name" => "Troll",
            "latitude_deg" => -72.01,
            "longitude_deg" => 2.53,
            "height_m" => 1270,
            "elevation_mask_deg" => 7.5
          })
        ])

      apply_ops(ctx, "Clear", [
        edit(id, [{"latitude_deg", nil}, {"longitude_deg", nil}, {"height_m", nil}])
      ])

      assert {:ok, %{location: nil, elevation_mask_deg: 7.5}} =
               GroundStationStore.fetch_ground_station(ctx.org, ctx.mission, id)
    end

    test "refuses out-of-range values and a half-entered location, naming the field", ctx do
      cases = [
        {%{"latitude_deg" => 91, "longitude_deg" => 0}, "latitude_deg"},
        {%{"latitude_deg" => 0, "longitude_deg" => -181}, "longitude_deg"},
        {%{"latitude_deg" => 0, "longitude_deg" => 0, "height_m" => 20_000}, "height_m"},
        {%{"elevation_mask_deg" => 90}, "elevation_mask_deg"},
        {%{"elevation_mask_deg" => 89.95}, "elevation_mask_deg"},
        {%{"elevation_mask_deg" => -1}, "elevation_mask_deg"},
        {%{"latitude_deg" => 10}, "longitude_deg"},
        {%{"longitude_deg" => 10}, "latitude_deg"},
        {%{"height_m" => 10}, "height_m"},
        {%{"latitude_deg" => "north", "longitude_deg" => 0}, "latitude_deg"}
      ]

      for {geometry, path} <- cases do
        op = create(Map.put(geometry, "display_name", "Bad"))

        # A create is refused as it is normalized, before preview.
        assert {:error, {:invalid_op, 0, errors}} =
                 Configuration.preview(ctx.alice, ctx.mission, {:ops, [op]})

        assert Enum.any?(errors, &(&1.path == path)), "#{inspect(geometry)}: #{inspect(errors)}"
      end
    end

    test "the form offers the four fields as numbers with their ranges", ctx do
      {:ok, fields} = ConfigKindSchema.fields("ground_station", ctx.org, ctx.mission)
      by_path = Map.new(fields, &{&1.path, &1})

      assert %{type: :number, range: %{min: -90, max: 90}, unit: "°"} = by_path["latitude_deg"]
      assert %{type: :number, range: %{min: -180, max: 180}} = by_path["longitude_deg"]
      assert %{type: :number, unit: "m"} = by_path["height_m"]
      assert %{type: :number, default: 5.0} = by_path["elevation_mask_deg"]
    end
  end

  describe "a provider's reported location" do
    setup ctx do
      [plain, owned] =
        apply_ops(ctx, "Stations", [
          create(%{"display_name" => "Hawaii"}),
          create(%{
            "display_name" => "Svalbard",
            "latitude_deg" => 78.23,
            "longitude_deg" => 15.41,
            "height_m" => 450
          })
        ])

      %{plain: plain, owned: owned}
    end

    test "fills a station the mission hasn't located, and never overwrites one it has", ctx do
      reports = [
        station(ctx.plain, %{"latitude_deg" => 19.0136, "longitude_deg" => -155.663}),
        station(ctx.owned, %{"latitude_deg" => 1.0, "longitude_deg" => 2.0, "height_m" => 3})
      ]

      assert {:ok, %{recorded: 2}} =
               StationLocations.record_provider_reports(
                 ctx.org,
                 ctx.mission,
                 "sim",
                 reports,
                 @synced_at
               )

      {:ok, plain} = GroundStationStore.fetch_ground_station(ctx.org, ctx.mission, ctx.plain)
      assert plain.location == nil

      assert %{latitude_deg: 19.0136, height_m: +0.0, provider_id: "sim"} =
               plain.provider_location

      assert GroundStation.effective_location(plain) ==
               %{latitude_deg: 19.0136, longitude_deg: -155.663, height_m: 0.0, source: :provider}

      {:ok, owned} = GroundStationStore.fetch_ground_station(ctx.org, ctx.mission, ctx.owned)
      assert owned.location == %{latitude_deg: 78.23, longitude_deg: 15.41, height_m: 450.0}
      assert %{latitude_deg: 1.0} = owned.provider_location
      assert %{source: :mission, latitude_deg: 78.23} = GroundStation.effective_location(owned)

      # A later admin edit keeps the provider's report.
      apply_ops(ctx, "Rename", [edit(ctx.owned, [{"display_name", "SvalSat"}])])
      {:ok, owned} = GroundStationStore.fetch_ground_station(ctx.org, ctx.mission, ctx.owned)
      assert %{latitude_deg: 1.0} = owned.provider_location
      assert owned.location.latitude_deg == 78.23
    end

    test "skips unknown stations, malformed and out-of-range locations, and unchanged ones",
         ctx do
      reports = [
        station("station-nowhere", %{"latitude_deg" => 1, "longitude_deg" => 1}),
        station(ctx.plain, %{"latitude_deg" => 95, "longitude_deg" => 1}),
        station(ctx.plain, %{"latitude_deg" => "1", "longitude_deg" => 1}),
        station(ctx.plain, nil),
        %{"name" => "no id"}
      ]

      assert {:ok, %{recorded: 0}} =
               StationLocations.record_provider_reports(
                 ctx.org,
                 ctx.mission,
                 "sim",
                 reports,
                 @synced_at
               )

      report = [station(ctx.plain, %{"latitude_deg" => 1, "longitude_deg" => 2})]

      assert {:ok, %{recorded: 1}} =
               StationLocations.record_provider_reports(
                 ctx.org,
                 ctx.mission,
                 "sim",
                 report,
                 @synced_at
               )

      later = DateTime.add(@synced_at, 3600)

      assert {:ok, %{recorded: 0}} =
               StationLocations.record_provider_reports(
                 ctx.org,
                 ctx.mission,
                 "sim",
                 report,
                 later
               )

      # A repeated identical report changes nothing but refreshes when it was last reported.
      {:ok, plain} = GroundStationStore.fetch_ground_station(ctx.org, ctx.mission, ctx.plain)
      assert plain.provider_location.reported_at == later

      assert {:error, :invalid_provider_inventory} =
               StationLocations.record_provider_reports(
                 ctx.org,
                 ctx.mission,
                 "sim",
                 %{},
                 @synced_at
               )
    end

    test "a full sync clears this provider's report when the location or the station is gone",
         ctx do
      both = [
        station(ctx.plain, %{"latitude_deg" => 19.0, "longitude_deg" => -155.0}),
        station(ctx.owned, %{"latitude_deg" => 1.0, "longitude_deg" => 2.0})
      ]

      {:ok, %{recorded: 2}} =
        StationLocations.record_provider_reports(ctx.org, ctx.mission, "sim", both, @synced_at)

      {:ok, plain} = GroundStationStore.fetch_ground_station(ctx.org, ctx.mission, ctx.plain)
      assert plain.provider_location.reported_at == @synced_at

      # plain is listed without a location; owned has left the inventory.
      assert {:ok, %{recorded: 0, cleared: 2}} =
               StationLocations.record_provider_reports(
                 ctx.org,
                 ctx.mission,
                 "sim",
                 [station(ctx.plain, nil)],
                 @synced_at
               )

      {:ok, plain} = GroundStationStore.fetch_ground_station(ctx.org, ctx.mission, ctx.plain)
      assert plain.provider_location == nil
      assert GroundStation.effective_location(plain) == nil

      # The mission's own location is never cleared.
      {:ok, owned} = GroundStationStore.fetch_ground_station(ctx.org, ctx.mission, ctx.owned)
      assert owned.provider_location == nil
      assert owned.location.latitude_deg == 78.23
    end

    test "a sync from one provider leaves another provider's report alone", ctx do
      report = [station(ctx.plain, %{"latitude_deg" => 19.0, "longitude_deg" => -155.0})]

      {:ok, _} =
        StationLocations.record_provider_reports(ctx.org, ctx.mission, "sim", report, @synced_at)

      assert {:ok, %{recorded: 0, cleared: 0}} =
               StationLocations.record_provider_reports(
                 ctx.org,
                 ctx.mission,
                 "other",
                 [],
                 @synced_at
               )

      {:ok, plain} = GroundStationStore.fetch_ground_station(ctx.org, ctx.mission, ctx.plain)
      assert %{provider_id: "sim", latitude_deg: 19.0} = plain.provider_location
    end

    test "a clear only removes the clearing provider's report, even after a snapshot", ctx do
      # Provider A's sync read its snapshot when the station still carried A's report; provider
      # B reported it before A's clear ran. The clear must leave B's report.
      a = [station(ctx.plain, %{"latitude_deg" => 1.0, "longitude_deg" => 2.0})]

      {:ok, _} =
        StationLocations.record_provider_reports(ctx.org, ctx.mission, "a", a, @synced_at)

      b = [station(ctx.plain, %{"latitude_deg" => 19.0, "longitude_deg" => -155.0})]

      {:ok, _} =
        StationLocations.record_provider_reports(ctx.org, ctx.mission, "b", b, @synced_at)

      assert StationLocations.clear_reports(ctx.org, ctx.mission, "a", [ctx.plain]) == 0

      {:ok, plain} = GroundStationStore.fetch_ground_station(ctx.org, ctx.mission, ctx.plain)
      assert %{provider_id: "b", latitude_deg: 19.0} = plain.provider_location

      assert StationLocations.clear_reports(ctx.org, ctx.mission, "b", [ctx.plain]) == 1
    end

    test "the station read shows the location in use, its source, the report and the mask", ctx do
      report = [station(ctx.plain, %{"latitude_deg" => 19.0, "longitude_deg" => -155.0})]

      {:ok, _} =
        StationLocations.record_provider_reports(ctx.org, ctx.mission, "sim", report, @synced_at)

      rows = Map.new(CommsDirectory.stations(ctx.org, ctx.mission), &{&1.id, &1})

      assert %{
               location: %{latitude_deg: 19.0, source: :provider},
               provider_location: %{latitude_deg: 19.0, reported_at: %DateTime{}},
               elevation_mask_deg: 5.0
             } = rows[ctx.plain]

      assert %{location: %{latitude_deg: 78.23, source: :mission}, provider_location: nil} =
               rows[ctx.owned]
    end
  end

  defp station(id, location), do: %{"id" => id, "name" => id, "location" => location}

  defp create(document), do: %{kind: "ground_station", action: :create, document: document}

  defp delete(id), do: %{kind: "ground_station", action: :delete, entity_id: id}

  defp station_jobs(mission) do
    BackgroundJobRow
    |> where([j], j.mission_id == ^mission and j.job_type == "pass_prediction")
    |> Repo.all()
    |> Enum.map(&BackgroundJobRow.to_domain/1)
    |> Enum.filter(&(&1.payload["kind"] == "station"))
    |> Enum.map(& &1.payload["ground_station_ids"])
  end

  defp edit(id, changes),
    do: %{
      kind: "ground_station",
      action: :update,
      entity_id: id,
      changes: Enum.map(changes, fn {path, value} -> %{path: path, value: value} end)
    }

  defp apply_ops(%{alice: alice, mission: mission}, summary, ops) do
    {:ok, staged} = Configuration.stage(alice, mission, %{summary: summary}, ops)

    {:ok, %{state: :applied}} =
      Configuration.submit(alice, mission, staged.change_set_id, %{
        reason: "Test change: " <> summary,
        expected_version: staged.version
      })

    staged.entity_ids
  end
end
