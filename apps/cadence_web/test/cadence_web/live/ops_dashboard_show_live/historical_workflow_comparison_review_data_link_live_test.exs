defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowComparisonReviewDataLinkLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Phoenix.LiveViewTest.ClientProxy

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Dashboards.Document
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

  describe "comparison-review dashboard lifecycle data-link routes" do
    test "opens dashboard lifecycle events directly from data-link routes" do
      {conn, user, org, mission} = signed_in_user_org_and_mission()
      %Document{} = dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Power")

      assert {:ok, request_event} =
               Cadence.Dashboards.record_dashboard_comparison_review_request(
                 org.organization_id,
                 mission.mission_id,
                 dashboard.dashboard_id,
                 %{
                   "schema" => "dashboard_comparison_review_request.v1",
                   "request_kind" => "comparison_open_findings_review",
                   "open_count" => 1,
                   "open_placement_ids" => ["placement-counter"]
                 },
                 actor_id: user.user_id
               )

      path =
        show_path(mission, dashboard) <>
          "?panel=data_link&selected_target=dashboard_lifecycle_event&selected_id=#{request_event.dashboard_lifecycle_event_id}"

      {:ok, view, _html} = live(conn, path)
      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="dashboard_lifecycle_event"][data-data-link-target-id="#{request_event.dashboard_lifecycle_event_id}"][data-data-link-status="resolved"])
             )

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-dashboard-selection-state="query_only"][data-dashboard-selection-target="dashboard_lifecycle_event"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Dashboard lifecycle event"]),
               request_event.dashboard_lifecycle_event_id
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Event type"]),
               "comparison_review_requested"
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector [data-data-link-field="Comparison review kind"]),
               "comparison_open_findings_review"
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=dashboard_lifecycle_event"][data-clipboard-text*="selected_id=#{URI.encode_www_form(request_event.dashboard_lifecycle_event_id)}"])
             )
    end

    test "keeps missing dashboard lifecycle data-link routes inspectable" do
      {conn, _org, mission} = signed_in_org_and_mission()
      %Document{} = dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Power")
      missing_event_id = "missing-dashboard-lifecycle-event"

      path =
        show_path(mission, dashboard) <>
          "?panel=data_link&selected_target=dashboard_lifecycle_event&selected_id=#{missing_event_id}"

      {:ok, view, _html} = live(conn, path)
      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#dashboard-data-link-inspector[data-data-link-target="dashboard_lifecycle_event"][data-data-link-target-id="#{missing_event_id}"][data-data-link-status="missing"])
             )

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-dashboard-selection-state="missing_target"][data-dashboard-selection-target="dashboard_lifecycle_event"])
             )

      assert has_element?(
               view,
               ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=dashboard_lifecycle_event"][data-clipboard-text*="selected_id=#{missing_event_id}"])
             )
    end
  end
end
