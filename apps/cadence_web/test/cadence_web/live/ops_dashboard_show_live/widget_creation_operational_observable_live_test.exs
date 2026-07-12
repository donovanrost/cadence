defmodule CadenceWeb.OpsDashboardShowLive.WidgetCreationOperationalObservableLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Cadence.Dashboards.{Document, RenderItem}
  alias CadenceWeb.TestFixtures
  alias Phoenix.LiveViewTest.ClientProxy

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  describe "operational observable widget creation flows" do
    test "adds an operational observable status matrix through the slide-over panel" do
      enable_dashboard_engine_inline_resolves!()

      {conn, user, org, mission} = signed_in_user_org_and_mission()
      %Document{} = dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Ops")

      {:ok, view, _html} = live(conn, show_path(mission, dashboard))
      render_dashboard_async(view)

      view |> element("#add-widget-button") |> render_click()

      view
      |> form("#widget-form",
        widget: %{
          type: "status_matrix",
          title: "Contact Phase",
          mode: "context",
          precision: "0"
        }
      )
      |> render_change()

      view
      |> form("#widget-form",
        widget: %{
          type: "status_matrix",
          title: "Contact Phase",
          binding_source: "operational_observables",
          precision: "0"
        }
      )
      |> render_change()

      assert has_element?(
               view,
               ~s([data-operational-observable="contacts.phase"])
             )

      assert has_element?(
               view,
               ~s([data-operational-observable="comms.transport.connection_state"])
             )

      assert has_element?(
               view,
               ~s([data-operational-observable="ground.station.connection_state"])
             )

      assert has_element?(
               view,
               ~s([data-operational-observable="comms.transport.downlink_bitrate"])
             )

      view |> element(~s(button[phx-value-point-id="contacts.phase"])) |> render_click()

      assert has_element?(
               view,
               ~s([data-selected-operational-observable="contacts.phase"])
             )

      view
      |> form("#widget-form",
        widget: %{
          type: "status_matrix",
          title: "Contact Phase",
          binding_source: "operational_observables",
          precision: "0"
        }
      )
      |> render_submit()

      render_dashboard_async(view)
      refute has_element?(view, "#dashboard-panel")
      stop_dashboard_view(view)

      document = fetch_dashboard_document!(org, mission, dashboard)

      assert [%{placement_id: placement_id, widget_def: widget_def}] = document.placements
      assert widget_def.widget_type_id == "cadence.status_matrix"
      assert widget_def.binding.source == :operational_observables
      assert widget_def.binding.observables == ["contacts.phase"]
      assert widget_def.binding.overlays == []

      version = fetch_dashboard_version!(org, mission, dashboard, 2)
      assert version.change_summary == "Added widget"
      assert version.created_by == user.user_id

      assert [
               %{
                 placement_id: ^placement_id,
                 widget: %{binding: %{source: :operational_observables, point_ids: point_ids}}
               }
             ] = RenderItem.from_document(document)

      assert point_ids == ["contacts.phase"]
    end
  end

  defp signed_in_user_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, slug: "ops", display_name: "Ops Mission")
    {TestFixtures.member_conn(user), user, org, mission}
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

  defp fetch_dashboard_version!(org, mission, dashboard, version_number) do
    assert {:ok, dashboard_version} =
             Cadence.Dashboards.fetch_version(
               org.organization_id,
               mission.mission_id,
               dashboard.dashboard_id,
               version_number
             )

    dashboard_version
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
