defmodule CadenceWeb.OpsDataSourcesByoLifecycleLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Management.DataSources
  alias CadenceWeb.TestFixtures
  alias LiveVue.Test

  test "BYO registration remains a durable action outcome behind the descriptor" do
    user = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!()
    TestFixtures.grant_membership!(user, organization, role: :organization_admin)
    mission = TestFixtures.persist_mission!(organization)

    {:ok, view, _html} =
      live(
        TestFixtures.member_conn(user),
        ~p"/missions/#{mission.mission_id}/ops/data-sources/registration/new"
      )

    assert_surface(view, "ops-data-sources-component", "data_source_registration", mission, %{})

    render_hook(view, "register_source", %{
      "source" => %{
        "data_source_id" => "customer-telemetry-questdb",
        "logical_source" => "telemetry",
        "kind" => "byo_tsdb",
        "isolation_level" => "customer_owned",
        "credentials_ref" => "cred-customer-telemetry",
        "credential_provider" => "questdb",
        "endpoint_ref" => "endpoint://customer/ops",
        "material_env_profile" => "",
        "http_endpoint_env" => "",
        "storage" => "questdb"
      }
    })

    assert {:ok, source} = DataSources.fetch_data_source("customer-telemetry-questdb")
    assert source.organization_id == organization.organization_id
    assert source.mission_id == mission.mission_id
    assert source.owner == :customer
    assert source.kind == :byo_tsdb
    assert source.credentials_ref == "cred-customer-telemetry"
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
