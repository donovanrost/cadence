defmodule CadenceWeb.Console.AlarmAPITest do
  use CadenceWeb.ConnCase, async: false

  alias CadenceWeb.ControlPlaneApiFixtures
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

  describe "with limit evaluations" do
    setup c do
      ControlPlaneApiFixtures.seed_mission_read_models(
        c.org.organization_id,
        c.mission.mission_id
      )

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

    test "lists the active alarm with thresholds and first-crossed time", c do
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
      assert alarm["value"] == 30

      assert alarm["thresholds"] == %{
               "red_low" => nil,
               "yellow_low" => nil,
               "yellow_high" => 20,
               "red_high" => nil
             }

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
