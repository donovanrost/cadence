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
             "query_params" => %{}
           }
  end

  test "packet feature captures only its declared scoped paging parameters" do
    {conn, mission, spacecraft} = setup_session()

    params = %{
      "page" => "3",
      "endpoint_page" => "2",
      "resource_page" => "4",
      "q" => "HEALTH",
      "endpoint_q" => "Downlink",
      "packet" => "packet-id"
    }

    path =
      ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/applications/telemetry_decom/packet_bindings"

    {:ok, view, _} =
      live(conn, path <> "?" <> URI.encode_query(Map.put(params, "untrusted", "ignored")))

    assert has_element?(
             view,
             "#spacecraft-application-host[data-renderer='federated'][data-surface-id='packet_bindings']"
           )

    vue = LiveVue.Test.get_vue(view, id: "application-surface-component")
    assert vue.component == "FederatedFullPageSurface"
    assert vue.props["query_params"] == params
    assert vue.props["mission_id"] == mission.mission_id
    assert vue.props["spacecraft_id"] == spacecraft.spacecraft_id
  end

  test "derived definitions retain the authenticated mission route and declared review and paging parameters" do
    {conn, mission, _spacecraft} = setup_session()

    params = %{
      "page" => "2",
      "history_page" => "3",
      "values_page" => "2",
      "sources_page" => "2",
      "spacecraft_page" => "3",
      "q" => "Power",
      "values_q" => "bus",
      "definition" => "definition-id",
      "version" => "7",
      "spacecraft" => "mission",
      "spacecraft_q" => "Explorer"
    }

    path = ~p"/missions/#{mission.mission_id}/applications/derived_telemetry/manage"

    {:ok, view, _} =
      live(conn, path <> "?" <> URI.encode_query(Map.put(params, "untrusted", "ignored")))

    assert has_element?(
             view,
             "#mission-application-host[data-application-key='derived_telemetry'][data-surface-id='manage'][data-renderer='federated']"
           )

    vue = LiveVue.Test.get_vue(view, id: "application-surface-component")
    assert vue.component == "FederatedFullPageSurface"
    assert vue.props["query_params"] == params
    assert vue.props["host_scope"] == "mission"
    assert vue.props["mission_id"] == mission.mission_id
    assert vue.props["spacecraft_id"] == nil
  end

  test "limits keeps authenticated mission URLs and exact-version bookmark parameters" do
    {conn, mission, _} = setup_session()

    params = %{
      "limit_definition_id" => "limits-id",
      "limit_definition_version" => "1",
      "point_id" => "HK.voltage",
      "page" => "2",
      "activation_page" => "2",
      "spacecraft" => "mission"
    }

    {:ok, view, _} =
      live(
        conn,
        "/missions/#{mission.mission_id}/applications/limits/activity?" <>
          URI.encode_query(Map.put(params, "untrusted", "ignored"))
      )

    assert has_element?(
             view,
             "#mission-application-host[data-application-key='limits'][data-surface-id='activity'][data-renderer='federated']"
           )

    vue = LiveVue.Test.get_vue(view, id: "application-surface-component")
    assert vue.props["query_params"] == params
    assert vue.props["host_scope"] == "mission"
    assert vue.props["mission_id"] == mission.mission_id
  end

  test "generic platform routes mount without installation ids" do
    {conn, mission, _spacecraft} = setup_session()

    {:ok, view, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/applications/comms/overview")

    assert has_element?(view, "#mission-application-host[data-application-key='comms']")
    refute has_element?(view, "#mission-application-host[data-application-installation-id]")

    assert LiveVue.Test.get_vue(view, id: "application-surface-component").props["query_params"] ==
             %{}

    assert LiveVue.Test.get_vue(view, id: "application-surface-component").component ==
             "FederatedFullPageSurface"
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

    {:ok, _} =
      ApplicationInstallations.install(
        scope,
        HostContext.mission(mission.mission_id),
        "derived_telemetry"
      )

    {:ok, _} =
      ApplicationInstallations.install(scope, HostContext.mission(mission.mission_id), "limits")

    {TestFixtures.member_conn(user), mission, spacecraft}
  end
end
