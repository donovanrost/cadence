defmodule CadenceWeb.OpsDashboardShowLive.OperationalObservableDefaultMultiEntityScopeLiveTest do
  use CadenceWeb.ConnCase, async: false

  @moduletag :config

  import Phoenix.LiveViewTest

  alias Phoenix.LiveViewTest.ClientProxy

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Comms.Transport
  alias Cadence.Dashboards.{Document, RenderItem}
  alias Cadence.Persistence.JsonDocument

  alias Cadence.Persistence.Schemas.OpsDashboardRow

  alias Cadence.Repo
  alias Cadence.SourceEndpoints.SourceEndpoint
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

  defp show_path(mission, dashboard) do
    ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}"
  end

  defp fetch_dashboard_document!(org, mission, dashboard) do
    assert {:ok, document} =
             Cadence.Dashboards.fetch_document(
               org.organization_id,
               mission.mission_id,
               dashboard.dashboard_id
             )

    document
  end

  defp replace_dashboard_row_document!(org, mission, %Document{} = document) do
    row =
      Repo.get_by!(OpsDashboardRow,
        organization_id: org.organization_id,
        mission_id: mission.mission_id,
        dashboard_id: document.dashboard_id
      )

    row
    |> Ecto.Changeset.change(%{document: JsonDocument.encode(Document.to_map(document))})
    |> Repo.update!()

    document
  end

  defp render_item_by_title(%Document{} = document, title) do
    document
    |> RenderItem.from_document()
    |> Enum.find(&(&1.widget.title == title))
  end

  defp render_dashboard_async(view) do
    track_dashboard_view(view)
    render_async(view, 5_000)
  end

  defp track_dashboard_view(%{pid: pid} = view) when is_pid(pid) do
    tracked_views = Process.get(:ops_dashboard_live_test_views, MapSet.new())

    unless MapSet.member?(tracked_views, pid) do
      Process.put(:ops_dashboard_live_test_views, MapSet.put(tracked_views, pid))

      on_exit({:ops_dashboard_live_view, pid}, fn ->
        stop_dashboard_view(view)
      end)
    end
  end

  defp stop_dashboard_view(view) do
    if Process.alive?(view.pid) do
      drain_dashboard_view(view)

      ref = Process.monitor(view.pid)
      {_proxy_ref, _topic, proxy_pid} = view.proxy
      ClientProxy.stop(proxy_pid, {:shutdown, :dashboard_test_cleanup})

      assert_receive {:DOWN, ^ref, :process, _pid, _reason}, 1_000
    end

    :ok
  end

  defp drain_dashboard_view(view) do
    render_async(view, 5_000)
    :ok
  catch
    :exit, _reason -> :ok
  end

  defp enable_dashboard_engine_inline_resolves! do
    previous_inline? = Application.get_env(:cadence_web, :dashboard_engine_resolve_inline?)
    Application.put_env(:cadence_web, :dashboard_engine_resolve_inline?, true)

    on_exit(fn ->
      case previous_inline? do
        nil ->
          Application.delete_env(:cadence_web, :dashboard_engine_resolve_inline?)

        value ->
          Application.put_env(:cadence_web, :dashboard_engine_resolve_inline?, value)
      end
    end)
  end

  describe "default multi-entity operational observable scope rendering" do
    test "document multi-entity scope filters operational observable rows" do
      enable_dashboard_engine_inline_resolves!()

      {conn, org, mission} = signed_in_org_and_mission()

      alpha_endpoint =
        SourceEndpoint.new(%{
          source_endpoint_id: "dashboard-source-endpoint-alpha",
          mission_id: mission.mission_id,
          display_name: "Goldstone DSS-14",
          metadata: %{"ground_station_id" => "dss-14"}
        })

      beta_endpoint =
        SourceEndpoint.new(%{
          source_endpoint_id: "dashboard-source-endpoint-beta",
          mission_id: mission.mission_id,
          display_name: "Madrid DSS-63",
          metadata: %{"ground_station_id" => "dss-63"}
        })

      gamma_endpoint =
        SourceEndpoint.new(%{
          source_endpoint_id: "dashboard-source-endpoint-gamma",
          mission_id: mission.mission_id,
          display_name: "Canberra DSS-43",
          metadata: %{"ground_station_id" => "dss-43"}
        })

      assert {:ok, _source_endpoint} =
               Cadence.persist_source_endpoint(org.organization_id, alpha_endpoint)

      assert {:ok, _source_endpoint} =
               Cadence.persist_source_endpoint(org.organization_id, beta_endpoint)

      assert {:ok, _source_endpoint} =
               Cadence.persist_source_endpoint(org.organization_id, gamma_endpoint)

      alpha_transport =
        Transport.new(%{
          transport_id: "dashboard-transport-alpha",
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
          metadata: %{
            "source_endpoint_id" => alpha_endpoint.source_endpoint_id,
            "ground_station_id" => "dss-14"
          }
        })

      beta_transport =
        Transport.new(%{
          transport_id: "dashboard-transport-beta",
          mission_id: mission.mission_id,
          display_name: "Beta TCP",
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
          metadata: %{
            "source_endpoint_id" => beta_endpoint.source_endpoint_id,
            "ground_station_id" => "dss-63"
          }
        })

      gamma_transport =
        Transport.new(%{
          transport_id: "dashboard-transport-gamma",
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
          metadata: %{
            "source_endpoint_id" => gamma_endpoint.source_endpoint_id,
            "ground_station_id" => "dss-43"
          }
        })

      assert {:ok, _transport} = Cadence.persist_transport(org.organization_id, alpha_transport)
      assert {:ok, _transport} = Cadence.persist_transport(org.organization_id, beta_transport)
      assert {:ok, _transport} = Cadence.persist_transport(org.organization_id, gamma_transport)

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Multi Source Endpoint Connection State",
          widgets: [
            %{
              type: :status_matrix,
              title: "Connection State",
              binding: %{
                source: :operational_observables,
                observables: ["comms.transport.connection_state"]
              }
            }
          ]
        )

      document =
        org
        |> fetch_dashboard_document!(mission, dashboard)
        |> then(fn document ->
          %Document{} = document

          %Document{
            document
            | defaults: %{
                "scope" => %{
                  "primary" => %{
                    "kind" => "source_endpoint",
                    "mode" => "many",
                    "ids" => [
                      alpha_endpoint.source_endpoint_id,
                      beta_endpoint.source_endpoint_id
                    ]
                  }
                }
              }
          }
        end)
        |> then(&replace_dashboard_row_document!(org, mission, &1))

      matrix_widget = render_item_by_title(document, "Connection State").widget

      {:ok, view, _html} = live(conn, show_path(mission, dashboard))
      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-dashboard-scope-kind="source_endpoint"][data-dashboard-scope-id="#{alpha_endpoint.source_endpoint_id}"])
             )

      alpha_row_selector =
        ~s(#widget-#{matrix_widget.widget_id} [data-status-matrix-row="comms.transport.connection_state:dashboard-transport-alpha"])

      beta_row_selector =
        ~s(#widget-#{matrix_widget.widget_id} [data-status-matrix-row="comms.transport.connection_state:dashboard-transport-beta"])

      gamma_row_selector =
        ~s(#widget-#{matrix_widget.widget_id} [data-status-matrix-row="comms.transport.connection_state:dashboard-transport-gamma"])

      assert has_element?(
               view,
               alpha_row_selector <>
                 ~s([data-status-matrix-source="operational_observables"][data-status-matrix-status-policy="connection_state"][data-status-matrix-resource-id="dashboard-transport-alpha"][data-status-matrix-scope-kind="transport"][data-status-matrix-source-endpoint-id="#{alpha_endpoint.source_endpoint_id}"][data-status-matrix-ground-station-id="dss-14"])
             )

      assert has_element?(
               view,
               beta_row_selector <>
                 ~s([data-status-matrix-source="operational_observables"][data-status-matrix-status-policy="connection_state"][data-status-matrix-resource-id="dashboard-transport-beta"][data-status-matrix-scope-kind="transport"][data-status-matrix-source-endpoint-id="#{beta_endpoint.source_endpoint_id}"][data-status-matrix-ground-station-id="dss-63"])
             )

      assert has_element?(
               view,
               alpha_row_selector <>
                 ~s([data-status-matrix-data-source-id="managed_operational_observables"][data-status-matrix-source-binding-id="default_flight_operational_observables"][data-status-matrix-supported-capability="connection_state"])
             )

      refute has_element?(view, gamma_row_selector)

      stop_dashboard_view(view)
    end
  end
end
