defmodule CadenceWeb.OpsDataSourcesCapabilityRemediationLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Applications.{HostContext, SurfaceQueryRequest}
  alias Cadence.Reads.ApplicationSurfaces.OpsConsole
  alias CadenceWeb.TestFixtures
  alias LiveVue.Test

  test "capability remediation mounts the authenticated data-source descriptor" do
    user = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!()
    TestFixtures.grant_membership!(user, organization, role: :organization_admin)
    mission = TestFixtures.persist_mission!(organization)

    {:ok, view, _html} =
      live(
        TestFixtures.member_conn(user),
        ~p"/missions/#{mission.mission_id}/ops/data-sources?#{%{data_source_id: "focus-source", source_empty_reason: "unsupported_source_capability", requested_sampling: "raw_series"}}"
      )

    assert_surface(
      view,
      "ops-data-sources-component",
      "data_sources",
      mission,
      %{"data_source_id" => "focus-source"}
    )
  end

  test "source query provider rejects unbounded capability parameters" do
    request = %SurfaceQueryRequest{
      application_key: "ops_console",
      application_version: 1,
      surface_id: "data_sources",
      surface_version: 1,
      query_id: "cadence.ops.data_sources",
      query_version: 1,
      params: %{"unsupported_capability" => "raw_series"}
    }

    assert {:error, :unsupported_application_surface_query} =
             OpsConsole.load(
               %Cadence.Auth.Scope{organization_id: "org-1"},
               HostContext.mission("mission-1"),
               request
             )
  end

  defp assert_surface(view, id, surface_id, mission, query_params) do
    assert has_element?(view, "##{id}.contents")
    vue = Test.get_vue(view, id: id)
    assert vue.component == "FederatedFullPageSurface"
    assert vue.id == id
    assert vue.class == "contents"
    assert vue.ssr == false
    assert vue.handlers == %{}

    assert vue.props == %{
             "application_key" => "ops_console",
             "host_scope" => "mission",
             "mission_id" => mission.mission_id,
             "query_params" => query_params,
             "surface_id" => surface_id
           }
  end
end
