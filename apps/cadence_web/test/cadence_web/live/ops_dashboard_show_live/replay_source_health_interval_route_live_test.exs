defmodule CadenceWeb.OpsDashboardShowLive.ReplaySourceHealthIntervalRouteLiveTest do
  use CadenceWeb.ConnCase, async: false

  @moduletag :config

  import Phoenix.LiveViewTest

  alias Cadence.Comms.{GroundStationStore, TransportStore}

  alias Phoenix.LiveViewTest.ClientProxy

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Comms.{GroundStation, Transport}
  alias Cadence.Control.Replay.Store.ReplayRunRow
  alias Cadence.Dashboards.Document
  alias Cadence.Dashboards.DocumentStore.DashboardRow, as: OpsDashboardRow
  alias Cadence.Dashboards.RenderItem
  alias Cadence.DataSources.DataBinding
  alias Cadence.DataSources.DataSource
  alias Cadence.Management.DataSources
  alias Cadence.OperationalEvents
  alias Cadence.OperationalEvents.Event
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Projections.DataSources.Health, as: SourceHealth
  alias Cadence.Replay.Run
  alias Cadence.Repo
  alias Cadence.SourceEndpoints.SourceEndpoint
  alias CadenceWeb.TestFixtures

  test "reopens replay source-health interval copied from rendered frame evidence" do
    observed_at = ~U[2026-07-11 12:02:00Z]
    replay_run_id = "replay_run_source_health_interval_route"

    enable_dashboard_engine_inline_resolves!()
    configure_dashboard_source_health!(DateTime.add(observed_at, 60, :second))

    {conn, org, mission} = signed_in_org_and_mission()
    _telemetry_replay_source = persist_dashboard_realm!(mission, :replay)
    replay_sources = persist_replay_operational_source!(mission)
    persist_replay_run!(mission, replay_run_id)
    transport = persist_connection_state_resources!(org, mission)

    assert {:ok, _connection_event} =
             Event.from_operational_observable_state_snapshot(%{
               snapshot_id: "connection-replay-source-health-interval-route",
               organization_id: org.organization_id,
               mission_id: mission.mission_id,
               observable_id: "comms.transport.connection_state",
               resource_id: transport.transport_id,
               scope_kind: :transport,
               transport_id: transport.transport_id,
               source_endpoint_id: "replay-source-health-endpoint",
               ground_station_id: "dss-14",
               adapter_key: :tcp_socket,
               connection_state: :degraded,
               state: :degraded,
               replay_run_id: replay_run_id,
               observed_at: observed_at
             })
             |> OperationalEvents.persist_event()

    {source_health_event, source_health_interval} =
      record_source_health!(org, mission, replay_sources, observed_at, replay_run_id)

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Replay Source Health Interval Route",
        widgets: [
          %{
            type: :status_matrix,
            title: "Replay Connection State",
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
      |> then(fn %Document{} = document ->
        %Document{
          document
          | defaults: %{
              "data" => %{
                "realm" => "replay",
                "source_mode" => "specific",
                "source_contexts" => %{
                  "operational_observables" => %{
                    "source_binding_id" => replay_sources.binding_id
                  }
                }
              }
            }
        }
      end)
      |> replace_dashboard_document!(org, mission)

    widget_id = render_item_by_title(document, "Replay Connection State").widget.widget_id

    {:ok, view, _html} =
      live(
        conn,
        show_path(mission, dashboard) <>
          "?time_mode=replay_run&replay_run_id=#{replay_run_id}" <>
          "&scope_kind=ground_station&scope_id=dss-14"
      )

    render_dashboard_async(view)

    row_selector =
      ~s(#widget-#{widget_id} [data-status-matrix-row="comms.transport.connection_state:#{transport.transport_id}"])

    view
    |> element(row_selector <> ~s( [data-status-matrix-row-evidence]))
    |> render_click()

    interval_selector =
      ~s([data-evidence-ref-kind="source health interval"]) <>
        ~s([data-evidence-ref-id="#{source_health_interval.interval_id}"]) <>
        ~s([data-evidence-ref-link-target="source_health_interval"])

    assert has_element?(view, "#dashboard-evidence-inspector " <> interval_selector)

    view
    |> element("#dashboard-evidence-inspector " <> interval_selector)
    |> render_click()

    interval_route_id = URI.encode_www_form(source_health_interval.interval_id)

    assert_interval_inspector(
      view,
      source_health_interval,
      source_health_event,
      replay_run_id
    )

    copied_path =
      view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert copied_path =~ "selected_target=source_health_interval"
    assert copied_path =~ "selected_id=#{interval_route_id}"
    assert copied_path =~ "replay_run_id=#{replay_run_id}"
    assert copied_path =~ "data_source_id=#{source_health_event.data_source_id}"
    assert copied_path =~ "source_binding_id=#{source_health_event.source_binding_id}"

    stop_dashboard_view(view)

    {:ok, reopened_view, _html} = live(conn, copied_path)

    assert_interval_inspector(
      reopened_view,
      source_health_interval,
      source_health_event,
      replay_run_id
    )

    assert has_element?(
             reopened_view,
             "#dashboard-data-link-inspector [data-data-link-field='Operational interval']",
             source_health_interval.interval_id
           )

    assert has_element?(
             reopened_view,
             "#dashboard-data-link-inspector [data-data-link-field='Source event']",
             source_health_interval.source_event_id
           )

    stop_dashboard_view(reopened_view)
  end

  defp assert_interval_inspector(view, interval, event, replay_run_id) do
    selector =
      ~s(#dashboard-data-link-inspector[data-data-link-target="source_health_interval"]) <>
        ~s([data-data-link-target-id="#{interval.interval_id}"]) <>
        ~s([data-data-link-status="resolved"]) <>
        ~s([data-data-link-selected-replay-run-id="#{replay_run_id}"]) <>
        ~s([data-data-link-selected-data-source-id="#{event.data_source_id}"]) <>
        ~s([data-data-link-selected-source-binding-id="#{event.source_binding_id}"])

    assert has_element?(view, selector)
  end

  defp element_attribute(html, selector, attribute) do
    html
    |> LazyHTML.from_fragment()
    |> LazyHTML.query(selector)
    |> LazyHTML.attribute(attribute)
    |> List.first()
  end

  defp signed_in_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, slug: "ops", display_name: "Ops Mission")
    {TestFixtures.member_conn(user), org, mission}
  end

  defp persist_replay_run!(mission, replay_run_id) do
    replay_run =
      Run.new(%{
        replay_run_id: replay_run_id,
        mission_id: mission.mission_id,
        binding_set_id: "#{replay_run_id}-binding-set",
        binding_set_version: 1,
        status: :completed,
        replayed_evidence_count: 1,
        replayed_packet_count: 0,
        replayed_sample_count: 0,
        started_at: ~U[2026-07-11 11:59:00Z],
        completed_at: ~U[2026-07-11 12:06:00Z]
      })

    Repo.insert!(ReplayRunRow.changeset(replay_run))
  end

  defp persist_dashboard_realm!(mission, realm) do
    unique = System.unique_integer([:positive])
    data_source_id = "test-#{realm}-questdb-#{unique}"

    assert {:ok, _source} =
             DataSources.persist_data_source(%DataSource{
               data_source_id: data_source_id,
               owner: :cadence,
               kind: :managed_tsdb,
               adapter: Cadence.Dashboards.Sources.Telemetry,
               organization_id: mission.organization_id,
               mission_id: mission.mission_id,
               isolation_level: :mission_isolated,
               capabilities: %{range_scan?: true, latest?: true}
             })

    binding_id = "test-#{realm}-binding-#{unique}"

    assert {:ok, _binding} =
             DataSources.persist_data_binding(%DataBinding{
               binding_id: binding_id,
               organization_id: mission.organization_id,
               mission_id: mission.mission_id,
               realm: realm,
               logical_source: :telemetry,
               data_source_id: data_source_id,
               dataset: to_string(realm),
               priority: 0
             })

    %{data_source_id: data_source_id, binding_id: binding_id}
  end

  defp persist_replay_operational_source!(mission) do
    assert {:ok, _source} =
             DataSources.persist_data_source(
               DataSources.default_operational_observables_data_source()
             )

    binding_id = "replay-operational-observables-#{System.unique_integer([:positive])}"

    %DataBinding{} =
      default_operational_binding =
      DataSources.default_flight_operational_observables_binding()

    assert {:ok, _binding} =
             DataSources.persist_data_binding(%DataBinding{
               default_operational_binding
               | binding_id: binding_id,
                 organization_id: mission.organization_id,
                 mission_id: mission.mission_id,
                 realm: :replay,
                 dataset: "operational_observables_replay",
                 metadata: %{bootstrap_default?: false}
             })

    %{
      binding_id: binding_id,
      data_source_id: DataSources.default_operational_observables_data_source().data_source_id
    }
  end

  defp persist_connection_state_resources!(org, mission) do
    ground_station =
      GroundStation.new(%{
        ground_station_id: "dss-14",
        mission_id: mission.mission_id,
        display_name: "Goldstone DSS-14",
        provider: "DSN",
        region: "California"
      })

    assert {:ok, _ground_station} =
             GroundStationStore.persist_ground_station(
               org.organization_id,
               ground_station
             )

    source_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "replay-source-health-endpoint",
        mission_id: mission.mission_id,
        display_name: "Replay Source Health Endpoint",
        metadata: %{"ground_station_id" => "dss-14"}
      })

    assert {:ok, source_endpoint} =
             Cadence.SourceEndpoints.persist_source_endpoint(org.organization_id, source_endpoint)

    transport =
      Transport.new(%{
        transport_id: "replay-source-health-transport",
        mission_id: mission.mission_id,
        display_name: "Replay Source Health Transport",
        transport_kind: :tcp_socket,
        direction_capability: :bidirectional,
        adapter_key: :tcp_socket,
        configuration: %{
          "mode" => "connect",
          "direction_capability" => "bidirectional",
          "host" => "ground.example",
          "port" => "5000",
          "framing_mode" => "raw",
          "tls_enabled" => "false"
        },
        metadata: %{
          "source_endpoint_id" => source_endpoint.source_endpoint_id,
          "ground_station_id" => "dss-14"
        }
      })

    assert {:ok, transport} =
             TransportStore.persist_transport(org.organization_id, transport)

    transport
  end

  defp record_source_health!(org, mission, source, observed_at, replay_run_id) do
    assert {:ok, event, _status} =
             SourceHealth.record_source_health(
               %{
                 source_health_event_id: "source-health-rendered-replay-interval-route",
                 organization_id: org.organization_id,
                 mission_id: mission.mission_id,
                 logical_source: :operational_observables,
                 data_source_id: source.data_source_id,
                 source_binding_id: source.binding_id,
                 realm: :replay,
                 replay_run_id: replay_run_id,
                 dataset: "operational_observables_replay",
                 source_health: :degraded,
                 reason: :source_probe_failed,
                 observed_at: observed_at
               },
               invalidate_runtime_cache?: false
             )

    [interval] =
      Cadence.OperationalEvents.source_health_intervals(org.organization_id, mission.mission_id,
        data_source_id: event.data_source_id,
        source_binding_id: event.source_binding_id,
        realm: event.realm,
        dataset: event.dataset,
        replay_run_id: replay_run_id,
        at: observed_at,
        order: :asc
      )

    {event, interval}
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

  defp replace_dashboard_document!(document, org, mission) do
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

  defp render_item_by_title(document, title) do
    document
    |> RenderItem.from_document()
    |> Enum.find(&(&1.widget.title == title))
  end

  defp show_path(mission, dashboard) do
    ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}"
  end

  defp render_dashboard_async(view) do
    track_dashboard_view(view)
    render_async(view, 5_000)
  end

  defp track_dashboard_view(view) do
    on_exit({:replay_source_health_interval_view, view.pid}, fn ->
      stop_dashboard_view(view)
    end)
  end

  defp stop_dashboard_view(view) do
    if Process.alive?(view.pid) do
      _ = render_async(view, 5_000)
      ref = Process.monitor(view.pid)
      {_proxy_ref, _topic, proxy_pid} = view.proxy
      ClientProxy.stop(proxy_pid, {:shutdown, :dashboard_test_cleanup})
      assert_receive {:DOWN, ^ref, :process, _pid, _reason}, 1_000
    end

    :ok
  catch
    :exit, _reason -> :ok
  end

  defp enable_dashboard_engine_inline_resolves! do
    previous = Application.get_env(:cadence_web, :dashboard_engine_resolve_inline?)
    Application.put_env(:cadence_web, :dashboard_engine_resolve_inline?, true)

    on_exit(fn ->
      case previous do
        nil -> Application.delete_env(:cadence_web, :dashboard_engine_resolve_inline?)
        value -> Application.put_env(:cadence_web, :dashboard_engine_resolve_inline?, value)
      end
    end)
  end

  defp configure_dashboard_source_health!(now) do
    previous = Application.get_env(:cadence_web, :dashboard_engine_source_execution, [])

    Application.put_env(
      :cadence_web,
      :dashboard_engine_source_execution,
      previous
      |> Keyword.put(:source_health_events?, true)
      |> Keyword.put(:record_source_health_events?, false)
      |> Keyword.put(:now, now)
      |> Keyword.put(:source_health_freshness, %{default_max_age_ms: 86_400_000})
    )

    on_exit(fn ->
      Application.put_env(:cadence_web, :dashboard_engine_source_execution, previous)
    end)
  end
end
