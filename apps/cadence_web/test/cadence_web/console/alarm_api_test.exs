defmodule CadenceWeb.Console.AlarmAPITest do
  use CadenceWeb.ConnCase, async: false

  alias CadenceWeb.MissionReadModelFixtures
  alias CadenceWeb.TestFixtures

  setup do
    org = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!()
    TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org)

    %{user: user, org: org, mission: mission}
  end

  defp get_json(c, path) do
    c.user
    |> TestFixtures.member_conn()
    |> get("/api/v1/missions/#{c.mission.mission_id}" <> path)
  end

  # The runtime's latest alarm states (#451 T3c): HK.counter in a warning, HK.voltage back in normal.
  defp seed_alarm_states(c) do
    now = DateTime.utc_now()

    for {parameter, state, seconds} <- [
          {"HK.counter", "warning", 60},
          {"HK.voltage", "normal", 30}
        ] do
      {1, _} =
        Cadence.Repo.insert_all(Cadence.SemanticObservations.LatestAlarmStateRow, [
          %{
            organization_id: c.org.organization_id,
            mission_id: c.mission.mission_id,
            spacecraft_scope_id: "spacecraft-001",
            spacecraft_id: "spacecraft-001",
            parameter_id: parameter,
            policy_id: "policy-#{parameter}",
            evaluation_id: "eval-#{parameter}",
            transition_id: "transition-#{parameter}",
            effective_state: state,
            generation_time: DateTime.add(now, -seconds, :second),
            receipt_time: DateTime.add(now, -seconds, :second),
            state_document: Cadence.Persistence.JsonDocument.wrap_value(%{}),
            inserted_at: now,
            updated_at: now
          }
        ])
    end
  end

  describe "with live alarm states" do
    setup c do
      MissionReadModelFixtures.seed_mission_read_models(
        c.org.organization_id,
        c.mission.mission_id
      )

      seed_alarm_states(c)
      :ok
    end

    test "takes the point unit from the active binding set", c do
      assert {:ok, _activation} =
               Cadence.Activations.record_binding_set_activation(
                 c.org.organization_id,
                 c.mission.mission_id,
                 "read-models",
                 1,
                 binding_set_content_sha256: String.duplicate("0", 64)
               )

      data = c |> get_json("/alarms") |> json_response(200) |> Map.fetch!("data")

      assert [%{"point" => %{"id" => "HK.counter", "unit" => "count", "description" => nil}}] =
               data["alarms"]
    end

    test "lists the active alarm with its first-crossed time; what a live alarm lacks is null",
         c do
      data = c |> get_json("/alarms") |> json_response(200) |> Map.fetch!("data")

      assert data["summary"]["active"] == 1
      assert data["summary"]["caution"] == 1

      assert [alarm] = data["alarms"]
      assert alarm["spacecraft_id"] == "spacecraft-001"
      assert alarm["point"]["id"] == "HK.counter"
      assert alarm["point"]["unit"] == nil
      assert alarm["point"]["description"] == nil
      assert alarm["severity"] == "caution"
      assert alarm["active"] == true
      # A state is written on a transition: no sampled value, no ground-limit words.
      assert alarm["value"] == nil
      assert alarm["condition"] == nil
      assert alarm["limit_set_name"] == nil
      assert alarm["thresholds"] == nil

      assert is_binary(alarm["first_crossed_at"])
      assert is_binary(alarm["received_at"])
    end

    test "pages by cursor: meta.next_cursor, a total, and every row enriched", c do
      first = c |> get_json("/alarms?state=all&limit=1") |> json_response(200)
      assert [one] = first["data"]["alarms"]
      assert first["data"]["total"] == 2
      assert is_binary(first["meta"]["next_cursor"])

      cursor = first["meta"]["next_cursor"]
      second = c |> get_json("/alarms?state=all&limit=1&cursor=#{cursor}") |> json_response(200)
      assert [other] = second["data"]["alarms"]
      assert other["id"] != one["id"]
      assert second["meta"]["next_cursor"] == nil
      assert second["data"]["summary"] == first["data"]["summary"]
    end

    test "the sister filters: one point, a plane's spacecraft, not me", c do
      by_point = c |> get_json("/alarms?state=all&point_id=HK.counter") |> json_response(200)
      assert Enum.all?(by_point["data"]["alarms"], &(&1["point"]["id"] == "HK.counter"))
      assert by_point["data"]["total"] == length(by_point["data"]["alarms"])

      no_plane = c |> get_json("/alarms?state=all&plane=9") |> json_response(200)
      assert no_plane["data"]["alarms"] == [] and no_plane["data"]["total"] == 0

      excluded =
        c
        |> get_json("/alarms?state=all&exclude_spacecraft_id=spacecraft-001")
        |> json_response(200)

      assert excluded["data"]["alarms"] == []
    end

    test "bad paging parameters are 422s", c do
      for query <- ["limit=0", "limit=201", "limit=x", "plane=x", "cursor=garbage"] do
        assert %{"error" => %{"details" => details}} =
                 c |> get_json("/alarms?" <> query) |> json_response(422)

        assert map_size(details) == 1
      end
    end

    test "state=all includes in-limits points; spacecraft filter narrows", c do
      all = c |> get_json("/alarms?state=all") |> json_response(200)
      assert length(all["data"]["alarms"]) == 2

      none = c |> get_json("/alarms?spacecraft_id=other") |> json_response(200)
      assert none["data"]["alarms"] == []
    end

    test "the fleet row reflects the caution", c do
      data = c |> get_json("/fleet") |> json_response(200) |> Map.fetch!("data")

      assert [row] = data["spacecraft"]
      assert row["limit_state"] == "caution"
      assert row["worst_point"]["point_id"] == "HK.counter"
      assert is_binary(row["last_received_at"])
      assert data["limits"] == %{"configured" => true}
    end
  end

  test "rejects unknown state and severity values", c do
    conn = get_json(c, "/alarms?state=open&severity=red")

    assert %{"error" => %{"code" => "invalid_params", "details" => details}} =
             json_response(conn, 422)

    assert Map.keys(details) |> Enum.sort() == ["severity", "state"]
  end

  test "an empty mission has no alarms", c do
    data = c |> get_json("/alarms") |> json_response(200) |> Map.fetch!("data")
    assert data["alarms"] == []
    assert data["summary"]["active"] == 0
  end
end
