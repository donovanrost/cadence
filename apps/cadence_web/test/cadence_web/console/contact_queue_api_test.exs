defmodule CadenceWeb.Console.ContactQueueAPITest do
  @moduledoc "BACKLOG §8 / U11 + U35: missed_pass and station rows in Now's action queue."
  use CadenceWeb.ConnCase, async: false

  alias Cadence.{Accounts, CommandGroupFixtures}
  alias Cadence.Auth.Scope
  alias Cadence.Comms.{GroundStation, GroundStationStore, StationAvailability}
  alias Cadence.Contacts.PassResults.Row
  alias Cadence.Repo
  alias CadenceWeb.TestFixtures

  setup do
    org = TestFixtures.persist_org!()
    admin = TestFixtures.persist_user!(display_name: "Mira K.")
    TestFixtures.grant_membership!(admin, org, role: :organization_admin)
    mission = TestFixtures.persist_mission!(org)
    craft = TestFixtures.persist_spacecraft!(mission, display_name: "EARENDIL-001")

    {:ok, station} =
      GroundStationStore.persist_ground_station(
        org.organization_id,
        GroundStation.new(%{
          ground_station_id: "gs-svb",
          mission_id: mission.mission_id,
          display_name: "Svalbard 1",
          code: "SVB1"
        })
      )

    %{org: org, admin: admin, mission: mission, craft: craft, station: station}
  end

  defp queue(c) do
    c.admin
    |> TestFixtures.member_conn()
    |> get("/api/console/v1/missions/#{c.mission.mission_id}/action-queue")
    |> json_response(200)
    |> Map.fetch!("data")
  end

  defp item(data, kind), do: Enum.find(data["items"], &(&1["kind"] == kind))

  defp missed!(c) do
    %Row{}
    |> Row.changeset(%{
      provider_reservation_id: "res-missed",
      organization_id: c.org.organization_id,
      mission_id: c.mission.mission_id,
      provider_id: "provider-test",
      spacecraft_id: c.craft.spacecraft_id,
      ground_station_ref: "SVB1",
      planned_aos: DateTime.add(DateTime.utc_now(), -3_600),
      planned_los: DateTime.add(DateTime.utc_now(), -3_000),
      planned_seconds: 600,
      outcome: "missed",
      cause: "no_acquisition",
      cause_source: "provider",
      owner: "provider"
    })
    |> Repo.insert!()
  end

  defp book!(c, starts_in_s),
    do:
      CommandGroupFixtures.commandable_pass!(
        c.org.organization_id,
        c.mission.mission_id,
        c.craft.spacecraft_id,
        DateTime.add(DateTime.utc_now(), starts_in_s),
        station_ref: "SVB1"
      )

  defp scope(c) do
    {:ok, membership} = Accounts.fetch_user_membership(c.admin.user_id, c.org.organization_id)

    Scope.new(%{
      user: c.admin,
      organization_id: c.org.organization_id,
      organization: c.org,
      organization_membership: membership
    })
  end

  test "a missed pass with no contact booked in the next 6 h is P1", c do
    missed!(c)
    data = queue(c)

    assert data["missed_pass_horizon_s"] == 21_600

    assert %{
             "id" => id,
             "priority" => 1,
             "state" => "critical",
             "count" => 1,
             "due_at" => nil,
             "next_contact" => nil,
             "spacecraft" => [%{"name" => "EARENDIL-001", "episode_id" => nil}],
             "missed_passes" => [
               %{
                 "reservation_id" => "res-missed",
                 "outcome" => "missed",
                 "cause" => "no_acquisition",
                 "owner" => "provider",
                 "station" => %{"code" => "SVB1"}
               }
             ]
           } = item(data, "missed_pass")

    assert id == "missed_pass:" <> c.craft.spacecraft_id
  end

  test "a missed pass with a contact booked within 6 h is P2 and names it", c do
    missed!(c)
    reservation = book!(c, 3_600)

    assert %{
             "priority" => 2,
             "state" => "caution",
             "next_contact" => %{"reservation_id" => id, "station" => %{"code" => "SVB1"}}
           } = item(queue(c), "missed_pass")

    assert id == reservation.provider_reservation_id
  end

  test "a station window over a booked pass within 2 h is P1", c do
    reservation = book!(c, 3_600)

    {:ok, _} =
      StationAvailability.schedule(scope(c), c.mission.mission_id, "gs-svb", %{
        kind: :maintenance,
        starts_at: DateTime.add(DateTime.utc_now(), 1_800),
        ends_at: DateTime.add(DateTime.utc_now(), 7_200),
        reason: "Antenna 2 bearing"
      })

    assert %{
             "id" => "station:gs-svb",
             "priority" => 1,
             "count" => 1,
             "spacecraft" => [%{"name" => "EARENDIL-001"}],
             "station_issue" => %{
               "station" => %{"id" => "gs-svb", "code" => "SVB1"},
               "window" => %{
                 "kind" => "maintenance",
                 "ends_at" => ends_at,
                 "source" => "operator"
               },
               "affected" => [%{"reservation_id" => affected}]
             }
           } = item(queue(c), "station")

    assert affected == reservation.provider_reservation_id
    assert is_binary(ends_at)
  end

  test "a station window over a booked pass further than 2 h out is P2", c do
    book!(c, 5 * 3_600)

    {:ok, _} =
      StationAvailability.schedule(scope(c), c.mission.mission_id, "gs-svb", %{
        kind: :outage,
        starts_at: DateTime.add(DateTime.utc_now(), 4 * 3_600),
        eta: DateTime.add(DateTime.utc_now(), 8 * 3_600),
        reason: "Power"
      })

    assert %{
             "priority" => 2,
             "state" => "caution",
             "station_issue" => %{"window" => %{"kind" => "outage"}}
           } =
             item(queue(c), "station")
  end

  test "rows of other kinds carry the new fields as null", c do
    data = queue(c)

    assert Enum.all?(
             data["items"],
             &(Map.has_key?(&1, "missed_passes") and &1["station_issue"] == nil)
           )
  end
end
