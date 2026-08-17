defmodule CadenceWeb.OpsDashboardShowLive.DashboardLifecycleLiveTest do
  use CadenceWeb.ConnCase, async: false

  @moduletag :config

  import Phoenix.LiveViewTest
  import CadenceWeb.OpsDashboardShowLive.ViewTestSupport

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

    {:ok, persisted} = Cadence.Governance.persist_binding_set(org.organization_id, binding_set)
    persisted
  end

  defp activate_binding_set!(org, mission, binding_set) do
    {:ok, _activation} =
      Cadence.ActivationFixtures.activate_binding_set(
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

  test "runs the dashboard lifecycle across the Editor, Activity, Settings, Directory, and Viewer" do
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

    editor_path =
      ~p"/missions/#{mission.mission_id}/ops/dashboards/#{created_summary.dashboard_id}/edit"

    activity_path =
      ~p"/missions/#{mission.mission_id}/ops/dashboards/#{created_summary.dashboard_id}/activity"

    settings_path =
      ~p"/missions/#{mission.mission_id}/ops/dashboards/#{created_summary.dashboard_id}/settings"

    {dashboard_path, _flash} = assert_redirect(new_view)
    assert dashboard_path == editor_path

    dashboard = fetch_dashboard_document!(org, mission, created_summary)
    assert dashboard.name == "Lifecycle Console"
    assert Document.version(dashboard) == 1
    assert dashboard.placements == []

    {:ok, editor, _html} = live(conn, dashboard_path)
    render_dashboard_async(editor)

    assert has_element?(
             editor,
             ~s(#ops-dashboard-show-page[data-dashboard-editor="true"][data-editor-dirty="false"])
           )

    editor |> element("#add-widget-button") |> render_click()
    editor |> element(~s(button[phx-value-point-id="HK.counter"])) |> render_click()

    editor
    |> form("#widget-form", widget: %{type: "value_tile", title: "Counter", mode: "context"})
    |> render_submit()

    render_dashboard_async(editor)

    assert Document.version(fetch_dashboard_document!(org, mission, created_summary)) == 1
    editor |> element("#dashboard-editor-save") |> render_click()

    edited = fetch_dashboard_document!(org, mission, created_summary)
    assert Document.version(edited) == 2
    assert [%{widget_def: %{title: "Counter"}}] = edited.placements

    {:ok, activity, _html} = live(conn, activity_path)
    assert has_element?(activity, ~s(#dashboard-version-detail[data-selected-version="2"]))
    activity |> element("#dashboard-activity-publish") |> render_click()
    assert has_element?(activity, ~s([data-dashboard-activity-type="published"]))

    assert [%Cadence.Dashboards.DashboardSummary{} = published_summary] =
             Cadence.Dashboards.list_dashboard_summaries(
               org.organization_id,
               mission.mission_id
             )

    assert published_summary.latest_version == 2
    assert published_summary.draft_version == nil
    assert published_summary.published_version == 2

    activity |> element("#dashboard-version-1") |> render_click()
    assert has_element?(activity, ~s(#dashboard-version-detail[data-selected-version="1"]))
    activity |> element("#dashboard-activity-restore") |> render_click()

    restored_draft = fetch_dashboard_document!(org, mission, created_summary)
    assert Document.version(restored_draft) == 3
    assert restored_draft.name == "Lifecycle Console"
    assert restored_draft.placements == []
    assert has_element?(activity, ~s([data-dashboard-activity-type="reverted"]))

    {:ok, settings, _html} = live(conn, settings_path)
    settings |> element("#dashboard-settings-archive") |> render_click()

    assert %{"info" => "Dashboard archived."} =
             assert_redirect(settings, ~p"/missions/#{mission.mission_id}/ops/dashboards")

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
    assert archived_summary.latest_version == 3

    {:ok, list_view, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/ops/dashboards?lifecycle=all")

    assert has_element?(
             list_view,
             ~s(#dashboard-directory-row-#{created_summary.dashboard_id}[data-dashboard-directory-lifecycle="archived"])
           )

    list_view
    |> element("#restore-dashboard-#{created_summary.dashboard_id}")
    |> render_click()

    assert has_element?(
             list_view,
             ~s(#dashboard-directory-row-#{created_summary.dashboard_id}[data-dashboard-directory-lifecycle="active"])
           )

    assert [
             %Cadence.Dashboards.LifecycleEvent{event_type: :published, dashboard_version: 2},
             %Cadence.Dashboards.LifecycleEvent{
               event_type: :reverted,
               dashboard_version: 3
             },
             %Cadence.Dashboards.LifecycleEvent{event_type: :archived, dashboard_version: 3},
             %Cadence.Dashboards.LifecycleEvent{event_type: :restored, dashboard_version: 3}
           ] =
             Cadence.Dashboards.list_lifecycle_events(
               org.organization_id,
               mission.mission_id,
               created_summary.dashboard_id
             )

    {:ok, restored_view, _html} = live(conn, show_path(mission, created_summary))
    render_dashboard_async(restored_view)

    assert has_element?(
             restored_view,
             ~s(#ops-dashboard-show-page[data-dashboard-publication-state="draft_ahead"][data-dashboard-publishable-version="3"][data-dashboard-draft-ahead="true"])
           )

    {:ok, final_activity, _html} = live(conn, activity_path)
    assert has_element?(final_activity, ~s([data-dashboard-activity-type="published"]))
    assert has_element?(final_activity, ~s([data-dashboard-activity-type="reverted"]))
    assert has_element?(final_activity, ~s([data-dashboard-activity-type="archived"]))
    assert has_element?(final_activity, ~s([data-dashboard-activity-type="restored"]))

    assert Cadence.Dashboards.list_lifecycle_events(
             org.organization_id,
             mission.mission_id,
             created_summary.dashboard_id
           )
           |> List.last()
           |> Map.fetch!(:actor_id) == user.user_id
  end
end
