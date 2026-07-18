defmodule CadenceWeb.OpsDashboardShowLive.DashboardLifecycleLiveTest do
  use CadenceWeb.ConnCase, async: false

  @moduletag :config

  import Phoenix.LiveViewTest

  alias Phoenix.LiveViewTest.ClientProxy

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.ApplicationDispatch.{BindingRule, BindingSet, CapabilityInstance}
  alias Cadence.Dashboards.Document
  alias Cadence.Telemetry.PacketDefinition
  alias CadenceWeb.TestFixtures

  defp signed_in_user_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, slug: "ops", display_name: "Ops Mission")
    {TestFixtures.member_conn(user), user, org, mission}
  end

  defp persist_binding_set!(org, mission) do
    packet_definition =
      PacketDefinition.new(%{
        mission_id: mission.mission_id,
        packet_definition_id: "hk-counter",
        packet_name: "HK",
        apid: 42,
        fields: [%{name: "counter", offset_bits: 0, size_bits: 16, data_type: :uint}]
      })

    binding_set =
      BindingSet.new(%{
        mission_id: mission.mission_id,
        binding_set_id: mission.mission_id <> "-binding-set",
        version: 1,
        capability_instances: [
          CapabilityInstance.new(%{
            capability_instance_id: mission.mission_id <> "-hk-counter-instance",
            family_key: :definition_bound_telemetry,
            target_scope: :mission,
            runtime_configuration: packet_definition
          })
        ],
        rules: [
          BindingRule.new(%{
            binding_rule_id: mission.mission_id <> "-hk-counter-rule",
            capability_instance_id: mission.mission_id <> "-hk-counter-instance",
            handler_key: :definition_bound_telemetry,
            packet_kind: :space_packet,
            apid: 42,
            handler_configuration: packet_definition
          })
        ]
      })

    {:ok, persisted} = Cadence.persist_binding_set(org.organization_id, binding_set)
    persisted
  end

  defp activate_binding_set!(org, mission, binding_set) do
    {:ok, _activation} =
      Cadence.activate_binding_set(
        org.organization_id,
        mission.mission_id,
        binding_set.binding_set_id,
        binding_set.version,
        []
      )
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

  test "runs the dashboard lifecycle across create edit publish conflict revert archive restore and audit surfaces" do
    enable_dashboard_engine_inline_resolves!()

    {conn, user, org, mission} = signed_in_user_org_and_mission()
    binding_set = persist_binding_set!(org, mission)
    activate_binding_set!(org, mission, binding_set)

    {:ok, new_view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/ops/dashboards/new")

    new_view
    |> form("#dashboard-form", dashboard: %{name: "Lifecycle Console", description: "Ops"})
    |> render_submit()

    assert [%Cadence.Dashboards.DashboardSummary{} = created_summary] =
             Cadence.Dashboards.list_dashboard_summaries(
               org.organization_id,
               mission.mission_id
             )

    {dashboard_path, _flash} = assert_redirect(new_view)
    assert dashboard_path == show_path(mission, created_summary)

    dashboard = fetch_dashboard_document!(org, mission, created_summary)
    assert dashboard.name == "Lifecycle Console"
    assert Document.version(dashboard) == 1
    assert dashboard.placements == []

    {:ok, view, _html} = live(conn, dashboard_path)
    render_dashboard_async(view)

    assert has_element?(
             view,
             ~s(#ops-dashboard-show-page[data-dashboard-publication-state="unpublished"][data-dashboard-publishable-version="1"])
           )

    view |> element("#add-widget-button") |> render_click()
    view |> element(~s(button[phx-value-point-id="HK.counter"])) |> render_click()

    view
    |> form("#widget-form", widget: %{type: "value_tile", title: "Counter", mode: "context"})
    |> render_submit()

    render_dashboard_async(view)

    edited = fetch_dashboard_document!(org, mission, created_summary)
    assert Document.version(edited) == 2
    assert [%{widget_def: %{title: "Counter"}}] = edited.placements

    assert has_element?(
             view,
             ~s(#ops-dashboard-show-page[data-dashboard-publication-state="unpublished"][data-dashboard-publishable-version="2"])
           )

    view |> element(~s(#dashboard-menu button[phx-click="publish_dashboard"])) |> render_click()
    render_dashboard_async(view)

    assert has_element?(
             view,
             ~s(#ops-dashboard-show-page[data-dashboard-publication-state="published_current"][data-dashboard-published-current="true"][data-dashboard-publish-available="false"])
           )

    assert [%Cadence.Dashboards.DashboardSummary{} = published_summary] =
             Cadence.Dashboards.list_dashboard_summaries(
               org.organization_id,
               mission.mission_id
             )

    assert published_summary.latest_version == 2
    assert published_summary.draft_version == nil
    assert published_summary.published_version == 2

    assert {:ok, %Document{} = externally_updated} =
             Cadence.Dashboards.update_document(
               org.organization_id,
               mission.mission_id,
               created_summary.dashboard_id,
               %Document{edited | name: "Lifecycle Console Updated"},
               expected_version: 2,
               created_by: "other-operator",
               change_summary: "External edit"
             )

    assert Document.version(externally_updated) == 3

    view |> element("#add-widget-button") |> render_click()
    view |> element(~s(button[phx-value-point-id="HK.counter"])) |> render_click()

    html =
      view
      |> form("#widget-form",
        widget: %{type: "value_tile", title: "Late Counter", mode: "context"}
      )
      |> render_submit()

    assert html =~ "Dashboard changed in another session"
    assert has_element?(view, "h1", "Lifecycle Console Updated")

    conflicted = fetch_dashboard_document!(org, mission, created_summary)
    assert Document.version(conflicted) == 3
    assert conflicted.name == "Lifecycle Console Updated"
    assert [%{widget_def: %{title: "Counter"}}] = conflicted.placements

    view |> element("#dashboard-versions-button") |> render_click()

    assert has_element?(
             view,
             ~s(#dashboard-version-2[data-version-publish-available="false"][data-version-publish-reason="already_published"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-version-3[data-version-restore-available="false"][data-version-restore-reason="already_latest"])
           )

    assert has_element?(
             view,
             ~s([data-lifecycle-event-type="published"] [data-activity-field="Published"]),
             "- -> v2"
           )

    view |> element("#restore-version-1") |> render_click()

    assert has_element?(
             view,
             ~s(#ops-dashboard-show-page[data-dashboard-document-mode="draft"][data-dashboard-publication-state="draft_ahead"][data-dashboard-publishable-version="4"])
           )

    restored_draft = fetch_dashboard_document!(org, mission, created_summary)
    assert Document.version(restored_draft) == 4
    assert restored_draft.name == "Lifecycle Console"
    assert restored_draft.placements == []

    view |> element("#dashboard-versions-button") |> render_click()

    assert has_element?(
             view,
             ~s([data-lifecycle-event-type="reverted"][data-lifecycle-source-version="1"][data-lifecycle-reverted-version="4"])
           )

    view
    |> element(~s(#dashboard-menu button[phx-click="archive_dashboard"]))
    |> render_click()

    assert %{"info" => "Dashboard archived."} =
             assert_redirect(view, ~p"/missions/#{mission.mission_id}/ops/dashboards")

    assert [] =
             Cadence.Dashboards.list_dashboard_summaries(
               org.organization_id,
               mission.mission_id
             )

    assert [%Cadence.Dashboards.DashboardSummary{} = archived_summary] =
             Cadence.Dashboards.list_archived_dashboard_summaries(
               org.organization_id,
               mission.mission_id
             )

    assert archived_summary.lifecycle_state == "archived"
    assert archived_summary.latest_version == 4

    {:ok, list_view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/ops/dashboards")

    assert has_element?(
             list_view,
             ~s(#archived-dashboard-#{created_summary.dashboard_id}[data-dashboard-publication-state="archived"][data-dashboard-restore-available="true"])
           )

    list_view
    |> element("#restore-dashboard-#{created_summary.dashboard_id}")
    |> render_click()

    assert has_element?(
             list_view,
             ~s(#active-dashboard-#{created_summary.dashboard_id}[data-dashboard-publication-state="draft_ahead"][data-dashboard-archive-available="true"][data-dashboard-restore-available="false"])
           )

    assert [
             %Cadence.Dashboards.LifecycleEvent{event_type: :published, dashboard_version: 2},
             %Cadence.Dashboards.LifecycleEvent{
               event_type: :reverted,
               dashboard_version: 4
             },
             %Cadence.Dashboards.LifecycleEvent{event_type: :archived, dashboard_version: 4},
             %Cadence.Dashboards.LifecycleEvent{event_type: :restored, dashboard_version: 4}
           ] =
             Cadence.Dashboards.list_lifecycle_events(
               org.organization_id,
               mission.mission_id,
               created_summary.dashboard_id
             )

    {:ok, restored_view, _html} = live(conn, dashboard_path)
    render_dashboard_async(restored_view)

    assert has_element?(
             restored_view,
             ~s(#ops-dashboard-show-page[data-dashboard-publication-state="draft_ahead"][data-dashboard-publishable-version="4"][data-dashboard-draft-ahead="true"])
           )

    restored_view |> element("#dashboard-versions-button") |> render_click()

    assert has_element?(restored_view, ~s([data-lifecycle-event-type="published"]))
    assert has_element?(restored_view, ~s([data-lifecycle-event-type="reverted"]))
    assert has_element?(restored_view, ~s([data-lifecycle-event-type="archived"]))
    assert has_element?(restored_view, ~s([data-lifecycle-event-type="restored"]))

    assert has_element?(
             restored_view,
             ~s([data-lifecycle-event-type="restored"] [data-activity-field="Actor"]),
             user.user_id
           )
  end
end
