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

    assert has_element?(inventory, "#ops-data-sources-page")

    assert has_element?(
             inventory,
             ~s(#data-source-mission-telemetry a[href="/missions/#{mission.mission_id}/ops/data-sources/mission-telemetry"])
           )

    refute has_element?(inventory, "#register-source-button")
    refute has_element?(inventory, "#source-settings-mission-telemetry")
    refute has_element?(inventory, "#probe-source-mission-telemetry")
    refute has_element?(inventory, "#disable-source-mission-telemetry")

    {:ok, detail, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/data-sources/mission-telemetry"
      )

    assert has_element?(
             detail,
             ~s(#ops-data-sources-page[data-source-focus-state="matched"][data-source-focus-data-source="mission-telemetry"])
           )

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

    assert has_element?(inventory, "#register-source-button")
    assert has_element?(inventory, "#source-settings-mission-telemetry")
    refute has_element?(inventory, "#probe-source-mission-telemetry")

    {:ok, settings, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/data-sources/mission-telemetry/settings"
      )

    assert has_element?(settings, "#probe-source-mission-telemetry")
    assert has_element?(settings, "#disable-source-mission-telemetry")

    {:ok, registration, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/data-sources/registration/new"
      )

    assert has_element?(registration, "#register-source-panel")
    assert has_element?(registration, "#register-source-form")
  end

  describe "writes only on the organization's own sources (cross-tenant fix)" do
    setup do
      {conn, mission} = signed_in(:organization_admin)
      other_org = TestFixtures.persist_org!()
      other_mission = TestFixtures.persist_mission!(other_org)

      other =
        persist_source!(
          "other-tenant-source",
          other_org.organization_id,
          other_mission.mission_id
        )

      shared = persist_source!("platform-shared-source", nil, nil)

      {:ok, settings, _html} =
        live(
          conn,
          ~p"/missions/#{mission.mission_id}/ops/data-sources/mission-telemetry/settings"
        )

      %{settings: settings, other: other, shared: shared, conn: conn, mission: mission}
    end

    test "another organization's source can't be disabled by id, and stays active", c do
      render_click(c.settings, "disable_source", %{"data-source-id" => c.other.data_source_id})

      assert {:ok, %DataSource{status: :active}} =
               DataSources.fetch_data_source(c.other.data_source_id)
    end

    test "a platform-shared source can't be disabled or probed", c do
      render_click(c.settings, "disable_source", %{"data-source-id" => c.shared.data_source_id})
      render_click(c.settings, "probe_source", %{"data-source-id" => c.shared.data_source_id})

      assert {:ok, %DataSource{status: :active}} =
               DataSources.fetch_data_source(c.shared.data_source_id)
    end

    test "registering an existing id never overwrites it", c do
      {:ok, registration, _html} =
        live(c.conn, ~p"/missions/#{c.mission.mission_id}/ops/data-sources/registration/new")

      registration
      |> form("#register-source-form",
        source: %{
          "data_source_id" => c.shared.data_source_id,
          "kind" => "managed_tsdb",
          "isolation_level" => "mission_isolated",
          "credentials_ref" => ""
        }
      )
      |> render_submit()

      assert {:ok, %DataSource{organization_id: nil}} =
               DataSources.fetch_data_source(c.shared.data_source_id)
    end

    test "the organization's own source can still be disabled", c do
      render_click(c.settings, "disable_source", %{"data-source-id" => "mission-telemetry"})

      assert {:ok, %DataSource{status: :disabled}} =
               DataSources.fetch_data_source("mission-telemetry")
    end
  end

  defp persist_source!(id, organization_id, mission_id) do
    {:ok, source} =
      DataSources.persist_data_source(%DataSource{
        data_source_id: id,
        owner: :cadence,
        kind: :managed_tsdb,
        adapter: Cadence.Dashboards.Sources.Telemetry,
        organization_id: organization_id,
        mission_id: mission_id,
        isolation_level: if(organization_id, do: :mission_isolated, else: :shared),
        capabilities: %{latest?: true, range_scan?: true, watermarks?: true},
        metadata: %{storage: :questdb}
      })

    source
  end
end
