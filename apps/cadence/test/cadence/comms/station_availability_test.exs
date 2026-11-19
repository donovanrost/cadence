defmodule Cadence.Comms.StationAvailabilityTest do
  use Cadence.DataCase, async: false

  import Cadence.ConfigurationFixtures

  alias Cadence.Comms.{GroundStation, GroundStationStore, StationAvailability}
  alias Cadence.Comms.StationAvailability.ProviderReports
  alias Cadence.ContactPlanning.{ContactRequirementVersion, RequirementEvaluator}

  setup do
    %{organization_id: org, mission_id: mission} = configuration_mission("avail")
    station_id = unique("svb")

    {:ok, _} =
      GroundStationStore.persist_ground_station(
        org,
        GroundStation.new(%{
          ground_station_id: station_id,
          mission_id: mission,
          display_name: "Svalbard",
          code: "SVB"
        })
      )

    %{org: org, mission: mission, station: station_id, alice: member_scope(org, :member, "Alice")}
  end

  defp at(hours), do: DateTime.add(~U[2026-11-10 00:00:00.000000Z], round(hours * 3600), :second)

  test "a station with no windows is up, and says why", ctx do
    assert {:ok, %{state: :up, basis: "no reported windows", eta: nil, source: nil}} =
             StationAvailability.status(ctx.alice, ctx.mission, ctx.station, at(1))
  end

  test "maintenance makes the station down for its window, then up again", ctx do
    assert {:ok, %{id: window_id, kind: :maintenance, created_by: %{"name" => "Alice"}}} =
             StationAvailability.schedule(ctx.alice, ctx.mission, ctx.station, %{
               kind: :maintenance,
               starts_at: at(2),
               ends_at: at(4),
               reason: "Antenna 2 bearing"
             })

    assert {:ok, %{state: :up, windows: [%{id: ^window_id}]}} =
             StationAvailability.status(ctx.alice, ctx.mission, ctx.station, at(1))

    assert {:ok, %{state: :down, since: since, eta: eta, source: :operator}} =
             StationAvailability.status(ctx.alice, ctx.mission, ctx.station, at(3))

    assert since == at(2) and eta == at(4)

    assert {:error, :window_overlaps} =
             StationAvailability.schedule(ctx.alice, ctx.mission, ctx.station, %{
               kind: :maintenance,
               starts_at: at(3),
               ends_at: at(5)
             })

    assert {:ok, %{cleared_at: %DateTime{}}} =
             StationAvailability.clear(ctx.alice, ctx.mission, window_id, "Done early")

    assert {:ok, %{state: :up}} =
             StationAvailability.status(ctx.alice, ctx.mission, ctx.station, at(3))

    assert {:error, :window_cleared} =
             StationAvailability.clear(ctx.alice, ctx.mission, window_id)
  end

  test "an open outage stays down with an eta only when one is reported", ctx do
    {:ok, _} =
      StationAvailability.schedule(ctx.alice, ctx.mission, ctx.station, %{
        kind: :outage,
        starts_at: at(0)
      })

    assert {:ok, %{state: :down, eta: nil}} =
             StationAvailability.status(ctx.alice, ctx.mission, ctx.station, at(100))
  end

  test "provider reports upsert by their reference and mark the source", ctx do
    report = %{
      ground_station_id: ctx.station,
      kind: :degraded,
      starts_at: at(1),
      ends_at: at(2),
      provider_ref: "ksat-77",
      provider: "simulator"
    }

    {:ok, _} = StationAvailability.record_provider_report(ctx.org, ctx.mission, report)

    {:ok, _} =
      StationAvailability.record_provider_report(ctx.org, ctx.mission, %{report | ends_at: at(6)})

    assert {:ok, [%{source: :provider, to: to, reported_by: %{"id" => "simulator"}}]} =
             StationAvailability.windows(ctx.alice, ctx.mission, ctx.station, at(0), at(10))

    assert to == at(6)

    assert {:ok, %{state: :degraded}} =
             StationAvailability.status(ctx.alice, ctx.mission, ctx.station, at(3))
  end

  test "a provider sync records reported windows and clears ones it stops reporting", ctx do
    stations = fn windows ->
      [
        %{"id" => ctx.station, "availability_windows" => windows},
        %{"id" => "not-in-cadence", "availability_windows" => [window("x", 1, 2)]}
      ]
    end

    assert {:ok, %{recorded: 2, cleared: 0}} =
             ProviderReports.sync(
               ctx.org,
               ctx.mission,
               "provider-a",
               stations.([window("a", 1, 3), window("b", 5, 6)])
             )

    assert {:ok, %{state: :down, source: :provider, reported_by: %{"id" => "provider-a"}}} =
             StationAvailability.status(ctx.alice, ctx.mission, ctx.station, at(2))

    assert {:ok, %{recorded: 1, cleared: 1}} =
             ProviderReports.sync(
               ctx.org,
               ctx.mission,
               "provider-a",
               stations.([window("b", 5, 6)])
             )

    assert {:ok, %{state: :up}} =
             StationAvailability.status(ctx.alice, ctx.mission, ctx.station, at(2))

    assert {:ok, %{recorded: 2}} =
             ProviderReports.sync(
               ctx.org,
               ctx.mission,
               "provider-a",
               stations.([window("a", 1, 3), window("b", 5, 6)])
             )

    assert {:ok, %{state: :down}} =
             StationAvailability.status(ctx.alice, ctx.mission, ctx.station, at(2))
  end

  test "a provider sync skips malformed windows and refuses a malformed inventory (L12 defect 2)",
       ctx do
    malformed = [
      "not-a-window",
      %{window("map-kind", 1, 2) | "kind" => %{"x" => 1}},
      %{window("map-id", 1, 2) | "id" => %{"x" => 1}}
    ]

    # A window whose only fault is a non-text reason is kept without the reason.
    bad_reason = Map.put(window("map-reason", 4, 5), "reason", %{"x" => 1})

    assert {:ok, %{recorded: 2}} =
             ProviderReports.sync(ctx.org, ctx.mission, "provider-a", [
               %{
                 "id" => ctx.station,
                 "availability_windows" => [window("a", 1, 3), bad_reason | malformed]
               },
               %{"id" => ctx.station, "availability_windows" => %{"not" => "a list"}},
               "not-a-station"
             ])

    assert {:error, :invalid_provider_inventory} =
             ProviderReports.sync(ctx.org, ctx.mission, "provider-a", %{"not" => "a list"})

    # A refused inventory clears nothing.
    assert {:ok, %{state: :down}} =
             StationAvailability.status(ctx.alice, ctx.mission, ctx.station, at(2))
  end

  defp window(id, from, to) do
    %{
      "id" => id,
      "kind" => "outage",
      "starts_at" => DateTime.to_iso8601(at(from)),
      "ends_at" => DateTime.to_iso8601(at(to))
    }
  end

  test "planning treats opportunities during outage or maintenance as ineligible", ctx do
    {:ok, _} =
      StationAvailability.schedule(ctx.alice, ctx.mission, ctx.station, %{
        kind: :outage,
        starts_at: at(2),
        ends_at: at(4)
      })

    {:ok, _} =
      StationAvailability.schedule(ctx.alice, ctx.mission, ctx.station, %{
        kind: :degraded,
        starts_at: at(5),
        ends_at: at(6)
      })

    windows = StationAvailability.blocking_windows(ctx.org, ctx.mission, at(0), at(24))

    requirement =
      struct(ContactRequirementVersion,
        earliest_start: at(0),
        latest_end: at(24),
        service_direction: :downlink,
        success_measure: :any_contact,
        provider_constraints_document: %{},
        station_constraints_document: %{}
      )

    evaluate = fn starts, ends ->
      opportunity = %{
        "starts_at" => DateTime.to_iso8601(at(starts)),
        "ends_at" => DateTime.to_iso8601(at(ends)),
        "expires_at" => DateTime.to_iso8601(at(48)),
        "ground_station_ref" => ctx.station,
        "availability" => "available"
      }

      RequirementEvaluator.evaluate_opportunity(requirement, opportunity, %{},
        now: at(0),
        unavailable_windows: windows
      )
    end

    assert Enum.any?(evaluate.(3, 3.2)["hard_failures"], &(&1["code"] == "station_unavailable"))
    refute Enum.any?(evaluate.(5, 5.2)["hard_failures"], &(&1["code"] == "station_unavailable"))
    refute Enum.any?(evaluate.(7, 7.2)["hard_failures"], &(&1["code"] == "station_unavailable"))
  end

  test "outsiders can't read or schedule", ctx do
    outsider = member_scope(ctx.org) |> Map.put(:organization_membership, nil)
    assert {:error, :forbidden} = StationAvailability.status(outsider, ctx.mission, ctx.station)

    assert {:error, :forbidden} =
             StationAvailability.schedule(outsider, ctx.mission, ctx.station, %{
               kind: :outage,
               starts_at: at(0)
             })
  end
end
