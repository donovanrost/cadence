defmodule CadenceWeb.OpsDashboardShowLive.RuntimeSourceCapabilityTimelineLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Phoenix.LiveViewTest.ClientProxy

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Dashboards.{DataSources, Document, RenderItem, RuntimeCache}
  alias Cadence.OperationalEvents
  alias Cadence.OperationalEvents.Event
  alias CadenceWeb.TestFixtures

  test "event timeline source-capability posture rows open canonical operational-event inspectors" do
    enable_dashboard_engine_inline_resolves!()

    {conn, org, mission} = signed_in_org_and_mission()

    assert {:ok, _events_source} =
             DataSources.persist_data_source(DataSources.default_events_data_source())

    assert {:ok, _events_binding} =
             DataSources.persist_data_binding(DataSources.default_flight_events_binding(),
               occurred_at: ~U[2026-06-17 11:59:00Z]
             )

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Source Capability Events",
        widgets: [
          %{
            type: :event_timeline,
            title: "Mission Events",
            binding: %{source: :events, observables: []}
          }
        ]
      )

    document = fetch_dashboard_document!(org, mission, dashboard)
    events_widget = render_item_by_title(document, "Mission Events").widget
    source_request_id = "source_req_#{events_widget.widget_id}_primary_events"

    source_capability_posture_id =
      "dashboard-live-source-capability:resolve-1:#{source_request_id}"

    assert {:ok, persisted_event} =
             Event.from_source_capability_posture(%{
               organization_id: org.organization_id,
               mission_id: mission.mission_id,
               source_capability_posture_id: source_capability_posture_id,
               dashboard_id: dashboard.dashboard_id,
               dashboard_version: 1,
               resolve_id: "dashboard-live-source-capability-resolve",
               source_request_id: source_request_id,
               logical_source: :events,
               data_source_id: DataSources.default_events_data_source().data_source_id,
               source_binding_id: DataSources.default_flight_events_binding().binding_id,
               realm: :flight,
               dataset: "mission_events",
               status: :fallback,
               requested_sampling: :event_history,
               supported_sampling: [:event_history],
               requested_time_axis: :generation_time,
               executed_time_axis: :occurred_at,
               supported_time_axes: [:occurred_at],
               fallbacks: [:occurred_at_axis],
               unsupported: [:generation_time_axis],
               source_execution_status: :resolved,
               source_execution_cache_status: :miss,
               source_execution_operator_action: :inspect_source_capability,
               source_execution_runtime_action: :use_occurred_at_axis,
               source_execution_warning_codes: [:unsupported_source_capability],
               observed_at: ~U[2026-06-17 12:01:00Z]
             })
             |> OperationalEvents.persist_event()

    assert [^persisted_event] =
             OperationalEvents.list_events(org.organization_id, mission.mission_id,
               category: :data_source,
               source_record_kind: :source_capability_posture,
               from_occurred_at: ~U[2026-06-17 12:00:00Z],
               to_occurred_at: ~U[2026-06-17 12:05:00Z],
               order: :asc
             )

    if Process.whereis(RuntimeCache), do: RuntimeCache.reset()

    {:ok, view, _html} =
      live(
        conn,
        show_path(mission, dashboard) <>
          "?time_mode=archive&time_axis=occurred_at&from=2026-06-17T12:00:00Z&to=2026-06-17T12:05:00Z"
      )

    render_dashboard_async(view)

    row_selector =
      ~s(#widget-#{events_widget.widget_id} [data-event-timeline-record-id="#{source_capability_posture_id}"])

    assert has_element?(
             view,
             row_selector <>
               ~s([data-event-timeline-category="Source capability"][data-event-timeline-kind="Source capability fallback"][data-event-timeline-target="Operational event"][data-event-timeline-target-id="#{persisted_event.event_id}"][data-event-timeline-logical-source="events"][data-event-timeline-realm="flight"][data-event-timeline-data-source-id="#{DataSources.default_events_data_source().data_source_id}"][data-event-timeline-source-binding-id="#{DataSources.default_flight_events_binding().binding_id}"][data-event-timeline-dataset="mission_events"])
           )

    assert has_element?(
             view,
             row_selector <>
               ~s( [data-event-timeline-row-link-target="operational event"][data-event-timeline-row-link-id="#{persisted_event.event_id}"][phx-value-target="operational_event"][phx-value-target-id="#{persisted_event.event_id}"][phx-value-realm="flight"][phx-value-source-binding-id="#{DataSources.default_flight_events_binding().binding_id}"][phx-value-data-source-id="#{DataSources.default_events_data_source().data_source_id}"])
           )

    view
    |> element(
      row_selector <>
        ~s( [data-event-timeline-row-link-target="operational event"][data-event-timeline-row-link-id="#{persisted_event.event_id}"])
    )
    |> render_click()

    operational_event_path = assert_patch(view)
    assert operational_event_path =~ "panel=data_link"
    assert operational_event_path =~ "selected_target=operational_event"

    assert operational_event_path =~
             "selected_id=#{URI.encode_www_form(persisted_event.event_id)}"

    assert operational_event_path =~
             "selected_placement=#{URI.encode_www_form(events_widget.widget_id)}"

    assert operational_event_path =~ "realm=flight"

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-status="resolved"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Operational event"]),
             persisted_event.event_id
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Source capability posture"]),
             source_capability_posture_id
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Capability status"]),
             "fallback"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Executed time axis"]),
             "occurred_at"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{URI.encode_www_form(persisted_event.event_id)}"][data-clipboard-text*="selected_placement=#{URI.encode_www_form(events_widget.widget_id)}"])
           )

    stop_dashboard_view(view)
  end

  defp signed_in_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, slug: "ops", display_name: "Ops Mission")
    {TestFixtures.member_conn(user), org, mission}
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
end
