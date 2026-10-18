defmodule CadenceWeb.OpsTimelineLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Applications.{HostContext, SurfaceQueryRequest}
  alias Cadence.Auth.Scope
  alias Cadence.Reads.ApplicationSurfaces.OpsConsole
  alias CadenceWeb.TestFixtures

  test "authenticated mission members mount the core workspace timeline" do
    user = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!()
    TestFixtures.grant_membership!(user, organization)
    mission = TestFixtures.persist_mission!(organization)

    {:ok, view, _html} =
      live(
        TestFixtures.member_conn(user),
        ~p"/missions/#{mission.mission_id}/ops/timeline?event_id=event-1&source_dashboard_id=dashboard-1"
      )

    snapshot = LiveVue.Test.get_vue(view, id: "application-shell").props["snapshot"]
    assert snapshot["timeline_page"]["context"]["mission_id"] == mission.mission_id
    assert snapshot["timeline_page"]["data"]["selected_status"] == "unavailable"
    assert snapshot["timeline_page"]["data"]["query"]["event_id"] == "event-1"

    assert LiveVue.Test.get_vue(view, id: "application-shell").props["snapshot"]["context"][
             "ops_context"
           ]["modules"] !=
             []
  end

  test "timeline query provider rejects forged and unsupported context" do
    assert {:error, :unsupported_application_surface_query} =
             OpsConsole.load(
               %Scope{organization_id: "org-1"},
               HostContext.mission("mission-1"),
               request("timeline", %{"unknown" => "value"})
             )

    assert {:error, :unsupported_application_surface_query} =
             OpsConsole.load(
               %Scope{organization_id: "org-1"},
               HostContext.mission("mission-1"),
               request("timeline", %{"mission_id" => "mission-2"})
             )
  end

  defp request(surface_id, params) do
    %SurfaceQueryRequest{
      application_key: "ops_console",
      application_version: 1,
      surface_id: surface_id,
      surface_version: 1,
      query_id: "cadence.ops.#{surface_id}",
      query_version: 1,
      params: params
    }
  end
end
