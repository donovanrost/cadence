defmodule CadenceWeb.OpsDashboardShowLive.ActivityTimelineShellComponentsTest do
  use ExUnit.Case, async: true

  import CadenceWeb.DashboardReviewFixtures
  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Cadence.Dashboards.{ComparisonReviewQueue, Document}
  alias CadenceWeb.OpsDashboardShowLive.ActivityEventSummary
  alias CadenceWeb.OpsDashboardShowLive.ActivityTimelineShellComponents
  alias CadenceWeb.OpsDashboardShowLive.ActivityViewModel
  alias CadenceWeb.OpsDashboardShowLive.ComparisonReviewActionOutcome

  test "activity_timeline_shell renders filter controls and open review queue metadata" do
    open_request_event =
      comparison_review_request_event(
        event_id: "dashboard-lifecycle-event-open",
        placement_ids: ["placement-open"],
        occurred_at: ~U[2026-06-24 12:00:00Z]
      )

    resolved_request_event =
      comparison_review_request_event(
        event_id: "dashboard-lifecycle-event-resolved",
        placement_ids: ["placement-resolved"],
        occurred_at: ~U[2026-06-24 12:01:00Z]
      )

    resolution_event =
      comparison_review_resolution_event(
        event_id: "dashboard-lifecycle-event-resolution",
        source_request_event_id: "dashboard-lifecycle-event-resolved",
        occurred_at: ~U[2026-06-24 12:02:00Z],
        payload: %{
          "schema" => "dashboard_comparison_review_resolution.v1",
          "source_request_event_id" => "dashboard-lifecycle-event-resolved",
          "disposition" => "review_completed"
        }
      )

    lifecycle_events = [open_request_event, resolved_request_event, resolution_event]

    activity =
      ActivityViewModel.build(lifecycle_events, :open_comparison_reviews,
        open_summary: ComparisonReviewQueue.open_summary(lifecycle_events),
        selected_placement_id: "placement-open"
      )

    html =
      render_shell(
        activity: activity,
        activity_rows: ActivityEventSummary.rows(activity.visible_events, nil, []),
        selected_activity_event:
          ActivityEventSummary.build(
            lifecycle_events,
            nil,
            activity.visible_events,
            activity,
            [],
            []
          ),
        dashboard_lifecycle_events: lifecycle_events,
        dashboard_review_placement_id: "placement-open"
      )

    vue = LiveVue.Test.get_vue(html, id: "dashboard-activity-controls-component")

    assert vue.component == "DashboardActivityControls"
    assert vue.id == "dashboard-activity-controls-component"
    assert vue.class == "contents"
    assert vue.ssr == false
    assert vue.handlers == %{}
    assert vue.slots == %{}
    assert Map.keys(vue.props) == ["presentation"]
    assert vue.props == Jason.decode!(Jason.encode!(vue.props))

    presentation = vue.props["presentation"]
    assert Map.keys(presentation) |> Enum.sort() == ["controls", "header"]

    header = presentation["header"]
    assert header["class"] == "flex items-center justify-between"
    assert header["leading_class"] == "flex items-center gap-2"

    [title, open_badge, filter_badge, clear_filter] = header["items"]

    assert title == %{
             "attrs" => %{"data-dashboard-activity-title" => "open_comparison_reviews"},
             "class" => "hud-label",
             "id" => nil,
             "key" => "title",
             "order" => 0,
             "tag" => "h3",
             "text" => "Review Queue",
             "type" => nil,
             "visible" => true
           }

    assert open_badge == %{
             "attrs" => %{"data-dashboard-comparison-review-open-badge" => ""},
             "class" => "badge badge-warning badge-xs",
             "id" => nil,
             "key" => "open-review-badge",
             "order" => 1,
             "tag" => "span",
             "text" => "1 open reviews",
             "type" => nil,
             "visible" => true
           }

    assert filter_badge == %{
             "attrs" => %{
               "data-dashboard-activity-filter-badge" => "open_comparison_reviews"
             },
             "class" => "badge badge-info badge-outline badge-xs",
             "id" => nil,
             "key" => "active-filter-badge",
             "order" => 2,
             "tag" => "span",
             "text" => "Open reviews",
             "type" => nil,
             "visible" => true
           }

    assert clear_filter == %{
             "attrs" => %{
               "data-dashboard-activity-clear-filter" => "open_comparison_reviews",
               "phx-click" => "open_versions"
             },
             "class" => "btn btn-ghost btn-xs",
             "id" => "dashboard-activity-clear-filter",
             "key" => "clear-filter",
             "order" => 3,
             "tag" => "button",
             "text" => "Show all",
             "type" => "button",
             "visible" => true
           }

    assert header["count"] == %{
             "class" => "font-mono text-xs text-base-content/50",
             "text" => "1 / 3"
           }

    controls = presentation["controls"]
    assert controls["id"] == "dashboard-activity-filter-controls"
    assert controls["class"] == "flex flex-wrap gap-1"
    assert controls["attrs"] == %{"data-dashboard-activity-filter-controls" => ""}

    filters = controls["filters"]

    assert Enum.map(filters, & &1["key"]) ==
             ~w(all version-changes reviews open-reviews health-snapshots publish-readiness)

    assert Enum.map(filters, & &1["order"]) == [0, 1, 2, 3, 4, 5]
    assert Enum.map(filters, & &1["tag"]) == List.duplicate("button", 6)

    assert Enum.map(filters, & &1["id"]) == [
             "dashboard-activity-filter-all",
             "dashboard-activity-filter-version-changes",
             "dashboard-activity-filter-reviews",
             "dashboard-activity-filter-open-reviews",
             "dashboard-activity-filter-health-snapshots",
             "dashboard-activity-filter-publish-readiness"
           ]

    assert Enum.map(filters, & &1["type"]) == List.duplicate("button", 6)

    assert Enum.map(filters, & &1["class"]) == [
             "btn btn-ghost btn-xs",
             "btn btn-ghost btn-xs",
             "btn btn-ghost btn-xs",
             "btn btn-primary btn-xs",
             "btn btn-ghost btn-xs",
             "btn btn-ghost btn-xs"
           ]

    assert Enum.map(filters, & &1["text"]) ==
             ["All", "Versions", "Reviews", "Open reviews", "Health", "Readiness"]

    assert Enum.map(filters, & &1["attrs"]) == [
             %{
               "data-dashboard-activity-filter-option" => "",
               "data-dashboard-activity-filter-selected" => "false",
               "phx-click" => "set_activity_filter",
               "phx-value-filter" => ""
             },
             %{
               "data-dashboard-activity-filter-option" => "version_changes",
               "data-dashboard-activity-filter-selected" => "false",
               "phx-click" => "set_activity_filter",
               "phx-value-filter" => "version_changes"
             },
             %{
               "data-dashboard-activity-filter-option" => "comparison_reviews",
               "data-dashboard-activity-filter-selected" => "false",
               "phx-click" => "set_activity_filter",
               "phx-value-filter" => "comparison_reviews"
             },
             %{
               "data-dashboard-activity-filter-option" => "open_comparison_reviews",
               "data-dashboard-activity-filter-selected" => "true",
               "phx-click" => "set_activity_filter",
               "phx-value-filter" => "open_comparison_reviews"
             },
             %{
               "data-dashboard-activity-filter-option" => "health_snapshots",
               "data-dashboard-activity-filter-selected" => "false",
               "phx-click" => "set_activity_filter",
               "phx-value-filter" => "health_snapshots"
             },
             %{
               "data-dashboard-activity-filter-option" => "publish_readiness",
               "data-dashboard-activity-filter-selected" => "false",
               "phx-click" => "set_activity_filter",
               "phx-value-filter" => "publish_readiness"
             }
           ]

    document = LazyHTML.from_fragment(html)

    assert ["open_comparison_reviews"] =
             document
             |> LazyHTML.query("#dashboard-activity-section")
             |> LazyHTML.attribute("data-dashboard-activity-mode")

    assert ["true"] =
             document
             |> LazyHTML.query("#dashboard-activity-section")
             |> LazyHTML.attribute("data-dashboard-comparison-review-work-queue")

    assert ["1"] =
             document
             |> LazyHTML.query("#dashboard-activity-section")
             |> LazyHTML.attribute("data-dashboard-comparison-review-work-queue-count")

    assert "open_versions" = clear_filter["attrs"]["phx-click"]

    open_reviews = Enum.find(filters, &(&1["id"] == "dashboard-activity-filter-open-reviews"))
    assert "true" = open_reviews["attrs"]["data-dashboard-activity-filter-selected"]

    reviews = Enum.find(filters, &(&1["id"] == "dashboard-activity-filter-reviews"))
    assert "false" = reviews["attrs"]["data-dashboard-activity-filter-selected"]

    row =
      LiveVue.Test.get_vue(html,
        id: "dashboard-activity-row-dashboard-lifecycle-event-open-component"
      )

    assert row.component == "ActivityTimelineRow"

    assert row.props["presentation"]["root"]["attrs"][
             "data-dashboard-comparison-review-work-queue-item"
           ] == "dashboard-lifecycle-event-open"
  end

  test "activity_timeline_shell renders the no lifecycle activity empty state" do
    activity =
      ActivityViewModel.build([], nil, open_summary: ComparisonReviewQueue.open_summary([]))

    html =
      render_shell(
        activity: activity,
        activity_rows: [],
        selected_activity_event: ActivityEventSummary.build([], nil, [], activity, [], []),
        dashboard_lifecycle_events: []
      )

    presentation =
      html
      |> LiveVue.Test.get_vue(id: "dashboard-activity-controls-component")
      |> then(& &1.props["presentation"])

    assert Enum.map(presentation["header"]["items"], & &1["visible"]) ==
             [true, false, false, false]

    assert Enum.map(
             presentation["controls"]["filters"],
             & &1["attrs"]["data-dashboard-activity-filter-selected"]
           ) == ["true", "false", "false", "false", "false", "false"]

    document = LazyHTML.from_fragment(html)

    assert ["no_lifecycle"] =
             document
             |> LazyHTML.query("[data-dashboard-activity-empty]")
             |> LazyHTML.attribute("data-dashboard-activity-empty")

    assert "No lifecycle activity." =
             document
             |> LazyHTML.query("[data-dashboard-activity-empty]")
             |> selected_text()
  end

  test "activity_timeline_shell renders comparison review action outcome metadata" do
    activity =
      ActivityViewModel.build([], nil, open_summary: ComparisonReviewQueue.open_summary([]))

    html =
      render_shell(
        activity: activity,
        activity_rows: [],
        selected_activity_event: ActivityEventSummary.build([], nil, [], activity, [], []),
        dashboard_lifecycle_events: [],
        dashboard_comparison_review_action_outcome:
          ComparisonReviewActionOutcome.new(
            status: :degraded,
            kind: :warning,
            reason: "comparison_review_bulk_decision_partially_applied",
            decision: "mark_conflict",
            source_request_event_id: "review-request-1",
            workflow_id: "review-request-1",
            requested: 2,
            applied: 1,
            failed: 1,
            scope_kind: "transport",
            scope_ids: "transport-alpha,transport-beta",
            contact_ids: "contact-alpha,contact-beta",
            resource_ids: "transport-alpha",
            transport_ids: "transport-alpha",
            source_endpoint_ids: "endpoint-alpha",
            ground_station_ids: "dss-14",
            scope_link_ids: "link-alpha",
            result_event_ids: "decision-event-1",
            target_event_id: "review-request-1",
            message: "Comparison review decisions applied to 1 findings; 1 failed."
          )
      )

    document = LazyHTML.from_fragment(html)

    assert ["comparison_review_bulk_decision"] =
             document
             |> LazyHTML.query("#dashboard-comparison-review-action-outcome")
             |> LazyHTML.attribute("data-dashboard-comparison-review-action")

    assert ["degraded"] =
             document
             |> LazyHTML.query("#dashboard-comparison-review-action-outcome")
             |> LazyHTML.attribute("data-dashboard-comparison-review-action-status")

    assert ["warning"] =
             document
             |> LazyHTML.query("#dashboard-comparison-review-action-outcome")
             |> LazyHTML.attribute("data-dashboard-comparison-review-action-kind")

    assert ["comparison_review_bulk_decision_partially_applied"] =
             document
             |> LazyHTML.query("#dashboard-comparison-review-action-outcome")
             |> LazyHTML.attribute("data-dashboard-comparison-review-action-reason")

    action =
      LazyHTML.query(document, "#dashboard-comparison-review-action-outcome")

    assert ["review-request-1"] =
             LazyHTML.attribute(
               action,
               "data-dashboard-comparison-review-action-source-request-id"
             )

    assert ["review-request-1"] =
             LazyHTML.attribute(action, "data-dashboard-comparison-review-action-workflow-id")

    assert ["2"] =
             LazyHTML.attribute(action, "data-dashboard-comparison-review-action-requested")

    assert ["1"] =
             LazyHTML.attribute(action, "data-dashboard-comparison-review-action-applied")

    assert ["1"] =
             LazyHTML.attribute(action, "data-dashboard-comparison-review-action-failed")

    assert ["transport"] =
             LazyHTML.attribute(action, "data-dashboard-comparison-review-action-scope-kind")

    assert ["transport-alpha,transport-beta"] =
             LazyHTML.attribute(action, "data-dashboard-comparison-review-action-scope-ids")

    assert ["contact-alpha,contact-beta"] =
             LazyHTML.attribute(action, "data-dashboard-comparison-review-action-contact-ids")

    assert ["transport-alpha"] =
             LazyHTML.attribute(action, "data-dashboard-comparison-review-action-resource-ids")

    assert ["transport-alpha"] =
             LazyHTML.attribute(action, "data-dashboard-comparison-review-action-transport-ids")

    assert ["endpoint-alpha"] =
             LazyHTML.attribute(
               action,
               "data-dashboard-comparison-review-action-source-endpoint-ids"
             )

    assert ["dss-14"] =
             LazyHTML.attribute(
               action,
               "data-dashboard-comparison-review-action-ground-station-ids"
             )

    assert ["link-alpha"] =
             LazyHTML.attribute(action, "data-dashboard-comparison-review-action-scope-link-ids")

    assert ["decision-event-1"] =
             LazyHTML.attribute(
               action,
               "data-dashboard-comparison-review-action-result-event-ids"
             )

    assert ["review-request-1"] =
             LazyHTML.attribute(action, "data-dashboard-comparison-review-action-target-event-id")

    assert "Partial" =
             document
             |> LazyHTML.query("#dashboard-comparison-review-action-outcome .badge")
             |> selected_text()

    [metadata_json] =
      document
      |> LazyHTML.query("#dashboard-comparison-review-action-outcome")
      |> LazyHTML.attribute("data-dashboard-comparison-review-action-metadata")

    assert Jason.decode!(metadata_json) == %{
             "decision" => "mark_conflict",
             "source_request_event_id" => "review-request-1",
             "workflow_id" => "review-request-1",
             "requested" => "2",
             "applied" => "1",
             "failed" => "1",
             "scope_kind" => "transport",
             "scope_ids" => "transport-alpha,transport-beta",
             "contact_ids" => "contact-alpha,contact-beta",
             "resource_ids" => "transport-alpha",
             "transport_ids" => "transport-alpha",
             "source_endpoint_ids" => "endpoint-alpha",
             "ground_station_ids" => "dss-14",
             "scope_link_ids" => "link-alpha",
             "result_event_ids" => "decision-event-1",
             "target_event_id" => "review-request-1"
           }

    action_text =
      document
      |> LazyHTML.query("#dashboard-comparison-review-action-outcome")
      |> selected_text()

    assert action_text =~ "Comparison Review Action"
    assert action_text =~ "Comparison review decisions applied to 1 findings; 1 failed."
    assert action_text =~ "Requested"
    assert action_text =~ "2"
    assert action_text =~ "Applied"
    assert action_text =~ "1"
    assert action_text =~ "Failed"
    assert action_text =~ "Scope"
    assert action_text =~ "transport"
    assert action_text =~ "Scope IDs"
    assert action_text =~ "transport-alpha,transport-beta"
    assert action_text =~ "Contacts"
    assert action_text =~ "contact-alpha,contact-beta"
    assert action_text =~ "Resources"
    assert action_text =~ "Source endpoints"
    assert action_text =~ "Ground stations"
    assert action_text =~ "Scope links"
    assert action_text =~ "review-request-1"
    assert action_text =~ "decision-event-1"
  end

  defp render_shell(assigns) do
    defaults = [
      dashboard_document: dashboard_document(),
      dashboard_activity_event_id: nil,
      dashboard_review_placement_id: nil,
      dashboard_readiness_return_intent: nil,
      dashboard_current_path: "/missions/mission-1/ops/dashboards/dashboard-1"
    ]

    render_component(
      &ActivityTimelineShellComponents.activity_timeline_shell/1,
      Keyword.merge(defaults, assigns)
    )
  end

  defp dashboard_document do
    %Document{
      dashboard_id: "dashboard-1",
      organization_id: "org-1",
      mission_id: "mission-1",
      name: "Dashboard"
    }
  end

  defp selected_text(lazy_html) do
    lazy_html
    |> LazyHTML.text()
    |> String.trim()
  end
end
