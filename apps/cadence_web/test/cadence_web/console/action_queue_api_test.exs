defmodule CadenceWeb.Console.ActionQueueAPITest do
  use CadenceWeb.ConnCase, async: false

  alias Cadence.Contacts.BookingResolutions.Row
  alias Cadence.Repo
  alias CadenceWeb.ControlPlaneApiFixtures
  alias CadenceWeb.TestFixtures

  setup do
    org = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!()
    TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org)

    %{user: user, org: org, mission: mission}
  end

  defp get_queue(c, mission_id \\ nil) do
    c.user
    |> TestFixtures.member_conn()
    |> get("/api/v1/missions/#{mission_id || c.mission.mission_id}/action-queue")
  end

  test "an empty mission has only setup items, ranked P3", c do
    data = c |> get_queue() |> json_response(200) |> Map.fetch!("data")

    assert is_integer(data["stale_after_s"])
    assert is_integer(data["failure_lookback_s"])
    assert %{"p1" => 0, "p2" => 0, "spacecraft_p1" => 0} = data["counts"]

    assert data["items"] != []
    assert Enum.all?(data["items"], &(&1["priority"] == 3))

    assert %{"kind" => "setup", "state" => "off", "finding" => %{"cause" => "no_spacecraft"}} =
             Enum.find(data["items"], &(&1["id"] == "setup:fleet.no_spacecraft"))
  end

  test "a pass-resolution conflict is an attention row; the empty queue has no resolved", c do
    ControlPlaneApiFixtures.seed_mission_read_models(c.org.organization_id, c.mission.mission_id)

    empty = c |> get_queue() |> json_response(200) |> Map.fetch!("data")
    assert empty["resolved"] == []
    assert Enum.all?(empty["items"], &Map.has_key?(&1, "attention"))

    starts_at = DateTime.add(DateTime.utc_now(), 3600)
    conflict!(c, "br-1", starts_at)

    data = c |> get_queue() |> json_response(200) |> Map.fetch!("data")

    assert %{
             "priority" => 1,
             "kind" => "attention",
             "state" => "critical",
             "source" => "pass_resolution",
             "spacecraft" => [%{"id" => "spacecraft-001", "name" => "SC-001"}],
             "attention" => %{
               "id" => "br-1",
               "conflict" => "contradicts_attestation",
               "state" => "open",
               "contact_id" => "contact-1",
               "station" => %{"ref" => "svb"},
               "provider" => %{"id" => "northlight"}
             }
           } = Enum.find(data["items"], &(&1["id"] == "attention:pass_resolution:br-1"))
  end

  defp conflict!(c, id, starts_at) do
    %{
      booking_resolution_id: id,
      organization_id: c.org.organization_id,
      mission_id: c.mission.mission_id,
      contact_plan_id: "plan-1",
      contact_plan_version: 1,
      contact_plan_execution_item_id: "item-" <> id,
      provider_reservation_id: "res-" <> id,
      scheduled_contact_id: "contact-1",
      spacecraft_id: "spacecraft-001",
      ground_station_ref: "svb",
      provider_id: "northlight",
      starts_at: starts_at,
      ends_at: DateTime.add(starts_at, 600),
      action: "booked",
      outcome: "attested",
      note: "Booked by phone",
      actor_document: %{"kind" => "user", "id" => c.user.user_id, "name" => "Mira K."}
    }
    |> Row.changeset()
    |> Repo.insert!()
    |> Row.conflict_changeset("contradicts_attestation", %{}, DateTime.utc_now())
    |> Repo.update!()
  end

  test "a caution alarm is a P2 item naming the spacecraft and point", c do
    ControlPlaneApiFixtures.seed_mission_read_models(c.org.organization_id, c.mission.mission_id)

    data = c |> get_queue() |> json_response(200) |> Map.fetch!("data")

    assert %{"priority" => 2, "state" => "caution", "count" => 1} =
             item = Enum.find(data["items"], &(&1["kind"] == "alarm"))

    assert item["point"]["id"] == "HK.counter"
    assert item["source"] == "ground_limit"
    assert item["acknowledged"] == 0
    assert data["alarms_truncated"] == false

    assert [
             %{"id" => "spacecraft-001", "name" => "SC-001", "value" => 30, "status" => "new"} =
               member
           ] =
             item["spacecraft"]

    assert is_binary(member["episode_id"])
    assert item["command_requests"] == []
    assert item["due_at"] == nil
    refute Enum.any?(data["items"], &(&1["id"] == "limits_not_configured"))
  end

  test "is not available for another organization's mission", c do
    stranger = TestFixtures.persist_org!() |> TestFixtures.persist_mission!()

    assert %{"error" => %{"code" => "mission_not_found"}} =
             c |> get_queue(stranger.mission_id) |> json_response(404)
  end
end
