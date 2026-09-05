defmodule CadenceWeb.ApplicationHostLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Applications.{ApplicationInstallations, HostContext}
  alias Cadence.Auth.Scope
  alias CadenceWeb.TestFixtures

  test "trusted surfaces mount as exact federated descriptors" do
    {conn, mission, spacecraft} = setup_session()

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/applications/telemetry_decom/manage"
      )

    assert has_element?(
             view,
             "#spacecraft-application-host[data-application-key='telemetry_decom'][data-application-version='1'][data-surface-id='manage'][data-surface-version='1'][data-renderer='federated']"
           )

    vue = LiveVue.Test.get_vue(view, id: "application-surface-component")

    assert vue.component == "FederatedFullPageSurface"
    assert vue.ssr == false
    assert vue.class == "contents"
    assert vue.handlers == %{}

    assert vue.props == %{
             "application_key" => "telemetry_decom",
             "application_version" => 1,
             "surface_id" => "manage",
             "surface_version" => 1,
             "host_scope" => "spacecraft",
             "organization_id" => nil,
             "user_id" => nil,
             "mission_id" => mission.mission_id,
             "spacecraft_id" => spacecraft.spacecraft_id,
             "query_params" => %{"page" => 1}
           }
  end

  defp setup_session do
    user = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!()
    membership = TestFixtures.grant_membership!(user, organization)
    mission = TestFixtures.persist_mission!(organization, slug: "host-test")
    spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "Host Test Craft")

    scope =
      Scope.new(%{
        user: user,
        organization_id: organization.organization_id,
        organization: organization,
        organization_membership: membership
      })

    {:ok, _installation} =
      ApplicationInstallations.install(
        scope,
        HostContext.spacecraft(mission.mission_id, spacecraft.spacecraft_id),
        "telemetry_decom"
      )

    {TestFixtures.member_conn(user), mission, spacecraft}
  end
end
