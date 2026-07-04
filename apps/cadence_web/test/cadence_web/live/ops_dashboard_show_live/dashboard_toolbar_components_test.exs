defmodule CadenceWeb.OpsDashboardShowLive.DashboardToolbarComponentsTest do
  use ExUnit.Case, async: true

  import CadenceWeb.DashboardReviewFixtures
  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Cadence.Dashboards.{ComparisonReviewQueue, DataBinding}
  alias CadenceWeb.OpsDashboardShowLive.DashboardToolbarComponents

  test "dashboard_toolbar renders dashboard actions with lifecycle availability" do
    html =
      render_component(
        &DashboardToolbarComponents.dashboard_toolbar/1,
        toolbar_assigns(
          edit_mode?: true,
          dashboard_lifecycle_status: %{publish_available?: false, archive_available?: true}
        )
      )

    document = LazyHTML.from_fragment(html)

    assert html =~ "Live updates paused while editing"
    assert html =~ "Done"

    assert ["false"] =
             document
             |> LazyHTML.query(~s(button[data-dashboard-lifecycle-action="publish"]))
             |> LazyHTML.attribute("data-dashboard-action-available")

    assert ["true"] =
             document
             |> LazyHTML.query(~s(button[data-dashboard-lifecycle-action="archive"]))
             |> LazyHTML.attribute("data-dashboard-action-available")

    assert ["open_historical_workflow_request"] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-request-button")
             |> LazyHTML.attribute("phx-click")

    assert ["open_diagnostics"] =
             document
             |> LazyHTML.query("#dashboard-diagnostics-button")
             |> LazyHTML.attribute("phx-click")

    assert [] =
             document
             |> LazyHTML.query("#runtime-context-controls")
             |> LazyHTML.attribute("id")
  end

  test "dashboard_toolbar routes versions button to review activity when review work is open" do
    lifecycle_events = [
      comparison_review_request_event(
        event_id: "review-request-1",
        placement_ids: ["placement-1", "placement-2"]
      ),
      comparison_review_request_event(
        event_id: "review-request-2",
        payload: %{
          "open_findings" => %{
            "findings" => [%{"placement_id" => "placement-3"}]
          }
        }
      ),
      comparison_review_resolution_event(
        event_id: "review-resolution-2",
        source_request_event_id: "review-request-2"
      )
    ]

    html =
      render_component(
        &DashboardToolbarComponents.dashboard_toolbar/1,
        toolbar_assigns(
          dashboard_lifecycle_events: lifecycle_events,
          dashboard_comparison_review_queue: ComparisonReviewQueue.open_summary(lifecycle_events)
        )
      )

    document = LazyHTML.from_fragment(html)

    assert ["open_review_activity"] =
             document
             |> LazyHTML.query("#dashboard-versions-button")
             |> LazyHTML.attribute("phx-click")

    assert ["1"] =
             document
             |> LazyHTML.query("#dashboard-versions-button")
             |> LazyHTML.attribute("data-dashboard-comparison-review-open-count")

    assert ["review-request-1"] =
             document
             |> LazyHTML.query("#dashboard-versions-button")
             |> LazyHTML.attribute("data-dashboard-comparison-review-open-requests")

    assert ["placement-1,placement-2"] =
             document
             |> LazyHTML.query("#dashboard-versions-button")
             |> LazyHTML.attribute("data-dashboard-comparison-review-open-placements")

    assert [_class] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-open-toolbar-badge]")
             |> LazyHTML.attribute("class")
  end

  test "dashboard_toolbar does not derive open review badges from lifecycle events" do
    html =
      render_component(
        &DashboardToolbarComponents.dashboard_toolbar/1,
        toolbar_assigns(
          dashboard_lifecycle_events: [
            comparison_review_request_event(
              event_id: "review-request-1",
              placement_ids: ["placement-1"]
            )
          ],
          dashboard_comparison_review_queue: ComparisonReviewQueue.open_summary([])
        )
      )

    document = LazyHTML.from_fragment(html)

    assert ["open_versions"] =
             document
             |> LazyHTML.query("#dashboard-versions-button")
             |> LazyHTML.attribute("phx-click")

    assert ["0"] =
             document
             |> LazyHTML.query("#dashboard-versions-button")
             |> LazyHTML.attribute("data-dashboard-comparison-review-open-count")

    assert [] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-review-open-toolbar-badge]")
             |> LazyHTML.attribute("class")
  end

  test "dashboard_toolbar routes versions button from materialized review queue" do
    queue_request =
      comparison_review_request_event(
        event_id: "review-request-from-queue",
        placement_ids: ["placement-9"]
      )

    html =
      render_component(
        &DashboardToolbarComponents.dashboard_toolbar/1,
        toolbar_assigns(
          dashboard_lifecycle_events: [],
          dashboard_comparison_review_queue: %{
            count: 1,
            count_text: "1",
            requests: [queue_request],
            request_ids: ["review-request-from-queue"],
            request_ids_attr: "review-request-from-queue",
            placement_ids: ["placement-9"],
            placements_attr: "placement-9"
          }
        )
      )

    document = LazyHTML.from_fragment(html)

    assert ["open_review_activity"] =
             document
             |> LazyHTML.query("#dashboard-versions-button")
             |> LazyHTML.attribute("phx-click")

    assert ["1"] =
             document
             |> LazyHTML.query("#dashboard-versions-button")
             |> LazyHTML.attribute("data-dashboard-comparison-review-open-count")

    assert ["review-request-from-queue"] =
             document
             |> LazyHTML.query("#dashboard-versions-button")
             |> LazyHTML.attribute("data-dashboard-comparison-review-open-requests")

    assert ["placement-9"] =
             document
             |> LazyHTML.query("#dashboard-versions-button")
             |> LazyHTML.attribute("data-dashboard-comparison-review-open-placements")
  end

  test "dashboard_toolbar renders publish readiness summary" do
    html =
      render_component(
        &DashboardToolbarComponents.dashboard_toolbar/1,
        toolbar_assigns(
          dashboard_publish_readiness: %{
            status: "blocked",
            label: "blocked",
            issues: [
              %{severity: :error, code: "invalid_runtime_default_context"},
              %{severity: :error, code: "unready_publish_source_request"}
            ]
          }
        )
      )

    document = LazyHTML.from_fragment(html)

    assert ["blocked"] =
             document
             |> LazyHTML.query("#dashboard-publish-readiness-summary")
             |> LazyHTML.attribute("data-dashboard-publish-readiness-status")

    assert ["2"] =
             document
             |> LazyHTML.query("#dashboard-publish-readiness-summary")
             |> LazyHTML.attribute("data-dashboard-publish-readiness-issue-count")

    assert ["open_versions"] =
             document
             |> LazyHTML.query("#dashboard-publish-readiness-summary")
             |> LazyHTML.attribute("phx-click")

    assert html =~ "Publish blocked"
  end

  test "dashboard_toolbar renders stale publish readiness summary" do
    html =
      render_component(
        &DashboardToolbarComponents.dashboard_toolbar/1,
        toolbar_assigns(
          dashboard_publish_readiness: %{
            status: "stale",
            label: "needs re-check",
            issues: []
          }
        )
      )

    document = LazyHTML.from_fragment(html)

    assert ["stale"] =
             document
             |> LazyHTML.query("#dashboard-publish-readiness-summary")
             |> LazyHTML.attribute("data-dashboard-publish-readiness-status")

    assert html =~ "Re-check publish"
  end

  defp toolbar_assigns(overrides) do
    Keyword.merge(
      [
        dashboard_document: %{name: "Ops", description: "Operations"},
        dashboard_lifecycle_status: %{publish_available?: true, archive_available?: false},
        dashboard_lifecycle_events: [],
        dashboard_comparison_review_queue: ComparisonReviewQueue.open_summary([]),
        edit_mode?: false,
        show_context?: true,
        current_mission: %{mission_id: "mission-1", display_name: "Lunar Demo"},
        spacecraft: [
          %{spacecraft_id: "spacecraft-1", display_name: "Alpha", scid: 101}
        ],
        scheduled_contacts: [],
        realized_contacts: [],
        context_spacecraft_id: nil,
        context_scope_kind: "mission",
        context_scope_id: "mission-1",
        time_mode: "live",
        time_from: nil,
        time_to: nil,
        replay_run_id: nil,
        time_validation: "ok",
        data_realm: "flight",
        data_realms: ["flight"],
        data_view: "canonical",
        compare_data_view: nil,
        data_source_id: nil,
        source_binding_id: nil,
        data_bindings: [data_binding()],
        limit_mode: "observed",
        selected_data_ref: nil,
        query: ""
      ],
      overrides
    )
  end

  defp data_binding do
    %DataBinding{
      binding_id: "flight-binding",
      data_source_id: "questdb-flight",
      dataset: "flight",
      realm: :flight,
      logical_source: :telemetry,
      priority: 0,
      status: :active
    }
  end
end
