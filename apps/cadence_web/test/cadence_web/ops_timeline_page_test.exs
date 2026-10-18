defmodule CadenceWeb.OpsTimelinePageTest do
  use CadenceWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias Cadence.OperationalEvents
  alias Cadence.OperationalEvents.Event
  alias CadenceWeb.TestFixtures

  setup do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org)
    %{user: user, org: org, mission: mission, conn: TestFixtures.member_conn(user)}
  end

  test "canonical deep links resolve selected evidence and path identity wins over foreign query parameters",
       c do
    persist(c, "selected", ~U[2026-09-01 00:00:00Z])
    foreign_org = TestFixtures.persist_org!()
    foreign = TestFixtures.persist_mission!(foreign_org)

    {:ok, view, _} =
      live(
        c.conn,
        path(c) <>
          "?event_id=mission_event:selected&mission_id=#{foreign.mission_id}&organization_id=#{foreign_org.organization_id}"
      )

    assert has_element?(view, "#application-shell")

    assert page(view)["context"] == %{
             "organization_id" => c.org.organization_id,
             "mission_id" => c.mission.mission_id
           }

    assert page(view)["data"]["selected"]["id"] == "mission_event:selected"
  end

  test "filter changes, canonical refresh, clear and leaving the route update the scoped snapshot",
       c do
    persist(c, "older", ~U[2026-09-01 00:00:00Z])
    persist(c, "newer", ~U[2026-09-03 00:00:00Z])
    {:ok, view, _} = live(c.conn, path(c))

    render_hook(view, "host:context", %{
      "path" => path(c) <> "?from=2026-09-03T00%3A00%3A00Z&event_id=mission_event:older"
    })

    assert Enum.map(page(view)["data"]["events"], & &1["id"]) == ["mission_event:newer"]
    assert page(view)["data"]["selected"]["id"] == "mission_event:older"
    persist(c, "latest", ~U[2026-09-04 00:00:00Z])
    render_hook(view, "host:context", %{"path" => path(c) <> "?from=2026-09-03T00%3A00%3A00Z"})
    assert length(page(view)["data"]["events"]) == 2
    assert page(view)["data"]["selected_status"] == "none"
    render_hook(view, "host:context", %{"path" => "/missions/#{c.mission.mission_id}/ops/alarms"})
    assert page(view) == nil
  end

  test "invalid time input stays visible as a filter error and denied sessions cannot refresh",
       c do
    {:ok, view, _} = live(c.conn, path(c) <> "?from=not-a-time")
    assert page(view)["data"]["errors"] == ["from"]
    assert page(view)["data"]["query"]["from"] == "not-a-time"
    assert page(view)["data"]["events"] == []
    :ok = Cadence.Auth.revoke_user_session(get_session(c.conn, :user_session_token))
    render_hook(view, "host:context", %{"path" => path(c)})
    assert_redirect(view, "/sign-in")
    assert {:error, {:redirect, %{to: "/sign-in"}}} = live(build_conn(), path(c))
  end

  defp page(view),
    do: LiveVue.Test.get_vue(view, id: "application-shell").props["snapshot"]["timeline_page"]

  defp path(c), do: "/missions/#{c.mission.mission_id}/ops/timeline"

  defp persist(c, id, at) do
    assert {:ok, _} =
             OperationalEvents.persist_event(
               Event.new(%{
                 event_id: id,
                 organization_id: c.org.organization_id,
                 mission_id: c.mission.mission_id,
                 occurred_at: at,
                 category: :data_source,
                 kind: :source_health_degraded,
                 severity: :warning,
                 subject: %{kind: :data_source, id: "flight-telemetry"},
                 current: %{status: "degraded"}
               })
             )
  end
end
