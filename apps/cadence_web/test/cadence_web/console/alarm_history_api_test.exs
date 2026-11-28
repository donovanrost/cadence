defmodule CadenceWeb.Console.AlarmHistoryAPITest do
  @moduledoc "Investigate History: a spacecraft's alarm episodes and one episode's earlier ones."
  use CadenceWeb.ConnCase, async: false

  import Ecto.Query

  alias Cadence.Alarms.{EpisodeEventRow, EpisodeRow}
  alias Cadence.Repo
  alias CadenceWeb.MissionReadModelFixtures
  alias CadenceWeb.TestFixtures

  @sc "spacecraft-001"
  @point "HK.counter"

  setup do
    org = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!(display_name: "Mira K.")
    TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org)
    MissionReadModelFixtures.seed_mission_read_models(org.organization_id, mission.mission_id)
    c = %{user: user, org: org, mission: mission}

    # The seeded active episode's time comes from fixture telemetry; make it an hour ago.
    {1, _} =
      Repo.update_all(
        from(e in EpisodeRow, where: e.mission_id == ^mission.mission_id),
        set: [opened_at: DateTime.add(DateTime.utc_now(), -3_600)]
      )

    # Earlier episodes of the seeded alarm (days ago, duration s, how it cleared), one on
    # another point, and one past the 90-day horizon.
    past!(c, @point, 2, 60, "in_limits")
    past!(c, @point, 10, 120, "reconcile")
    past!(c, @point, 40, 300, "in_limits")
    past!(c, @point, 100, 600, "in_limits")
    past!(c, "HK.other", 1, 30, "in_limits")
    c
  end

  defp past!(c, point, days_ago, duration_s, cause) do
    opened = DateTime.add(DateTime.utc_now(), -days_ago * 86_400)
    cleared = DateTime.add(opened, duration_s)
    id = "alarm_episode_past_#{point}_#{days_ago}"

    Repo.insert!(%EpisodeRow{
      episode_id: id,
      organization_id: c.org.organization_id,
      mission_id: c.mission.mission_id,
      spacecraft_id: @sc,
      spacecraft_scope_id: @sc,
      source: "ground_limit",
      subject_key: point,
      parameter_ref: point,
      point_name: point,
      severity: "critical",
      peak_severity: "critical",
      source_state: "red_low",
      state: "cleared",
      opened_at: opened,
      first_value: %{"value" => 21.5},
      last_value: %{"value" => 24.2},
      last_observed_at: cleared,
      last_evaluated_at: cleared,
      cleared_at: cleared
    })

    Repo.insert!(%EpisodeEventRow{
      event_id: "alarm_event_#{id}",
      episode_id: id,
      organization_id: c.org.organization_id,
      mission_id: c.mission.mission_id,
      kind: "cleared",
      at: cleared,
      payload: %{"cause" => cause}
    })
  end

  defp base(c), do: "/api/v1/missions/#{c.mission.mission_id}"

  defp get_json(c, path, status \\ 200),
    do: c.user |> TestFixtures.member_conn() |> get(base(c) <> path) |> json_response(status)

  defp active_id(c) do
    [%{"id" => id}] = get_json(c, "/alarm-episodes")["data"]["episodes"]
    id
  end

  test "an episode's history pages the same alarm's earlier episodes, with counts and median",
       c do
    id = active_id(c)
    data = get_json(c, "/alarm-episodes/#{id}/history?limit=2")["data"]

    assert %{"id" => ^id, "status" => "new"} = data["episode"]
    # The seeded episode counts itself; HK.other and the 100-day one don't (the latter is only
    # first_opened_at and the median).
    assert data["counts"] == %{"d7" => 2, "d30" => 3, "d90" => 4}
    assert data["median_duration_s"] == 210
    assert data["first_opened_at"]
    assert data["retention_days"] == nil

    assert [two_days, ten_days] = data["items"]

    assert %{
             "status" => "cleared",
             "condition" => "red_low",
             "direction" => "low",
             "duration_s" => 60,
             "ended" => "back_in_limits",
             "first_value" => 21.5,
             "point" => %{"id" => @point}
           } = two_days

    assert Map.has_key?(two_days["point"], "unit")
    assert %{"ended" => "source_stopped", "duration_s" => 120} = ten_days

    next = data["next_before"]
    assert is_binary(next)

    page2 = get_json(c, "/alarm-episodes/#{id}/history?limit=2&before=#{next}")["data"]
    assert [%{"duration_s" => 300}] = page2["items"]
    assert page2["next_before"] == nil
  end

  test "the spacecraft list covers every point, newest first; point_id narrows it", c do
    data = get_json(c, "/spacecraft/#{@sc}/alarm-episodes")["data"]

    assert [%{"status" => "new", "ended" => nil, "duration_s" => nil} | rest] = data["items"]
    assert Enum.map(rest, & &1["point"]["id"]) == ["HK.other", @point, @point, @point]
    assert data["counts"] == %{"d7" => 3, "d30" => 4, "d90" => 5}

    narrowed = get_json(c, "/spacecraft/#{@sc}/alarm-episodes?point_id=HK.other")["data"]
    assert [%{"point" => %{"id" => "HK.other"}}] = narrowed["items"]
    assert narrowed["counts"]["d90"] == 1
  end

  test "bad params are 422; an unknown episode is 404", c do
    body = get_json(c, "/alarm-episodes/#{active_id(c)}/history?scope=x&limit=0&before=zz", 422)

    assert %{"code" => "invalid_params", "details" => details} = body["error"]
    assert Map.keys(details) |> Enum.sort() == ["before", "limit", "scope"]

    assert %{"error" => %{"code" => "episode_not_found"}} =
             get_json(c, "/alarm-episodes/alarm_episode_nope/history", 404)
  end
end
