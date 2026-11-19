defmodule CadenceWeb.Console.AlarmEpisodeAPITest do
  use CadenceWeb.ConnCase, async: false

  alias CadenceWeb.ControlPlaneApiFixtures
  alias CadenceWeb.TestFixtures

  setup do
    org = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!(display_name: "Mira K.")
    other = TestFixtures.persist_user!(display_name: "Ana R.")
    TestFixtures.grant_membership!(user, org)
    TestFixtures.grant_membership!(other, org)
    mission = TestFixtures.persist_mission!(org)
    ControlPlaneApiFixtures.seed_mission_read_models(org.organization_id, mission.mission_id)

    %{user: user, other: other, org: org, mission: mission}
  end

  defp path(c, suffix),
    do: "/api/console/v1/missions/#{c.mission.mission_id}/alarm-episodes" <> suffix

  defp conn(c), do: TestFixtures.member_conn(c.user)

  defp get_data(c, suffix),
    do: c |> conn() |> get(path(c, suffix)) |> json_response(200) |> Map.fetch!("data")

  defp episode_id(c) do
    [%{"id" => id}] = get_data(c, "")["episodes"]
    id
  end

  describe "GET /alarm-episodes" do
    test "lists the active episode with summary and the viewer's permissions", c do
      data = get_data(c, "")

      assert "alarm.acknowledge" in data["permissions"]
      assert %{"active" => 1, "caution" => %{"new" => 1}} = data["summary"]

      # U69 A6: the mission's newest state change, with its spacecraft.
      assert %{
               "kind" => "raised",
               "spacecraft_id" => "spacecraft-001",
               "at" => _,
               "episode_id" => _
             } =
               data["summary"]["latest_change"]

      assert [episode] = data["episodes"]

      assert %{
               "source" => "ground_limit",
               "status" => "new",
               "severity" => "caution",
               "spacecraft" => %{"id" => "spacecraft-001", "name" => "SC-001"},
               "point" => %{"id" => "HK.counter"},
               "assignee" => nil
             } = episode

      assert Map.has_key?(episode["point"], "unit")
      refute Map.has_key?(episode, "events")

      # U68 R5: the definition that opened it and the sample that triggered it.
      assert %{
               "limit_definition_id" => definition_id,
               "limit_definition_version" => version,
               "limit_set_name" => set_name,
               "trigger" => %{
                 "sample_id" => sample_id,
                 "sample_type" => "telemetry_sample",
                 "point_id" => "HK.counter",
                 "at" => at,
                 "receipt_time" => receipt_time
               }
             } = episode

      assert is_binary(definition_id) and is_integer(version) and is_binary(set_name)
      assert is_binary(sample_id) and is_binary(at)
      # §11c(D) D1: the sample's receipt time, which the one-sample read matches on.
      assert {:ok, _received, 0} = DateTime.from_iso8601(receipt_time)
    end

    test "filters and rejects bad filter values", c do
      assert get_data(c, "?source=catalog_monitoring")["episodes"] == []
      assert get_data(c, "?state=cleared")["episodes"] == []

      body = c |> conn() |> get(path(c, "?state=open&limit=0")) |> json_response(422)

      assert %{"code" => "invalid_params", "details" => %{"state" => _, "limit" => _}} =
               body["error"]

      # U69 A6d: pages by meta.next_cursor; a bad cursor is a 422.
      assert %{"meta" => %{"next_cursor" => nil}} =
               c |> conn() |> get(path(c, "")) |> json_response(200)

      body = c |> conn() |> get(path(c, "?cursor=nope")) |> json_response(422)
      assert %{"details" => %{"cursor" => _}} = body["error"]
    end
  end

  describe "lifecycle commands" do
    test "show includes the event log; acknowledge records it", c do
      id = episode_id(c)

      assert [
               %{"kind" => "raised", "sample" => %{"id" => sample_id, "receipt_time" => received}}
               | _
             ] =
               get_data(c, "/#{id}")["events"]

      assert is_binary(received)

      assert sample_id == get_data(c, "")["episodes"] |> hd() |> get_in(["trigger", "sample_id"])

      data =
        c |> conn() |> post(path(c, "/#{id}/acknowledge"), %{note: "on it"}) |> json_response(200)

      assert %{"status" => "acknowledged", "acknowledged_by" => %{"id" => _}} = data["data"]
      assert Enum.any?(data["data"]["events"], &(&1["kind"] == "acknowledged"))
    end

    test "assign, hand off and note", c do
      id = episode_id(c)

      assigned =
        c
        |> conn()
        |> post(path(c, "/#{id}/assign"), %{user_id: c.other.user_id})
        |> json_response(200)

      assert %{"assignee" => %{"id" => other_id, "name" => "Ana R."}} = assigned["data"]
      assert other_id == c.other.user_id

      unassigned =
        c |> conn() |> post(path(c, "/#{id}/assign"), %{user_id: nil}) |> json_response(200)

      assert unassigned["data"]["assignee"] == nil

      handed =
        c
        |> conn()
        |> post(path(c, "/#{id}/hand-off"), %{to: c.other.user_id, note: "Shift change"})
        |> json_response(200)

      assert Enum.any?(handed["data"]["events"], &(&1["kind"] == "handed_off"))

      noted =
        c |> conn() |> post(path(c, "/#{id}/notes"), %{note: "Trending up"}) |> json_response(200)

      assert Enum.any?(noted["data"]["events"], &(&1["kind"] == "note"))
    end

    test "rejects missing notes, bad assignees and unknown episodes", c do
      id = episode_id(c)

      assert %{"error" => %{"code" => "note_required"}} =
               c |> conn() |> post(path(c, "/#{id}/hand-off"), %{to: nil}) |> json_response(422)

      assert %{"error" => %{"code" => "invalid_params", "details" => %{"user_id" => _}}} =
               c |> conn() |> post(path(c, "/#{id}/assign"), %{}) |> json_response(422)

      assert %{"error" => %{"code" => "assignee_not_member"}} =
               c
               |> conn()
               |> post(path(c, "/#{id}/assign"), %{user_id: "user_stranger"})
               |> json_response(422)

      assert %{"error" => %{"code" => "episode_not_found"}} =
               c
               |> conn()
               |> post(path(c, "/alarm_episode_missing/acknowledge"), %{})
               |> json_response(404)
    end

    test "writes require the CSRF token", c do
      id = episode_id(c)

      conn =
        c
        |> conn()
        |> put_private(:plug_skip_csrf_protection, false)
        |> post(path(c, "/#{id}/acknowledge"), %{})

      assert %{"error" => %{"code" => "invalid_csrf"}} = json_response(conn, 403)
    end
  end

  test "another organization's mission is not found", c do
    stranger = TestFixtures.persist_org!() |> TestFixtures.persist_mission!()

    assert %{"error" => %{"code" => "mission_not_found"}} =
             c
             |> conn()
             |> get("/api/console/v1/missions/#{stranger.mission_id}/alarm-episodes")
             |> json_response(404)
  end
end
