defmodule CadenceWeb.OpsDataSourcesCapabilityRemediationLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Applications.{HostContext, SurfaceQueryRequest}
  alias Cadence.Reads.ApplicationSurfaces.OpsConsole
  alias CadenceWeb.HostTransportTestSupport
  alias CadenceWeb.TestFixtures

  test "capability remediation forwards only the source subject" do
    {conn, mission} = signed_in()

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/data-sources?data_source_id=focus-source&source_empty_reason=unsupported&requested_sampling=raw"
      )

    assert_surface(view, "ops-data-sources-component", "data_sources", mission, %{
      "data_source_id" => "focus-source"
    })
  end

  test "the source provider rejects unbounded capability parameters" do
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

  defp signed_in do
    user = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!()
    TestFixtures.grant_membership!(user, organization, role: :organization_admin)
    mission = TestFixtures.persist_mission!(organization)
    {TestFixtures.member_conn(user), mission}
  end

  defp assert_surface(view, _id, surface_id, mission, query_params) do
    contribution =
      case surface_id do
        "data_sources" -> "data-operations.sources"
        "data_source_registration" -> "data-operations.source-registration"
        "data_source_settings" -> "data-operations.source-settings"
      end

    snapshot =
      HostTransportTestSupport.assert_context(view, %{
        "kind" => "ops_module",
        "contribution" => contribution,
        "host_scope" => "mission",
        "mission_id" => mission.mission_id,
        "query_params" => query_params
      })

    assert snapshot["ops_page"]["id"] == contribution
  end
end
