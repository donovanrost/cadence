defmodule CadenceWeb.OpsAwarenessLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Commanding.{CommandRequest, CommandRequestRow}
  alias Cadence.Limits.Event
  alias Cadence.Limits.Store
  alias Cadence.Repo
  alias CadenceWeb.TestFixtures

  test "read-only alarm filters link each condition to evidence and its definition" do
    {conn, _org, mission} = signed_in_org_and_mission()

    assert {:ok, _rows} =
             Store.persist_latest_states(Repo, [
               limit_event(mission, "red", :red, true, "EPS.voltage"),
               limit_event(mission, "green", :green, false, "EPS.current")
             ])

    {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/ops/alarms")

    assert has_element?(view, "#ops-alarms-page")
    assert has_element?(view, "#alarm-filter-form")
    assert has_element?(view, ~s([data-alarm-condition="red"][data-alarm-severity="critical"]))
    refute has_element?(view, ~s([data-alarm-condition="green"]))
    assert has_element?(view, "#alarm-open-sample-red")
    assert has_element?(view, "#alarm-open-definition-red")
    refute has_element?(view, ~s(form[phx-submit]))

    view
    |> form("#alarm-filter-form", filters: %{state: "nominal"})
    |> render_change()

    assert has_element?(view, ~s([data-alarm-condition="green"][data-alarm-severity="nominal"]))
    refute has_element?(view, ~s([data-alarm-condition="red"]))
  end

  test "a followed command is URL-scoped and remains visible on another Ops page" do
    {conn, org, mission} = signed_in_org_and_mission()
    persist_command_request!(org, mission, "command-1")

    {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/ops/commands")

    assert has_element?(view, "#ops-commands-page")
    assert has_element?(view, ~s([data-command-request="command-1"]))
    refute has_element?(view, ~s(button[phx-click="release_command"]))

    view
    |> element("#follow-command-command-1")
    |> render_click()

    assert has_element?(view, ~s(#followed-command-banner[data-followed-command="command-1"]))

    assert has_element?(
             view,
             ~s(#ops-context-rail [data-ops-context-followed-command="command-1"])
           )

    assert has_element?(
             view,
             ~s(#ops-nav-rail a[href*="/ops/planning"][href*="focus_command_id=command-1"])
           )

    {:ok, planning_view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/planning?#{%{focus_command_id: "command-1"}}"
      )

    assert has_element?(
             planning_view,
             ~s(#ops-context-rail [data-ops-context-followed-command="command-1"])
           )

    assert has_element?(
             planning_view,
             ~s(#ops-nav-rail a[href*="/ops/commands"][href*="focus_command_id=command-1"])
           )
  end

  test "alarm and command routes require an authenticated organization member", %{conn: conn} do
    org = TestFixtures.persist_org!()
    mission = TestFixtures.persist_mission!(org)

    for path <- [
          ~p"/missions/#{mission.mission_id}/ops/alarms",
          ~p"/missions/#{mission.mission_id}/ops/commands"
        ] do
      assert {:error, {:redirect, %{to: "/sign-in"}}} = live(conn, path)
    end
  end

  defp signed_in_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, slug: "ops", display_name: "Ops Mission")
    {TestFixtures.member_conn(user), org, mission}
  end

  defp limit_event(mission, id, normalized_state, violation, point_id) do
    %Event{
      limit_event_id: id,
      mission_id: mission.mission_id,
      point_id: point_id,
      point_name: point_id,
      source_sample_type: :telemetry_sample,
      sample_id: "sample-#{id}",
      limit_definition_id: "definition-#{id}",
      limit_definition_version: 1,
      limit_set_name: "DEFAULT",
      evaluated_value: 42,
      limit_state: normalized_state,
      normalized_state: normalized_state,
      violation: violation,
      receipt_time: ~U[2026-08-01 12:00:00Z],
      provenance: %{}
    }
  end

  defp persist_command_request!(org, mission, command_request_id) do
    request = %CommandRequest{
      command_request_id: command_request_id,
      organization_id: org.organization_id,
      mission_id: mission.mission_id,
      source_endpoint_ref: "uplink-primary",
      command_snapshot_id: "snapshot-1",
      command_id: "NOOP",
      command_name: "NOOP",
      command_display_name: "No operation",
      lifecycle_state: :approved,
      requested_by: %{display_name: "Flight Director"},
      requested_at: ~U[2026-08-01 12:00:00Z]
    }

    request
    |> CommandRequestRow.changeset()
    |> Repo.insert!()
  end
end
