defmodule CadenceWeb.OpsDashboardShowLive.DashboardLifecyclePublishValidationLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import CadenceWeb.OpsDashboardShowLive.ViewTestSupport

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Dashboards.Document
  alias Cadence.Dashboards.DocumentStore.DashboardRow, as: OpsDashboardRow
  alias Cadence.Persistence.JsonDocument
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

  defp value_tile(point_id, mode \\ :context, spacecraft_id \\ nil) do
    %{
      type: :value_tile,
      title: "Counter",
      binding: %{mode: mode, spacecraft_id: spacecraft_id, point_id: point_id}
    }
  end

  defp show_path(mission, dashboard) do
    ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}/activity"
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

  defp with_invalid_grid(%Document{} = document) do
    grid = Map.put(document.grid, :columns, 0)
    %Document{document | grid: grid}
  end

  defp with_unknown_widget(%Document{placements: [placement | rest]} = document) do
    widget_def = %{placement.widget_def | widget_type_id: "partner.spectrum_waterfall"}
    Document.replace_placements(document, [%{placement | widget_def: widget_def} | rest])
  end

  describe "dashboard lifecycle publish validation" do
    test "blocks publish and opens validation details when the saved draft is invalid" do
      {conn, org, mission} = signed_in_org_and_mission()
      dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Invalid Publish")

      replace_dashboard_row_document!(org, mission, with_invalid_grid(dashboard))

      {:ok, view, _html} = live(conn, show_path(mission, dashboard))
      render_dashboard_async(view)

      render_hook(view, "publish_version", %{"version" => "1"})

      presentation = publish_validation_presentation(view)

      assert presentation["root"]["attrs"]["data-publish-validation-status"] == "blocked"

      [issue] = presentation["issues"]["rows"]

      assert issue["attrs"] == %{
               "data-publish-validation-issue-id" => "error:invalid_grid:columns",
               "data-publish-validation-issue-selected" => "false",
               "data-publish-validation-severity" => "error",
               "data-publish-validation-code" => "invalid_grid"
             }

      field_detail =
        Enum.find(issue["details"]["rows"], fn row ->
          row["value"]["attrs"]["data-publish-validation-detail"] == "field"
        end)

      assert field_detail["value"]["text"] == "columns"

      assert [%Cadence.Dashboards.DashboardSummary{} = summary] =
               Cadence.Dashboards.list_dashboard_summaries(
                 org.organization_id,
                 mission.mission_id
               )

      assert summary.latest_version == 1
      assert summary.draft_version == 1
      assert summary.published_version == nil

      assert [] =
               Cadence.Dashboards.list_lifecycle_events(
                 org.organization_id,
                 mission.mission_id,
                 dashboard.dashboard_id
               )
    end

    test "allows warning-only draft publish and shows warnings in the publish check" do
      {conn, user, org, mission} = signed_in_user_org_and_mission()

      dashboard =
        TestFixtures.persist_dashboard_document!(mission,
          name: "Legacy Warning",
          widgets: [value_tile("HK.counter")]
        )

      assert {:ok, %Document{} = warning_document} =
               Cadence.Dashboards.update_document(
                 org.organization_id,
                 mission.mission_id,
                 dashboard.dashboard_id,
                 with_unknown_widget(dashboard),
                 expected_version: Document.version(dashboard),
                 created_by: user.user_id,
                 change_summary: "Imported legacy widget"
               )

      {:ok, view, _html} = live(conn, show_path(mission, dashboard))
      render_dashboard_async(view)

      presentation = publish_validation_presentation(view)

      assert presentation["root"]["attrs"]["data-publish-validation-status"] == "warnings"

      [issue] = presentation["issues"]["rows"]

      assert Map.take(issue["attrs"], [
               "data-publish-validation-issue-selected",
               "data-publish-validation-severity",
               "data-publish-validation-code"
             ]) == %{
               "data-publish-validation-issue-selected" => "false",
               "data-publish-validation-severity" => "warning",
               "data-publish-validation-code" => "unknown_widget_type"
             }

      render_hook(view, "publish_version", %{
        "version" => Integer.to_string(Document.version(warning_document))
      })

      {:ok, viewer, _html} =
        live(
          conn,
          ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}"
        )

      render_dashboard_async(viewer)

      assert has_element?(
               viewer,
               ~s(#ops-dashboard-show-page[data-dashboard-document-mode="published"])
             )

      assert [%Cadence.Dashboards.DashboardSummary{} = summary] =
               Cadence.Dashboards.list_dashboard_summaries(
                 org.organization_id,
                 mission.mission_id
               )

      assert summary.latest_version == Document.version(warning_document)
      assert summary.draft_version == nil
      assert summary.published_version == Document.version(warning_document)

      assert [%Cadence.Dashboards.LifecycleEvent{} = event] =
               Cadence.Dashboards.list_lifecycle_events(
                 org.organization_id,
                 mission.mission_id,
                 dashboard.dashboard_id
               )

      assert event.event_type == :published
      assert event.dashboard_version == Document.version(warning_document)
      assert event.actor_id == user.user_id
    end
  end

  defp publish_validation_presentation(view) do
    vue =
      LiveVue.Test.get_vue(view,
        id: "dashboard-version-history-summary-component"
      )

    assert vue.component == "VersionHistorySummary"
    assert vue.id == "dashboard-version-history-summary-component"
    assert vue.ssr == false
    assert vue.class == "contents"
    assert vue.handlers == %{}
    assert vue.slots == %{}
    assert vue.props == Jason.decode!(Jason.encode!(vue.props))
    vue.props["presentation"]["publish_validation"]
  end
end
