defmodule CadenceWeb.OpsDashboardShowLive.LiveWidgetSelectionMissingContextLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Phoenix.LiveViewTest.ClientProxy

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Dashboards.{Document, RenderItem}
  alias CadenceWeb.TestFixtures

  defp signed_in_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, slug: "ops", display_name: "Ops Mission")
    {TestFixtures.member_conn(user), org, mission}
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

  defp chart_optional_attribute(html, widget_id, attribute) do
    case html
         |> LazyHTML.from_fragment()
         |> LazyHTML.query(~s([id^="tlm-chart-#{widget_id}-"]))
         |> LazyHTML.attribute(attribute) do
      [value] -> Jason.decode!(value)
      [] -> nil
    end
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

  describe "live widget missing selection contexts" do
    test "renders missing telemetry sample, stale link, and unsupported target URLs" do
      {conn, org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "SC Alpha")

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Power",
          widgets: [
            %{
              type: :time_series,
              title: "Counter Trend",
              binding: %{
                mode: :fixed,
                spacecraft_id: spacecraft.spacecraft_id,
                point_id: "HK.counter"
              },
              layout: %{x: 4, y: 0, w: 6, h: 3}
            }
          ]
        )

      document = fetch_dashboard_document!(org, mission, dashboard)
      trend_widget = render_item_by_title(document, "Counter Trend").widget

      stale_target_path =
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{selected_target: "telemetry_sample", selected_id: "missing-sample"}}"

      {:ok, stale_target_view, _html} = live(conn, stale_target_path)
      render_dashboard_async(stale_target_view)

      assert has_element?(
               stale_target_view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="telemetry_sample"][data-data-link-target-id="missing-sample"][data-data-link-status="missing"])
             )

      assert has_element?(
               stale_target_view,
               ~s(#ops-dashboard-show-page[data-dashboard-selection-state="missing_target"][data-dashboard-selection-target="telemetry_sample"])
             )

      assert has_element?(
               stale_target_view,
               ~s(#ops-dashboard-show-page[data-dashboard-evidence-state="none"])
             )

      assert has_element?(
               stale_target_view,
               ~s(#dashboard-data-link-copy-link[data-clipboard-text*="selected_target=telemetry_sample"][data-clipboard-text*="selected_id=missing-sample"])
             )

      stale_link_path =
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{panel: "data_link", selected_link: "stale-link-1"}}"

      {:ok, stale_link_view, _html} = live(conn, stale_link_path)
      render_dashboard_async(stale_link_view)

      assert has_element?(
               stale_link_view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="data_link"][data-data-link-target-id="stale-link-1"][data-data-link-status="missing"])
             )

      assert has_element?(
               stale_link_view,
               ~s(#ops-dashboard-show-page[data-dashboard-selection-state="missing_target"])
             )

      refute chart_optional_attribute(
               render(stale_link_view),
               trend_widget.widget_id,
               "data-selected-ref"
             )

      unsupported_target_path =
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}?#{%{selected_target: "command", selected_id: "cmd-1"}}"

      {:ok, unsupported_target_view, _html} = live(conn, unsupported_target_path)
      render_dashboard_async(unsupported_target_view)

      assert has_element?(
               unsupported_target_view,
               ~s(#ops-dashboard-show-page[data-dashboard-selection-state="none"])
             )

      refute has_element?(unsupported_target_view, "#dashboard-data-link-inspector")

      refute chart_optional_attribute(
               render(unsupported_target_view),
               trend_widget.widget_id,
               "data-selected-ref"
             )

      assert has_element?(unsupported_target_view, "#dashboard-pause-at-selection[disabled]")
      assert has_element?(unsupported_target_view, "#dashboard-clear-selection[disabled]")
    end
  end
end
