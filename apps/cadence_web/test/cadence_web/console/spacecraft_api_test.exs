defmodule CadenceWeb.Console.SpacecraftAPITest do
  use CadenceWeb.ConnCase, async: true

  alias Cadence.Comms.RoutingRuleRow
  alias Cadence.Reads.ProfileDetail
  alias Cadence.Repo
  alias Cadence.SpacecraftStore.SpacecraftRow
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
      |> get("/api/v1/missions/#{c.mission.mission_id}/spacecraft")
      |> json_response(200)
      |> Map.fetch!("data")

    assert [row] = data["spacecraft"]
    assert row["id"] == craft.spacecraft_id
    assert row["name"] == "EARENDIL-007"
    assert row["routing_rule_count"] == 0
    assert row["ready"] == false
    assert row["last_received_at"] == nil
    # Whether last_received_at had the durable store behind it (api-ops 17deb3c1).
    assert data["telemetry"] in ["ok", "degraded"]
    assert Map.has_key?(row, "norad_id")
    assert Map.has_key?(row, "plane")
  end

  test "sends the SCIDs in use and the next free one (S9, #313)", c do
    TestFixtures.persist_spacecraft!(c.mission, display_name: "EARENDIL-001", scid: 1)
    TestFixtures.persist_spacecraft!(c.mission, display_name: "EARENDIL-003", scid: 3)

    data =
      c.user
      |> TestFixtures.member_conn()
      |> get("/api/v1/missions/#{c.mission.mission_id}/spacecraft")
      |> json_response(200)
      |> Map.fetch!("data")

    assert data["scids_in_use"] == [1, 3]
    assert data["next_free_scid"] == 2
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
      |> get("/api/v1/missions/#{c.mission.mission_id}/spacecraft/#{craft.spacecraft_id}")
      |> json_response(200)
      |> Map.fetch!("data")

    assert data["spacecraft"]["name"] == "EARENDIL-009"
    assert data["telemetry"] in ["ok", "degraded"]
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
      |> get("/api/v1/missions/#{c.mission.mission_id}/spacecraft/nope")

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
      |> get("/api/v1/missions/#{c.mission.mission_id}/profiles/#{profile.spacecraft_type_id}")
      |> json_response(200)
      |> Map.fetch!("data")

    assert data["profile"]["name"] == "Block 1"
    assert data["profile"]["protocols"]["downlink"] == %{"value" => "tm", "label" => "CCSDS TM"}
    assert data["inherit_count"] == 1
    assert data["routing_model"] == "per_spacecraft"
    assert data["rules"] == [] and data["overrides"] == []

    assert [%{"version" => 1, "created_at" => _, "actor" => nil, "spacecraft_count" => _}] =
             data["versions"]

    # No catalog revisions in this mission: the catalog field has no choices.
    catalog = Enum.find(data["sections"], &(&1["key"] == "catalog"))
    # The catalog section also carries handled_apids (L22, 9251b745).
    assert %{"enum" => nil} = Enum.find(catalog["fields"], &(&1["path"] == "catalog_revision_id"))
    assert Enum.any?(catalog["fields"], &(&1["path"] == "handled_apids"))

    # With revisions, the field offers them (fe-setup), as built by the pure builder.
    choices = [%{value: "rev-3", label: "r3 · demo_spacecraft.yaml"}]
    built = ProfileDetail.build(%{profile: profile, catalog_choices: choices})

    catalog_fields = Enum.find(built.sections, &(&1.key == :catalog)).fields
    assert %{enum: ^choices} = Enum.find(catalog_fields, &(&1.path == "catalog_revision_id"))

    # ux U25 / Profile.md P3: "rev N" (never "rN", a change-set revision) and the import date
    # (UTC); the source file only when the date isn't known.
    revision = %{
      revision_number: 4,
      metadata: %{"source_artifact_name" => "earendil.xtce"},
      inserted_at: ~U[2026-11-10 23:30:00Z]
    }

    assert ProfileDetail.catalog_label(revision) == "rev 4 · imported 11-10"
    assert ProfileDetail.catalog_label(%{revision | inserted_at: nil}) == "rev 4 · earendil.xtce"
    assert ProfileDetail.catalog_label(%{revision | inserted_at: nil, metadata: %{}}) == "rev 4"

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
      |> get("/api/v1/missions/#{c.mission.mission_id}/profiles/nope")

    assert json_response(conn, 404)["error"]["code"] == "profile_not_found"
  end

  test "lists profiles with protocol labels and pinned counts", c do
    profile = TestFixtures.persist_spacecraft_profile!(c.mission, display_name: "Block 1")

    data =
      c.user
      |> TestFixtures.member_conn()
      |> get("/api/v1/missions/#{c.mission.mission_id}/profiles")
      |> json_response(200)
      |> Map.fetch!("data")

    assert [row] = data["profiles"]
    assert row["id"] == profile.spacecraft_type_id
    assert row["name"] == "Block 1"
    assert row["downlink_protocol"] == %{"value" => "tm", "label" => "CCSDS TM"}
    assert row["spacecraft_count"] == 0
    assert row["catalog_revision"] == nil
    # As the detail reads them (fe-setup, Profile.md list).
    assert row["override_count"] == 0
    assert %{"version" => 1, "at" => at, "revision" => nil, "actor" => nil} = row["last_change"]
    assert is_binary(at)
  end

  test "readiness for an empty mission blocks on spacecraft and catalog", c do
    data =
      c.user
      |> TestFixtures.member_conn()
      |> get("/api/v1/missions/#{c.mission.mission_id}/readiness")
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

  test "readiness groups route findings across 500 active spacecraft", c do
    mission = c.mission
    profile = TestFixtures.persist_spacecraft_profile!(mission, display_name: "Fleet block")
    now = DateTime.utc_now()

    spacecraft =
      for index <- 1..500 do
        %{
          spacecraft_id: "readiness-fleet-#{index}",
          organization_id: mission.organization_id,
          mission_id: mission.mission_id,
          display_name: "Fleet #{index}",
          scid: index,
          lifecycle_state: "active",
          spacecraft_type_id: if(index in 301..400, do: nil, else: profile.spacecraft_type_id),
          spacecraft_type_version: if(index in 301..400, do: nil, else: profile.version),
          metadata: %{},
          inserted_at: now
        }
      end

    archived = %{
      hd(spacecraft)
      | spacecraft_id: "readiness-archived",
        scid: 501,
        lifecycle_state: "archived"
    }

    Repo.insert_all(SpacecraftRow, [archived | spacecraft])

    routes =
      for {craft, index} <- Enum.with_index(spacecraft, 1),
          {direction, origin, enabled, state} <- readiness_legs(index) do
        readiness_route(craft, direction, origin, enabled, state, now)
      end

    archived_route = readiness_route(archived, "outbound", "spacecraft", true, "active", now)
    Repo.insert_all(RoutingRuleRow, [archived_route | routes])

    data =
      c.user
      |> TestFixtures.member_conn()
      |> get("/api/v1/missions/#{mission.mission_id}/readiness")
      |> json_response(200)
      |> Map.fetch!("data")

    findings = Map.new(data["findings"], &{&1["cause"], &1})

    for {cause, severity, fix} <- [
          {"spacecraft_without_profile", "blocker", "spacecraft_list"},
          {"spacecraft_without_routing_rule", "blocker", "comms"},
          {"spacecraft_without_downlink", "blocker", "comms"},
          {"spacecraft_with_multiple_uplinks", "caution", "comms"},
          {"spacecraft_with_disabled_route", "caution", "comms"}
        ] do
      assert %{
               "severity" => ^severity,
               "affected_count" => 100,
               "fix" => %{"kind" => ^fix}
             } = findings[cause]
    end

    assert %{"status" => "blocker", "secondary_count" => 500} =
             Enum.find(data["areas"], &(&1["key"] == "comms"))
  end

  defp readiness_legs(index) when index <= 100,
    do: [{"outbound", "profile", true, "active"}, {"bidirectional", "spacecraft", true, "active"}]

  defp readiness_legs(index) when index <= 200,
    do: [{"outbound", "profile", true, "active"}]

  defp readiness_legs(index) when index <= 300 do
    [
      {"inbound", "profile", true, "active"},
      {"outbound", "spacecraft", false, "active"},
      {"inbound", "spacecraft", false, "active"}
    ]
  end

  defp readiness_legs(index) when index <= 400,
    do: [{"inbound", "legacy", true, "active"}, {"inbound", "profile", false, "archived"}]

  defp readiness_legs(_index), do: [{"bidirectional", "spacecraft", true, "active"}]

  defp readiness_route(craft, direction, origin, enabled, state, now) do
    %{
      routing_rule_id: "#{craft.spacecraft_id}-#{direction}-#{origin}",
      organization_id: craft.organization_id,
      mission_id: craft.mission_id,
      spacecraft_id: craft.spacecraft_id,
      spacecraft_type_id: if(origin == "profile", do: craft.spacecraft_type_id),
      spacecraft_type_version: if(origin == "profile", do: craft.spacecraft_type_version),
      lifecycle_state: state,
      display_name: "Fleet route",
      purpose_label: "Readiness",
      direction: direction,
      transport_id: "readiness-test-transport",
      transport_version: 1,
      role: "primary",
      enabled: enabled,
      origin: origin,
      metadata: %{},
      inserted_at: now,
      updated_at: now
    }
  end

  test "is not available for another organization's mission", c do
    stranger = TestFixtures.persist_org!() |> TestFixtures.persist_mission!()

    conn =
      c.user
      |> TestFixtures.member_conn()
      |> get("/api/v1/missions/#{stranger.mission_id}/spacecraft")

    assert json_response(conn, 404)["error"]["code"] == "mission_not_found"
  end
end
