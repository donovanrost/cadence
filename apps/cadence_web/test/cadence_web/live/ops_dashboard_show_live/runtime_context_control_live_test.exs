defmodule CadenceWeb.OpsDashboardShowLive.RuntimeContextControlLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import CadenceWeb.OpsDashboardShowLive.ViewTestSupport

  alias Cadence.Comms.TransportStore

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Comms.Transport
  alias CadenceWeb.TestFixtures

  defp signed_in_user_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, slug: "ops", display_name: "Ops Mission")
    {TestFixtures.member_conn(user), user, org, mission}
  end

  defp signed_in_org_and_mission do
    {conn, _user, org, mission} = signed_in_user_org_and_mission()
    {conn, org, mission}
  end

  defp value_tile(point_id, mode, spacecraft_id) do
    %{
      type: :value_tile,
      title: "Counter",
      binding: %{mode: mode, spacecraft_id: spacecraft_id, point_id: point_id}
    }
  end

  defp show_path(mission, dashboard) do
    ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}"
  end

  describe "dashboard runtime context controls" do
    test "context selector can apply and clear a multi-transport runtime scope" do
      {conn, org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Alpha")

      alpha_transport =
        Transport.new(%{
          transport_id: "dashboard-context-alpha-transport",
          mission_id: mission.mission_id,
          display_name: "Alpha TCP",
          transport_kind: :tcp_socket,
          direction_capability: :bidirectional,
          adapter_key: :tcp_socket,
          configuration: %{
            "mode" => "connect",
            "direction_capability" => "bidirectional",
            "host" => "alpha.ground.example",
            "port" => "5000",
            "framing_mode" => "raw",
            "tls_enabled" => "false"
          },
          metadata: %{"ground_station_id" => "dss-14"}
        })

      beta_transport =
        Transport.new(%{
          transport_id: "dashboard-context-beta-transport",
          mission_id: mission.mission_id,
          display_name: "Alpha Backup TCP",
          transport_kind: :tcp_socket,
          direction_capability: :bidirectional,
          adapter_key: :tcp_socket,
          configuration: %{
            "mode" => "connect",
            "direction_capability" => "bidirectional",
            "host" => "beta.ground.example",
            "port" => "5001",
            "framing_mode" => "raw",
            "tls_enabled" => "false"
          },
          metadata: %{"ground_station_id" => "dss-63"}
        })

      gamma_transport =
        Transport.new(%{
          transport_id: "dashboard-context-gamma-transport",
          mission_id: mission.mission_id,
          display_name: "Gamma TCP",
          transport_kind: :tcp_socket,
          direction_capability: :bidirectional,
          adapter_key: :tcp_socket,
          configuration: %{
            "mode" => "connect",
            "direction_capability" => "bidirectional",
            "host" => "gamma.ground.example",
            "port" => "5002",
            "framing_mode" => "raw",
            "tls_enabled" => "false"
          },
          metadata: %{"ground_station_id" => "dss-43"}
        })

      assert {:ok, _transport} =
               TransportStore.persist_transport(
                 org.organization_id,
                 alpha_transport
               )

      assert {:ok, _transport} =
               TransportStore.persist_transport(org.organization_id, beta_transport)

      assert {:ok, _transport} =
               TransportStore.persist_transport(
                 org.organization_id,
                 gamma_transport
               )

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Multi Transport Context Control",
          widgets: [value_tile("HK.counter", :context, spacecraft.spacecraft_id)]
        )

      {:ok, view, _html} = live(conn, show_path(mission, dashboard))
      render_dashboard_async(view)

      view |> element("#context-search-form") |> render_change(%{"q" => "Alpha"})

      expected_scope_ids =
        "#{beta_transport.transport_id},#{alpha_transport.transport_id}"

      assert has_element?(
               view,
               ~s(button[data-dashboard-context-batch-result="transport"][data-dashboard-context-batch-count="2"][data-dashboard-context-batch-ids="#{expected_scope_ids}"])
             )

      refute has_element?(
               view,
               ~s(button[data-dashboard-context-batch-result="transport"][data-dashboard-context-batch-ids*="#{gamma_transport.transport_id}"])
             )

      view
      |> element(~s(button[data-dashboard-context-batch-result="transport"]))
      |> render_click()

      patched_path = assert_patch(view)
      assert patched_path =~ "scope_kind=transport"
      assert patched_path =~ "scope_ids=#{URI.encode_www_form(expected_scope_ids)}"
      refute patched_path =~ "scope_id="

      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-dashboard-scope-kind="transport"][data-dashboard-scope-id="#{beta_transport.transport_id}"][data-dashboard-scope-ids="#{expected_scope_ids}"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-selected-context[data-dashboard-selected-context-kind="transport"][data-dashboard-selected-context-id="#{beta_transport.transport_id}"][data-dashboard-selected-context-ids="#{expected_scope_ids}"]),
               "2 transports"
             )

      view |> element(~s(button[aria-label="Clear context"])) |> render_click()

      cleared_path = assert_patch(view)
      refute cleared_path =~ "scope_kind="
      refute cleared_path =~ "scope_id="
      refute cleared_path =~ "scope_ids="

      render_dashboard_async(view)

      refute has_element?(view, "#dashboard-selected-context")
      stop_dashboard_view(view)
    end
  end
end
