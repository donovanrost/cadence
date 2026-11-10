defmodule CadenceWeb.Console.SpacecraftAPITest do
  use CadenceWeb.ConnCase, async: true

  alias CadenceWeb.TestFixtures

  setup do
    org = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!()
    TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org)
    %{user: user, mission: mission}
  end

  test "lists spacecraft with identity, geometry and readiness", c do
    craft = TestFixtures.persist_spacecraft!(c.mission, display_name: "EARENDIL-007")

    data =
      c.user
      |> TestFixtures.member_conn()
      |> get("/api/console/v1/missions/#{c.mission.mission_id}/spacecraft")
      |> json_response(200)
      |> Map.fetch!("data")

    assert [row] = data["spacecraft"]
    assert row["id"] == craft.spacecraft_id
    assert row["name"] == "EARENDIL-007"
    assert row["routing_rule_count"] == 0
    assert row["ready"] == false
    assert row["last_received_at"] == nil
    assert Map.has_key?(row, "norad_id")
    assert Map.has_key?(row, "plane")
  end

  test "shows one spacecraft with profile, routing rules and readiness checks", c do
    profile = TestFixtures.persist_spacecraft_profile!(c.mission, display_name: "Block 1")

    craft =
      TestFixtures.persist_spacecraft!(c.mission,
        display_name: "EARENDIL-009",
        spacecraft_type_id: profile.spacecraft_type_id,
        spacecraft_type_version: profile.version
      )

    data =
      c.user
      |> TestFixtures.member_conn()
      |> get("/api/console/v1/missions/#{c.mission.mission_id}/spacecraft/#{craft.spacecraft_id}")
      |> json_response(200)
      |> Map.fetch!("data")

    assert data["spacecraft"]["name"] == "EARENDIL-009"
    assert data["routing_rules"] == []
    assert data["configuration"] == nil
    assert data["readiness"]["ready"] == false

    checks = Map.new(data["readiness"]["checks"], &{&1["key"], &1["status"]})
    assert checks["routing"] == "blocker"
    assert checks["telemetry"] == "not_set_up"
  end

  test "an unknown spacecraft is not found", c do
    conn =
      c.user
      |> TestFixtures.member_conn()
      |> get("/api/console/v1/missions/#{c.mission.mission_id}/spacecraft/nope")

    assert json_response(conn, 404)["error"]["code"] == "spacecraft_not_found"
  end

  test "profile detail: schema-driven sections with values, counts and versions", c do
    profile = TestFixtures.persist_spacecraft_profile!(c.mission, display_name: "Block 1")

    TestFixtures.persist_spacecraft!(c.mission,
      spacecraft_type_id: profile.spacecraft_type_id,
      spacecraft_type_version: profile.version
    )

    data =
      c.user
      |> TestFixtures.member_conn()
      |> get(
        "/api/console/v1/missions/#{c.mission.mission_id}/profiles/#{profile.spacecraft_type_id}"
      )
      |> json_response(200)
      |> Map.fetch!("data")

    assert data["profile"]["name"] == "Block 1"
    assert data["profile"]["protocols"]["downlink"] == %{"value" => "tm", "label" => "CCSDS TM"}
    assert data["inherit_count"] == 1
    assert data["routing_model"] == "per_spacecraft"
    assert data["rules"] == [] and data["overrides"] == []
    assert [%{"version" => 1, "created_at" => _, "actor" => nil}] = data["versions"]

    framing = Enum.find(data["sections"], &(&1["key"] == "framing"))
    frame_size = Enum.find(framing["fields"], &(&1["path"] == "frame_parameters.frame_size"))

    assert %{
             "type" => "integer",
             "unit" => "bytes",
             "value" => 1024,
             "runtime_impact" => "generation"
           } =
             frame_size

    downlink = Enum.find(framing["fields"], &(&1["path"] == "downlink_protocol"))
    assert downlink["value"] == "tm"
    assert %{"value" => "aos", "label" => "CCSDS AOS"} in downlink["enum"]
  end

  test "an unknown profile is not found", c do
    conn =
      c.user
      |> TestFixtures.member_conn()
      |> get("/api/console/v1/missions/#{c.mission.mission_id}/profiles/nope")

    assert json_response(conn, 404)["error"]["code"] == "profile_not_found"
  end

  test "lists profiles with protocol labels and pinned counts", c do
    profile = TestFixtures.persist_spacecraft_profile!(c.mission, display_name: "Block 1")

    data =
      c.user
      |> TestFixtures.member_conn()
      |> get("/api/console/v1/missions/#{c.mission.mission_id}/profiles")
      |> json_response(200)
      |> Map.fetch!("data")

    assert [row] = data["profiles"]
    assert row["id"] == profile.spacecraft_type_id
    assert row["name"] == "Block 1"
    assert row["downlink_protocol"] == %{"value" => "tm", "label" => "CCSDS TM"}
    assert row["spacecraft_count"] == 0
    assert row["catalog_revision"] == nil
  end

  test "readiness for an empty mission blocks on spacecraft and catalog", c do
    data =
      c.user
      |> TestFixtures.member_conn()
      |> get("/api/console/v1/missions/#{c.mission.mission_id}/readiness")
      |> json_response(200)
      |> Map.fetch!("data")

    assert Enum.map(data["areas"], & &1["key"]) ==
             ~w(fleet catalog comms stations data_sources apps)

    fleet = Enum.find(data["areas"], &(&1["key"] == "fleet"))
    assert fleet["status"] == "blocker"
    assert fleet["count"] == 0
    assert data["verdict"]["blocker"] >= 2
    # Nothing applied yet: an empty change feed (R2), not null.
    assert is_list(data["recent_changes"])

    causes = Enum.map(data["findings"], & &1["cause"])
    assert "no_spacecraft" in causes
    assert "no_catalog" in causes

    assert %{"kind" => "spacecraft_new", "id" => nil, "label" => nil} =
             Enum.find(data["findings"], &(&1["cause"] == "no_spacecraft"))["fix"]
  end

  test "is not available for another organization's mission", c do
    stranger = TestFixtures.persist_org!() |> TestFixtures.persist_mission!()

    conn =
      c.user
      |> TestFixtures.member_conn()
      |> get("/api/console/v1/missions/#{stranger.mission_id}/spacecraft")

    assert json_response(conn, 404)["error"]["code"] == "mission_not_found"
  end
end
