defmodule CadenceWeb.OpsDashboardShowLive.OperationalObservableMissionScopeLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Phoenix.LiveViewTest.ClientProxy

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Commanding.{CommandQueueEntry, CommandRequest}
  alias Cadence.Dashboards.{Document, RenderItem}

  alias Cadence.Persistence.Schemas.{
    CommandQueueEntryRow,
    CommandRequestRow
  }

  alias Cadence.Repo
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

  defp persist_command_queue_entry!(
         org,
         mission,
         command_queue_entry_id,
         source_endpoint_ref,
         lifecycle_state \\ :pending
       ) do
    requested_at = DateTime.from_unix!(1_700_000_000, :second)
    command_request_id = command_queue_entry_id <> "-request"

    command_request =
      CommandRequest.new(%{
        command_request_id: command_request_id,
        mission_id: mission.mission_id,
        source_endpoint_ref: source_endpoint_ref,
        command_snapshot_id: command_queue_entry_id <> "-snapshot",
        command_id: command_queue_entry_id <> "-command",
        command_name: "NOOP",
        command_display_name: "NOOP",
        lifecycle_state: :queued,
        priority: 3,
        requested_by: %{"user_id" => "dashboard-test"},
        requested_at: requested_at,
        metadata: %{}
      })

    command_queue_entry =
      CommandQueueEntry.new(%{
        command_queue_entry_id: command_queue_entry_id,
        mission_id: mission.mission_id,
        command_request_id: command_request_id,
        source_endpoint_ref: source_endpoint_ref,
        queue_lane_key: source_endpoint_ref,
        priority: 3,
        queue_sequence: System.unique_integer([:positive, :monotonic]),
        lifecycle_state: lifecycle_state,
        enqueued_by: %{"user_id" => "dashboard-test"},
        enqueued_at: requested_at,
        metadata: %{}
      })

    assert %CommandRequestRow{} =
             Repo.insert!(
               CommandRequestRow.changeset(%CommandRequest{
                 command_request
                 | organization_id: org.organization_id
               })
             )

    assert %CommandQueueEntryRow{} =
             Repo.insert!(
               CommandQueueEntryRow.changeset(%CommandQueueEntry{
                 command_queue_entry
                 | organization_id: org.organization_id
               })
             )

    command_queue_entry
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

  describe "mission operational observable scope rendering" do
    test "renders aggregate operational observable rows" do
      enable_dashboard_engine_inline_resolves!()

      {conn, org, mission} = signed_in_org_and_mission()

      persist_command_queue_entry!(
        org,
        mission,
        "dashboard-queue-alpha",
        "dashboard-source-endpoint-alpha"
      )

      persist_command_queue_entry!(
        org,
        mission,
        "dashboard-queue-beta",
        "dashboard-source-endpoint-beta"
      )

      persist_command_queue_entry!(
        org,
        mission,
        "dashboard-queue-released",
        "dashboard-source-endpoint-alpha",
        :released
      )

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Mission Command Queue",
          widgets: [
            %{
              type: :status_matrix,
              title: "Command Queue",
              binding: %{
                source: :operational_observables,
                observables: ["commanding.queue_depth"]
              }
            }
          ]
        )

      document = fetch_dashboard_document!(org, mission, dashboard)
      matrix_widget = render_item_by_title(document, "Command Queue").widget

      {:ok, view, _html} =
        live(
          conn,
          show_path(mission, dashboard) <>
            "?scope_kind=mission&scope_id=#{mission.mission_id}"
        )

      render_dashboard_async(view)

      assert has_element?(
               view,
               ~s(#ops-dashboard-show-page[data-dashboard-scope-kind="mission"][data-dashboard-scope-id="#{mission.mission_id}"])
             )

      mission_row_selector =
        ~s(#widget-#{matrix_widget.widget_id} [data-status-matrix-row="commanding.queue_depth:#{mission.mission_id}"])

      assert has_element?(
               view,
               mission_row_selector <>
                 ~s([data-status-matrix-source="operational_observables"][data-status-matrix-status-policy="metric_value"][data-status-matrix-resource-id="#{mission.mission_id}"][data-status-matrix-scope-kind="mission"])
             )

      assert has_element?(
               view,
               mission_row_selector <>
                 ~s([data-status-matrix-frame-observable-id="commanding.queue_depth"][data-status-matrix-product-family="commanding"][data-status-matrix-supported-capability="command_queue_depth"][data-status-matrix-data-source-id="managed_operational_observables"][data-status-matrix-source-binding-id="default_flight_operational_observables"])
             )

      assert has_element?(
               view,
               mission_row_selector <> ~s( [data-status-matrix-field="observable"]),
               "Pending commands"
             )

      assert has_element?(
               view,
               mission_row_selector <> ~s( [data-status-matrix-field="value"]),
               "2"
             )

      assert has_element?(
               view,
               mission_row_selector <>
                 ~s( [data-status-matrix-row-evidence="commanding.queue_depth:#{mission.mission_id}"][data-status-matrix-row-evidence-observable="commanding.queue_depth"][phx-value-logical-source="operational_observables"][phx-value-data-source-id="managed_operational_observables"][phx-value-source-binding-id="default_flight_operational_observables"])
             )

      refute has_element?(
               view,
               ~s(#widget-#{matrix_widget.widget_id} [data-status-matrix-row-link="commanding.queue_depth:#{mission.mission_id}"])
             )

      stop_dashboard_view(view)
    end
  end
end
