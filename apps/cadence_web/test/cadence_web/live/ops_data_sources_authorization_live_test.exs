defmodule CadenceWeb.OpsDataSourcesAuthorizationLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Management.DataSources

  alias Cadence.DataSources.DataSource
  alias CadenceWeb.TestFixtures

  defp signed_in(role) do
    user = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, organization, role: role)
    mission = TestFixtures.persist_mission!(organization)

    assert {:ok, _source} =
             DataSources.persist_data_source(%DataSource{
               data_source_id: "mission-telemetry",
               owner: :cadence,
               kind: :managed_tsdb,
               adapter: Cadence.Dashboards.Sources.Telemetry,
               organization_id: organization.organization_id,
               mission_id: mission.mission_id,
               isolation_level: :mission_isolated,
               capabilities: %{latest?: true, range_scan?: true, watermarks?: true},
               metadata: %{storage: :questdb}
             })

    {TestFixtures.member_conn(user), mission}
  end

  test "ordinary operators can inspect inventory and source detail without mutation controls" do
    {conn, mission} = signed_in(:member)

    {:ok, inventory, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/ops/data-sources")

    assert has_element?(inventory, "#ops-data-sources-component.contents")

    inventory_page = ops_data_sources_page(inventory)
    source = source_row(inventory_page, "mission-telemetry")

    assert inventory_page["mode"] == "reader"
    refute Map.has_key?(inventory_page, "admin")
    assert inventory_page["header"]["register_link"] == nil

    assert source["detail_link"]["href"] ==
             "/missions/#{mission.mission_id}/ops/data-sources/mission-telemetry"

    refute Map.has_key?(source, "settings_link")
    refute Map.has_key?(source, "actions")

    render_hook(inventory, "disable_source", %{"data-source-id" => "mission-telemetry"})
    assert {:ok, persisted_source} = DataSources.fetch_data_source("mission-telemetry")
    assert persisted_source.status == :active

    render_patch(
      inventory,
      ~p"/missions/#{mission.mission_id}/ops/data-sources?#{%{logical_source: "telemetry", realm: "rehearsal", source_empty_reason: "missing_source_binding"}}"
    )

    reader_remediation = ops_data_sources_page(inventory)["focus"]["remediation"]
    assert reader_remediation["kind"] == "missing_source_binding"
    refute Map.has_key?(reader_remediation, "action")

    {:ok, detail, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/data-sources/mission-telemetry"
      )

    detail_page = ops_data_sources_page(detail)
    assert detail_page["focus"]["state"] == "matched"
    assert detail_page["focus"]["data_source_id"] == "mission-telemetry"
    refute Map.has_key?(detail_page, "admin")
    refute Map.has_key?(source_row(detail_page, "mission-telemetry"), "actions")

    assert {:error, {:redirect, %{to: "/"}}} =
             live(
               conn,
               ~p"/missions/#{mission.mission_id}/ops/data-sources/mission-telemetry/settings"
             )

    assert {:error, {:redirect, %{to: "/"}}} =
             live(
               conn,
               ~p"/missions/#{mission.mission_id}/ops/data-sources/registration/new"
             )
  end

  test "organization administrators enter dedicated registration and settings routes" do
    {conn, mission} = signed_in(:organization_admin)

    {:ok, inventory, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/ops/data-sources")

    inventory_page = ops_data_sources_page(inventory)
    inventory_source = source_row(inventory_page, "mission-telemetry")

    assert inventory_page["header"]["register_link"]["id"] == "register-source-button"
    assert inventory_source["settings_link"]["id"] == "source-settings-mission-telemetry"
    refute Map.has_key?(inventory_source, "actions")

    {:ok, settings, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/data-sources/mission-telemetry/settings"
      )

    settings_page = ops_data_sources_page(settings)
    settings_source = source_row(settings_page, "mission-telemetry")

    assert settings_page["mode"] == "admin"
    assert Map.has_key?(settings_page, "admin")

    assert Enum.map(settings_source["actions"], & &1["id"]) == [
             "probe-source-mission-telemetry",
             "disable-source-mission-telemetry"
           ]

    {:ok, registration, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/data-sources/registration/new"
      )

    registration_page = ops_data_sources_page(registration)
    registration_dto = registration_page["admin"]["registration"]

    assert registration_dto["id"] == "register-source-panel"
    assert registration_dto["form"]["id"] == "register-source-form"
    assert registration_dto["form"]["values"]["kind"] == "byo_tsdb"

    invalid_values = %{
      "data_source_id" => "",
      "logical_source" => "telemetry",
      "kind" => "byo_tsdb",
      "isolation_level" => "customer_owned",
      "credentials_ref" => "cred-resync",
      "credential_provider" => "questdb",
      "endpoint_ref" => "endpoint://customer/resync",
      "material_env_profile" => "resync-profile",
      "http_endpoint_env" => "RESYNC_HTTP_ENDPOINT",
      "storage" => "questdb"
    }

    render_hook(registration, "register_source", %{"source" => invalid_values})

    resynced_form = ops_data_sources_page(registration)["admin"]["registration"]["form"]
    assert resynced_form["values"] == invalid_values
    assert resynced_form["error"] == "Source ID is required."
    assert registration_page == Jason.decode!(Jason.encode!(registration_page))
  end

  defp ops_data_sources_page(view_or_html) do
    view_or_html
    |> LiveVue.Test.get_vue(id: "ops-data-sources-component")
    |> then(& &1.props["page"])
  end

  defp source_row(page, data_source_id) do
    Enum.find(page["sources"]["rows"], &(&1["data_source_id"] == data_source_id))
  end
end
