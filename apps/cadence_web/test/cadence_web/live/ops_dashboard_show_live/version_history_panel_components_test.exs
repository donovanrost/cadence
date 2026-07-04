defmodule CadenceWeb.OpsDashboardShowLive.VersionHistoryPanelComponentsTest do
  use ExUnit.Case, async: true

  import CadenceWeb.DashboardReviewFixtures
  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Cadence.Dashboards.{
    ComparisonReviewQueue,
    DashboardSummary,
    Document,
    SourceHealthEvent,
    ValidationResult,
    Version
  }

  alias CadenceWeb.OpsDashboardShowLive.{PublishReadinessModel, VersionHistoryPanelComponents}

  test "versions_panel renders version pointers and version actions" do
    html =
      render_component(&VersionHistoryPanelComponents.versions_panel/1,
        dashboard_document: dashboard_document(),
        dashboard_summary: %DashboardSummary{
          dashboard_id: "dashboard-1",
          organization_id: "org-1",
          mission_id: "mission-1",
          name: "Dashboard",
          latest_version: 2,
          draft_version: 2,
          published_version: 1
        },
        dashboard_versions: [
          version(1, :publish, "published save"),
          version(2, :draft_save, "draft save")
        ],
        dashboard_lifecycle_events: [],
        dashboard_publish_readiness: nil,
        dashboard_current_path: "/missions/mission-1/ops/dashboards/dashboard-1"
      )

    document = LazyHTML.from_fragment(html)

    assert ["2"] =
             document
             |> LazyHTML.query("#dashboard-version-list > li")
             |> LazyHTML.attribute("id")
             |> Enum.map(&String.replace_prefix(&1, "dashboard-version-", ""))
             |> Enum.take(1)

    assert ["published"] =
             document
             |> LazyHTML.query("#dashboard-version-1 [data-version-pointer]")
             |> LazyHTML.attribute("data-version-pointer")

    assert ["true"] =
             document
             |> LazyHTML.query("#dashboard-version-2")
             |> LazyHTML.attribute("data-version-publish-available")

    assert ["already_latest"] =
             document
             |> LazyHTML.query("#dashboard-version-2")
             |> LazyHTML.attribute("data-version-restore-reason")

    assert "draft save" =
             document
             |> LazyHTML.query(~s(#dashboard-version-2 [data-version-field="Summary"]))
             |> selected_text()

    assert ["draft_save"] =
             document
             |> LazyHTML.query("#dashboard-version-2")
             |> LazyHTML.attribute("data-version-lineage-kind")

    assert ["1"] =
             document
             |> LazyHTML.query("#dashboard-version-2")
             |> LazyHTML.attribute("data-version-lineage-source-version")

    assert "Draft saved from v1" =
             document
             |> LazyHTML.query(~s(#dashboard-version-2 [data-version-field="Origin"]))
             |> selected_text()
  end

  test "versions_panel renders open comparison review activity queue" do
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

    html =
      render_component(&VersionHistoryPanelComponents.versions_panel/1,
        dashboard_document: dashboard_document(),
        dashboard_summary: nil,
        dashboard_versions: [],
        dashboard_lifecycle_events: lifecycle_events,
        dashboard_comparison_review_queue: ComparisonReviewQueue.open_summary(lifecycle_events),
        dashboard_activity_filter: :open_comparison_reviews,
        dashboard_activity_event_id: nil,
        dashboard_review_placement_id: "placement-open",
        dashboard_publish_readiness: nil,
        dashboard_current_path: "/missions/mission-1/ops/dashboards/dashboard-1"
      )

    document = LazyHTML.from_fragment(html)

    assert ["open_comparison_reviews"] =
             document
             |> LazyHTML.query("#dashboard-activity-section")
             |> LazyHTML.attribute("data-dashboard-activity-mode")

    assert ["true"] =
             document
             |> LazyHTML.query("#dashboard-activity-section")
             |> LazyHTML.attribute("data-dashboard-comparison-review-work-queue")

    assert ["dashboard-lifecycle-event-open"] =
             document
             |> LazyHTML.query("#dashboard-activity-list > li")
             |> LazyHTML.attribute("data-dashboard-comparison-review-work-queue-item")

    assert "Review Queue" =
             document
             |> LazyHTML.query("[data-dashboard-activity-title]")
             |> selected_text()
  end

  test "versions_panel renders open comparison review activity from materialized queue" do
    queue_request =
      comparison_review_request_event(
        event_id: "dashboard-lifecycle-event-queued",
        placement_ids: ["placement-queued"],
        occurred_at: ~U[2026-06-24 12:00:00Z]
      )

    html =
      render_component(&VersionHistoryPanelComponents.versions_panel/1,
        dashboard_document: dashboard_document(),
        dashboard_summary: nil,
        dashboard_versions: [],
        dashboard_lifecycle_events: [],
        dashboard_comparison_review_queue: %{
          count: 1,
          count_text: "1",
          requests: [queue_request],
          request_ids: ["dashboard-lifecycle-event-queued"],
          request_ids_attr: "dashboard-lifecycle-event-queued",
          placement_ids: ["placement-queued"],
          placements_attr: "placement-queued"
        },
        dashboard_activity_filter: :open_comparison_reviews,
        dashboard_activity_event_id: nil,
        dashboard_review_placement_id: "placement-queued",
        dashboard_publish_readiness: nil,
        dashboard_current_path: "/missions/mission-1/ops/dashboards/dashboard-1"
      )

    document = LazyHTML.from_fragment(html)

    assert ["open_comparison_reviews"] =
             document
             |> LazyHTML.query("#dashboard-activity-section")
             |> LazyHTML.attribute("data-dashboard-activity-mode")

    assert ["dashboard-lifecycle-event-queued"] =
             document
             |> LazyHTML.query("#dashboard-activity-list > li")
             |> LazyHTML.attribute("data-dashboard-comparison-review-work-queue-item")

    assert ["dashboard-lifecycle-event-queued"] =
             document
             |> LazyHTML.query("#dashboard-activity-section")
             |> LazyHTML.attribute("data-dashboard-comparison-review-open-requests")
  end

  test "versions_panel correlates selected version activity with runtime invalidation impact" do
    published_event =
      lifecycle_event(
        "dashboard-lifecycle-event-published",
        :published,
        dashboard_version: 3,
        occurred_at: ~U[2026-06-24 12:00:00Z]
      )

    html =
      render_component(&VersionHistoryPanelComponents.versions_panel/1,
        dashboard_document: dashboard_document(),
        dashboard_summary: nil,
        dashboard_versions: [],
        dashboard_lifecycle_events: [published_event],
        dashboard_recent_invalidations: [
          %{
            id: "invalidation-published",
            lifecycle_action: "published",
            document_version: "3",
            source_version: "-",
            context_match: "true",
            refresh_allowed: "true",
            refresh_action: "refresh_plan",
            context_reason_label: "matched",
            refresh_allowed_reason_label: "refresh allowed"
          }
        ],
        dashboard_activity_filter: :version_changes,
        dashboard_activity_event_id: "dashboard-lifecycle-event-published",
        dashboard_publish_readiness: nil,
        dashboard_current_path: "/missions/mission-1/ops/dashboards/dashboard-1"
      )

    document = LazyHTML.from_fragment(html)

    assert ["refresh_allowed"] =
             document
             |> LazyHTML.query("#dashboard-activity-dashboard-lifecycle-event-published")
             |> LazyHTML.attribute("data-dashboard-activity-runtime-impact-state")

    assert ["invalidation-published"] =
             document
             |> LazyHTML.query("#dashboard-activity-dashboard-lifecycle-event-published")
             |> LazyHTML.attribute("data-dashboard-activity-runtime-impact-invalidation")

    assert "Runtime refresh allowed: refresh_plan" =
             document
             |> LazyHTML.query(
               ~s(#dashboard-activity-dashboard-lifecycle-event-published [data-activity-field="Runtime"])
             )
             |> selected_text()

    assert ["refresh_allowed"] =
             document
             |> LazyHTML.query("#dashboard-selected-activity-event")
             |> LazyHTML.attribute("data-dashboard-selected-activity-runtime-impact-state")

    assert "Runtime refresh allowed: refresh_plan" =
             document
             |> LazyHTML.query(~s([data-dashboard-selected-activity-field="Runtime"]))
             |> selected_text()
  end

  test "versions_panel offers recovery when selected activity is hidden by filter" do
    published_event = lifecycle_event("dashboard-lifecycle-event-published", :published)
    health_event = lifecycle_event("dashboard-lifecycle-event-health", :health_snapshot_captured)

    html =
      render_component(&VersionHistoryPanelComponents.versions_panel/1,
        dashboard_document: dashboard_document(),
        dashboard_summary: nil,
        dashboard_versions: [],
        dashboard_lifecycle_events: [published_event, health_event],
        dashboard_activity_filter: :health_snapshots,
        dashboard_activity_event_id: "dashboard-lifecycle-event-published",
        dashboard_publish_readiness: nil,
        dashboard_current_path:
          "/missions/mission-1/ops/dashboards/dashboard-1?scope_kind=mission&scope_id=mission-1"
      )

    document = LazyHTML.from_fragment(html)

    assert ["hidden"] =
             document
             |> LazyHTML.query("#dashboard-selected-activity-recovery")
             |> LazyHTML.attribute("data-dashboard-selected-activity-recovery")

    assert "This event exists but is hidden by the current activity filter." =
             document
             |> LazyHTML.query("#dashboard-selected-activity-recovery")
             |> selected_text()
             |> String.replace("Show all activity", "")
             |> String.trim()

    assert [href] =
             document
             |> LazyHTML.query("#dashboard-selected-activity-recovery-link")
             |> LazyHTML.attribute("href")

    query =
      href
      |> URI.parse()
      |> Map.fetch!(:query)
      |> URI.decode_query()

    assert query == %{
             "scope_kind" => "mission",
             "scope_id" => "mission-1",
             "panel" => "versions",
             "activity_event" => "dashboard-lifecycle-event-published"
           }
  end

  test "versions_panel offers recovery when selected activity is unavailable" do
    health_event = lifecycle_event("dashboard-lifecycle-event-health", :health_snapshot_captured)

    html =
      render_component(&VersionHistoryPanelComponents.versions_panel/1,
        dashboard_document: dashboard_document(),
        dashboard_summary: nil,
        dashboard_versions: [],
        dashboard_lifecycle_events: [health_event],
        dashboard_activity_filter: :publish_readiness,
        dashboard_activity_event_id: "dashboard-lifecycle-event-missing",
        dashboard_publish_readiness: nil,
        dashboard_current_path:
          "/missions/mission-1/ops/dashboards/dashboard-1?scope_kind=mission&scope_id=mission-1&activity_event=dashboard-lifecycle-event-missing"
      )

    document = LazyHTML.from_fragment(html)

    assert ["false"] =
             document
             |> LazyHTML.query("#dashboard-selected-activity-event")
             |> LazyHTML.attribute("data-dashboard-selected-activity-event-found")

    assert ["missing"] =
             document
             |> LazyHTML.query("#dashboard-selected-activity-recovery")
             |> LazyHTML.attribute("data-dashboard-selected-activity-recovery")

    assert "This event is no longer available in the dashboard activity log." =
             document
             |> LazyHTML.query("#dashboard-selected-activity-recovery")
             |> selected_text()
             |> String.replace("Clear selection", "")
             |> String.trim()

    assert [href] =
             document
             |> LazyHTML.query("#dashboard-selected-activity-recovery-link")
             |> LazyHTML.attribute("href")

    query =
      href
      |> URI.parse()
      |> Map.fetch!(:query)
      |> URI.decode_query()

    assert query == %{
             "scope_kind" => "mission",
             "scope_id" => "mission-1",
             "panel" => "versions"
           }
  end

  test "versions_panel renders published and draft runtime default context" do
    html =
      render_component(&VersionHistoryPanelComponents.versions_panel/1,
        dashboard_document: dashboard_document(),
        dashboard_summary: %DashboardSummary{
          dashboard_id: "dashboard-1",
          organization_id: "org-1",
          mission_id: "mission-1",
          name: "Dashboard",
          latest_version: 2,
          draft_version: 2,
          published_version: 1
        },
        dashboard_versions: [
          runtime_default_version(1, "flight", "canonical", "questdb-flight", "flight-binding"),
          runtime_default_version(
            2,
            "rehearsal",
            "as_recorded",
            "questdb-rehearsal",
            "rehearsal-binding"
          )
        ],
        dashboard_lifecycle_events: [],
        dashboard_publish_readiness: nil,
        dashboard_current_path: "/missions/mission-1/ops/dashboards/dashboard-1"
      )

    document = LazyHTML.from_fragment(html)

    assert ["true"] =
             document
             |> LazyHTML.query("#dashboard-runtime-defaults-summary")
             |> LazyHTML.attribute("data-dashboard-runtime-defaults-differ")

    assert ["flight"] =
             document
             |> LazyHTML.query("#dashboard-runtime-defaults-summary")
             |> LazyHTML.attribute("data-dashboard-runtime-defaults-published-realm")

    assert ["rehearsal-binding"] =
             document
             |> LazyHTML.query("#dashboard-runtime-defaults-summary")
             |> LazyHTML.attribute("data-dashboard-runtime-defaults-draft-source-binding")

    assert ["as_recorded"] =
             document
             |> LazyHTML.query("#dashboard-runtime-defaults-summary")
             |> LazyHTML.attribute("data-dashboard-runtime-defaults-draft-data-view")

    assert "rehearsal-binding" =
             document
             |> LazyHTML.query(
               ~s([data-dashboard-runtime-default-context="Draft"] [data-runtime-default-field="Source"])
             )
             |> selected_text()

    assert ["runtime_context_change"] =
             document
             |> LazyHTML.query("#dashboard-publish-impact")
             |> LazyHTML.attribute("data-dashboard-publish-impact-state")

    assert ["warning"] =
             document
             |> LazyHTML.query("#dashboard-publish-impact")
             |> LazyHTML.attribute("data-dashboard-publish-impact-severity")

    assert ["flight"] =
             document
             |> LazyHTML.query("#dashboard-publish-impact")
             |> LazyHTML.attribute("data-dashboard-publish-impact-from-realm")

    assert ["rehearsal-binding"] =
             document
             |> LazyHTML.query("#dashboard-publish-impact")
             |> LazyHTML.attribute("data-dashboard-publish-impact-to-source-binding")

    assert "Publishing will move operators from flight / flight-binding / canonical to rehearsal / rehearsal-binding / as_recorded." =
             document
             |> LazyHTML.query("[data-dashboard-publish-impact-message]")
             |> selected_text()
  end

  test "versions_panel renders publish validation action hints" do
    html =
      render_component(&VersionHistoryPanelComponents.versions_panel/1,
        dashboard_document: dashboard_document(),
        dashboard_summary: nil,
        dashboard_versions: [],
        dashboard_lifecycle_events: [],
        dashboard_publish_readiness:
          publish_readiness(
            %ValidationResult{
              valid?: false,
              errors: [
                %{
                  code: :unready_publish_source_request,
                  details: %{
                    source_warning_code: :missing_source_binding,
                    source_warning_message: "No active binding resolves for telemetry",
                    details: %{
                      logical_source: :telemetry,
                      realm: :rehearsal,
                      scope_kind: :spacecraft,
                      scope_id: "spacecraft-1"
                    }
                  }
                }
              ]
            },
            %{
              evaluated_at: "2026-06-27T12:00:00Z",
              draft_version: "2",
              summary_draft_version: "2",
              latest_version: "2",
              published_version: "1",
              state: "current",
              state_label: "current draft",
              reason: "draft_current",
              reason_label: "draft current",
              message: "Publish readiness was evaluated against the current draft version."
            }
          ),
        dashboard_current_path: "/missions/mission-1/ops/dashboards/dashboard-1"
      )

    document = LazyHTML.from_fragment(html)

    assert ["current"] =
             document
             |> LazyHTML.query("#dashboard-publish-validation-freshness")
             |> LazyHTML.attribute("data-publish-validation-freshness-state")

    assert ["2026-06-27T12:00:00Z"] =
             document
             |> LazyHTML.query("#dashboard-publish-validation-freshness")
             |> LazyHTML.attribute("data-publish-validation-evaluated-at")

    assert ["2"] =
             document
             |> LazyHTML.query("#dashboard-publish-validation-freshness")
             |> LazyHTML.attribute("data-publish-validation-draft-version")

    assert ["draft_current"] =
             document
             |> LazyHTML.query("#dashboard-publish-validation-freshness")
             |> LazyHTML.attribute("data-publish-validation-freshness-reason")

    assert "Publish readiness was evaluated against the current draft version." =
             document
             |> LazyHTML.query("[data-publish-validation-freshness-message]")
             |> selected_text()

    assert ["refresh_publish_readiness"] =
             document
             |> LazyHTML.query("#refresh-publish-readiness")
             |> LazyHTML.attribute("phx-click")

    assert ["still_blocked"] =
             document
             |> LazyHTML.query("#dashboard-publish-validation-result")
             |> LazyHTML.attribute("data-publish-validation-result-state")

    assert document
           |> LazyHTML.query("#dashboard-publish-validation-result")
           |> selected_text() =~ "Latest check still has publish blockers."

    assert ["data_sources"] =
             document
             |> LazyHTML.query(
               ~s([data-publish-validation-action="unready_publish_source_request"])
             )
             |> LazyHTML.attribute("data-publish-validation-action-target")

    assert "Create or select a source binding" =
             document
             |> LazyHTML.query(
               ~s([data-publish-validation-action="unready_publish_source_request"] .hud-label)
             )
             |> selected_text()

    assert document
           |> LazyHTML.query(
             ~s([data-publish-validation-action="unready_publish_source_request"])
           )
           |> selected_text() =~ "Open Data Sources"

    assert [href] =
             document
             |> LazyHTML.query(
               ~s([data-publish-validation-action-link="unready_publish_source_request"])
             )
             |> LazyHTML.attribute("href")

    assert String.starts_with?(href, "/missions/mission-1/ops/data-sources?")

    query =
      href
      |> URI.parse()
      |> Map.fetch!(:query)
      |> URI.decode_query()

    assert query == %{
             "logical_source" => "telemetry",
             "realm" => "rehearsal",
             "selected_publish_issue" =>
               "error:unready_publish_source_request:missing_source_binding",
             "scope_kind" => "spacecraft",
             "scope_id" => "spacecraft-1",
             "source_dashboard_id" => "dashboard-1",
             "source_empty_reason" => "missing_source_binding",
             "source_return_activity_filter" => "publish_readiness",
             "source_return_panel" => "versions"
           }
  end

  test "versions_panel summarizes unsupported observable scope blockers" do
    selected_issue_id =
      "error:unready_publish_source_request:placement-ground-state:unsupported_observable_scope:ground.station.connection_state"

    html =
      render_component(&VersionHistoryPanelComponents.versions_panel/1,
        dashboard_document: dashboard_document(),
        dashboard_summary: nil,
        dashboard_versions: [],
        dashboard_lifecycle_events: [],
        dashboard_publish_readiness:
          publish_readiness(
            %ValidationResult{
              valid?: false,
              errors: [
                %{
                  code: :unready_publish_source_request,
                  details: %{
                    source_warning_code: :unsupported_observable_scope,
                    source_warning_message:
                      "Widget observables do not support selected runtime scope",
                    placement_id: "placement-ground-state",
                    details: %{
                      logical_source: :operational_observables,
                      requested_scope_kind: :spacecraft,
                      requested_scope_ids: [],
                      unsupported_observables: ["ground.station.connection_state"],
                      supported_scopes: %{
                        "ground.station.connection_state" => [
                          :ground_station,
                          :source_endpoint,
                          :transport,
                          :link
                        ]
                      }
                    }
                  }
                }
              ]
            },
            %{
              evaluated_at: "2026-06-27T12:00:00Z",
              draft_version: "2",
              summary_draft_version: "2",
              latest_version: "2",
              published_version: "1",
              state: "current",
              state_label: "current draft",
              reason: "draft_current",
              reason_label: "draft current",
              message: "Publish readiness was evaluated against the current draft version."
            }
          ),
        dashboard_selected_publish_issue_id: selected_issue_id,
        dashboard_current_path: "/missions/mission-1/ops/dashboards/dashboard-1"
      )

    document = LazyHTML.from_fragment(html)

    assert ["selected"] =
             document
             |> LazyHTML.query("#dashboard-publish-validation")
             |> LazyHTML.attribute("data-publish-validation-selected-issue-state")

    assert [^selected_issue_id] =
             document
             |> LazyHTML.query("#dashboard-publish-validation")
             |> LazyHTML.attribute("data-publish-validation-selected-issue")

    assert ["true"] =
             document
             |> LazyHTML.query(~s([data-publish-validation-issue-id="#{selected_issue_id}"]))
             |> LazyHTML.attribute("data-publish-validation-issue-selected")

    assert [issue_href] =
             document
             |> LazyHTML.query(
               ~s([data-publish-validation-issue-focus-link="#{selected_issue_id}"])
             )
             |> LazyHTML.attribute("href")

    assert URI.decode_query(URI.parse(issue_href).query) == %{
             "panel" => "versions",
             "selected_publish_issue" => selected_issue_id
           }

    assert document
           |> LazyHTML.query(
             ~s([data-publish-validation-message="unready_publish_source_request"])
           )
           |> selected_text() =~
             "Dashboard context cannot support selected operational observables: ground.station.connection_state."

    assert ["dashboard_editor"] =
             document
             |> LazyHTML.query(
               ~s([data-publish-validation-action="unready_publish_source_request"])
             )
             |> LazyHTML.attribute("data-publish-validation-action-target")

    assert "Change widget context" =
             document
             |> LazyHTML.query(
               ~s([data-publish-validation-action="unready_publish_source_request"] .hud-label)
             )
             |> selected_text()

    assert [href] =
             document
             |> LazyHTML.query(
               ~s([data-publish-validation-action-link="unready_publish_source_request"])
             )
             |> LazyHTML.attribute("href")

    assert "Open Widget Editor" =
             document
             |> LazyHTML.query(
               ~s([data-publish-validation-action-link="unready_publish_source_request"])
             )
             |> selected_text()

    assert String.starts_with?(href, "/missions/mission-1/ops/dashboards/dashboard-1?")

    query =
      href
      |> URI.parse()
      |> Map.fetch!(:query)
      |> URI.decode_query()

    assert query == %{
             "panel" => "dashboard_editor",
             "selected_placement" => "placement-ground-state",
             "selected_publish_issue" => selected_issue_id,
             "source_empty_reason" => "unsupported_observable_scope",
             "unsupported_observables" => "ground.station.connection_state"
           }

    assert "placement-ground-state" =
             document
             |> LazyHTML.query(
               ~s([data-publish-validation-summary="unready_publish_source_request"] [data-publish-validation-summary-row="placement_id"])
             )
             |> selected_text()

    assert "spacecraft" =
             document
             |> LazyHTML.query(
               ~s([data-publish-validation-summary="unready_publish_source_request"] [data-publish-validation-summary-row="requested_scope"])
             )
             |> selected_text()

    assert "ground.station.connection_state" =
             document
             |> LazyHTML.query(
               ~s([data-publish-validation-summary="unready_publish_source_request"] [data-publish-validation-summary-row="unsupported_observables"])
             )
             |> selected_text()
  end

  test "versions_panel renders resolved publish validation result after a clean re-check" do
    html =
      render_component(&VersionHistoryPanelComponents.versions_panel/1,
        dashboard_document: dashboard_document(),
        dashboard_summary: nil,
        dashboard_versions: [],
        dashboard_lifecycle_events: [],
        dashboard_publish_readiness:
          publish_readiness(%ValidationResult{}, %{
            evaluated_at: "2026-06-27T12:05:00Z",
            draft_version: "2",
            summary_draft_version: "2",
            latest_version: "2",
            published_version: "1",
            state: "current",
            state_label: "current draft"
          }),
        dashboard_selected_publish_issue_id: "error:invalid_grid",
        dashboard_current_path: "/missions/mission-1/ops/dashboards/dashboard-1"
      )

    document = LazyHTML.from_fragment(html)

    assert ["clean"] =
             document
             |> LazyHTML.query("#dashboard-publish-validation")
             |> LazyHTML.attribute("data-publish-validation-status")

    assert ["resolved"] =
             document
             |> LazyHTML.query("#dashboard-publish-validation-result")
             |> LazyHTML.attribute("data-publish-validation-result-state")

    assert document
           |> LazyHTML.query("#dashboard-publish-validation-result")
           |> selected_text() =~ "Latest check found no publish blockers."

    assert ["resolved"] =
             document
             |> LazyHTML.query("#dashboard-publish-validation")
             |> LazyHTML.attribute("data-publish-validation-selected-issue-state")

    assert "Selected publish issue is no longer present in this check." =
             document
             |> LazyHTML.query("[data-publish-validation-selected-issue-resolved]")
             |> selected_text()
  end

  test "versions_panel renders stale publish validation state" do
    html =
      render_component(&VersionHistoryPanelComponents.versions_panel/1,
        dashboard_document: dashboard_document(),
        dashboard_summary: nil,
        dashboard_versions: [],
        dashboard_lifecycle_events: [],
        dashboard_publish_readiness:
          publish_readiness(%ValidationResult{}, %{
            evaluated_at: "2026-06-27T12:00:00Z",
            draft_version: "1",
            summary_draft_version: "2",
            latest_version: "2",
            published_version: "-",
            state: "stale",
            state_label: "stale draft",
            reason: "draft_version_changed",
            reason_label: "draft changed",
            message: "The dashboard draft changed after this publish readiness check."
          }),
        dashboard_current_path: "/missions/mission-1/ops/dashboards/dashboard-1"
      )

    document = LazyHTML.from_fragment(html)

    assert ["stale"] =
             document
             |> LazyHTML.query("#dashboard-publish-validation")
             |> LazyHTML.attribute("data-publish-validation-status")

    assert ["stale"] =
             document
             |> LazyHTML.query("#dashboard-publish-validation-freshness")
             |> LazyHTML.attribute("data-publish-validation-freshness-state")

    assert ["draft_version_changed"] =
             document
             |> LazyHTML.query("#dashboard-publish-validation-freshness")
             |> LazyHTML.attribute("data-publish-validation-freshness-reason")

    assert ["needs_recheck"] =
             document
             |> LazyHTML.query("#dashboard-publish-validation-result")
             |> LazyHTML.attribute("data-publish-validation-result-state")

    assert document
           |> LazyHTML.query("[data-publish-validation-freshness-message]")
           |> selected_text() =~ "dashboard draft changed"

    assert document
           |> LazyHTML.query("#dashboard-publish-validation")
           |> selected_text() =~ "Re-check readiness before publishing"
  end

  test "versions_panel renders source evidence stale publish validation reason" do
    html =
      render_component(&VersionHistoryPanelComponents.versions_panel/1,
        dashboard_document: dashboard_document(),
        dashboard_summary: nil,
        dashboard_versions: [],
        dashboard_lifecycle_events: [],
        dashboard_publish_readiness:
          publish_readiness(
            %ValidationResult{
              warnings: [%{code: :stale_data, details: %{data_source_id: "source-1"}}]
            },
            %{
              evaluated_at: "2026-06-27T12:10:00Z",
              draft_version: "2",
              summary_draft_version: "2",
              latest_version: "2",
              published_version: "1",
              state: "stale",
              state_label: "source evidence stale",
              reason: "source_watermark_stale",
              reason_label: "source stale",
              message:
                "Source watermark evidence is stale; re-check readiness after source data advances."
            }
          ),
        dashboard_current_path: "/missions/mission-1/ops/dashboards/dashboard-1"
      )

    document = LazyHTML.from_fragment(html)

    assert ["stale"] =
             document
             |> LazyHTML.query("#dashboard-publish-validation")
             |> LazyHTML.attribute("data-publish-validation-status")

    assert ["source_watermark_stale"] =
             document
             |> LazyHTML.query("#dashboard-publish-validation-freshness")
             |> LazyHTML.attribute("data-publish-validation-freshness-reason")

    assert document
           |> LazyHTML.query("[data-publish-validation-freshness-message]")
           |> selected_text() =~ "Source watermark evidence is stale"

    assert document
           |> LazyHTML.query("#dashboard-publish-validation-result")
           |> selected_text() =~ "Source watermark evidence is stale"
  end

  test "versions_panel links selected publish readiness activity to remediation target" do
    previous_event =
      lifecycle_event(
        "dashboard-lifecycle-event-readiness-previous",
        :publish_readiness_checked,
        occurred_at: ~U[2026-06-27 12:00:00Z],
        payload: %{
          "result" => "still_blocked",
          "issue_count" => 3
        }
      )

    readiness_event =
      lifecycle_event(
        "dashboard-lifecycle-event-readiness",
        :publish_readiness_checked,
        dashboard_version: 2,
        occurred_at: ~U[2026-06-27 12:05:00Z],
        payload: %{
          "result" => "still_blocked",
          "issue_count" => 1,
          "source_evidence_contexts" => [
            %{
              "warning_code" => "unsupported_source_capability",
              "source_request_id" => "request-telemetry-latest",
              "logical_source" => "telemetry",
              "source_binding_id" => "rehearsal-binding",
              "data_source_id" => "rehearsal-source",
              "replay_run_id" => "replay-run-7"
            }
          ],
          "remediation_targets" => [
            %{
              "label" => "Use a compatible source",
              "target" => "data_sources",
              "message" => "Open Data Sources and choose a compatible source.",
              "params" => %{
                "data_source_id" => "rehearsal-source",
                "source_binding_id" => "rehearsal-binding",
                "source_empty_reason" => "unsupported_source_capability"
              }
            }
          ]
        }
      )

    html =
      render_component(&VersionHistoryPanelComponents.versions_panel/1,
        dashboard_document: dashboard_document(),
        dashboard_summary: nil,
        dashboard_versions: [],
        dashboard_lifecycle_events: [previous_event, readiness_event],
        dashboard_source_action_events: [
          SourceHealthEvent.new(%{
            source_health_event_id: "source-health-event-1",
            organization_id: "org-1",
            mission_id: "mission-1",
            logical_source: "telemetry",
            data_source_id: "rehearsal-source",
            source_binding_id: "rehearsal-binding",
            source_health: :healthy,
            observed_at: ~U[2026-06-27 12:35:00Z],
            payload: %{
              "source_dashboard_id" => "dashboard-1",
              "source_return_activity_event" => "dashboard-lifecycle-event-readiness"
            }
          })
        ],
        dashboard_activity_filter: :publish_readiness,
        dashboard_activity_event_id: "dashboard-lifecycle-event-readiness",
        dashboard_readiness_return_intent: "source_return",
        dashboard_publish_readiness: nil,
        dashboard_current_path: "/missions/mission-1/ops/dashboards/dashboard-1"
      )

    document = LazyHTML.from_fragment(html)

    assert [
             "Use a compatible source",
             "Inspect telemetry: rehearsal-binding -> rehearsal-source (replay replay-run-7, request request-telemetry-latest)"
           ] =
             document
             |> LazyHTML.query("[data-dashboard-selected-activity-remediation]")
             |> LazyHTML.attribute("data-dashboard-selected-activity-remediation")

    assert ["data_sources", "data_sources"] =
             document
             |> LazyHTML.query("[data-dashboard-selected-activity-remediation]")
             |> LazyHTML.attribute("data-dashboard-selected-activity-remediation-target")

    assert document
           |> LazyHTML.query("[data-dashboard-selected-activity-remediation]")
           |> selected_text() =~ "Open Data Sources and choose a compatible source."

    assert ["improved"] =
             document
             |> LazyHTML.query("[data-dashboard-selected-activity-readiness-trend]")
             |> LazyHTML.attribute("data-dashboard-selected-activity-readiness-trend")

    assert ["dashboard-lifecycle-event-readiness-previous"] =
             document
             |> LazyHTML.query("[data-dashboard-selected-activity-readiness-trend]")
             |> LazyHTML.attribute("data-dashboard-selected-activity-readiness-previous")

    assert "Readiness improved: 3 issues -> 1 issue." =
             document
             |> LazyHTML.query(~s([data-dashboard-selected-activity-field="Readiness trend"]))
             |> selected_text()

    assert ["1"] =
             document
             |> LazyHTML.query("#dashboard-selected-activity-source-actions")
             |> LazyHTML.attribute("data-dashboard-selected-activity-source-actions")

    assert ["source_health"] =
             document
             |> LazyHTML.query("#dashboard-selected-activity-source-actions")
             |> LazyHTML.attribute("data-dashboard-selected-activity-source-action-latest-kind")

    assert ["2026-06-27 12:35:00 UTC"] =
             document
             |> LazyHTML.query("#dashboard-selected-activity-source-actions")
             |> LazyHTML.attribute("data-dashboard-selected-activity-source-action-latest-at")

    assert ["source_health"] =
             document
             |> LazyHTML.query("[data-dashboard-selected-activity-source-action]")
             |> LazyHTML.attribute("data-dashboard-selected-activity-source-action")

    assert ["telemetry / rehearsal-binding / rehearsal-source"] =
             document
             |> LazyHTML.query("[data-dashboard-selected-activity-source-action]")
             |> LazyHTML.attribute("data-dashboard-selected-activity-source-action-source")

    assert document
           |> LazyHTML.query("#dashboard-selected-activity-source-actions")
           |> selected_text() =~ "Source probed after this check"

    assert ["improved"] =
             document
             |> LazyHTML.query(
               ~s(#dashboard-activity-dashboard-lifecycle-event-readiness [data-dashboard-activity-readiness-trend])
             )
             |> LazyHTML.attribute("data-dashboard-activity-readiness-trend")

    assert ["dashboard-lifecycle-event-readiness-previous"] =
             document
             |> LazyHTML.query(
               ~s(#dashboard-activity-dashboard-lifecycle-event-readiness [data-dashboard-activity-readiness-trend])
             )
             |> LazyHTML.attribute("data-dashboard-activity-readiness-previous")

    assert ["2"] =
             document
             |> LazyHTML.query(
               ~s(#dashboard-activity-dashboard-lifecycle-event-readiness [data-dashboard-activity-remediation-count])
             )
             |> LazyHTML.attribute("data-dashboard-activity-remediation-count")

    assert [
             "Use a compatible source",
             "Inspect telemetry: rehearsal-binding -> rehearsal-source (replay replay-run-7, request request-telemetry-latest)"
           ] =
             document
             |> LazyHTML.query(
               ~s(#dashboard-activity-dashboard-lifecycle-event-readiness [data-dashboard-activity-remediation-action])
             )
             |> LazyHTML.attribute("data-dashboard-activity-remediation-action")

    assert ["data_sources", "data_sources"] =
             document
             |> LazyHTML.query(
               ~s(#dashboard-activity-dashboard-lifecycle-event-readiness [data-dashboard-activity-remediation-action])
             )
             |> LazyHTML.attribute("data-dashboard-activity-remediation-target")

    assert ["refresh_publish_readiness"] =
             document
             |> LazyHTML.query("#dashboard-selected-activity-refresh-readiness")
             |> LazyHTML.attribute("phx-click")

    assert ["source_return"] =
             document
             |> LazyHTML.query("#dashboard-selected-activity-readiness-return")
             |> LazyHTML.attribute("data-dashboard-selected-activity-readiness-return")

    assert ["dashboard-lifecycle-event-readiness"] =
             document
             |> LazyHTML.query("#dashboard-selected-activity-readiness-return")
             |> LazyHTML.attribute("data-dashboard-selected-activity-readiness-return-event")

    assert ["dashboard-lifecycle-event-readiness"] =
             document
             |> LazyHTML.query("[data-dashboard-selected-activity-readiness-return-refresh]")
             |> LazyHTML.attribute("data-dashboard-selected-activity-readiness-return-refresh")

    assert ["refresh_publish_readiness"] =
             document
             |> LazyHTML.query("[data-dashboard-selected-activity-readiness-return-refresh]")
             |> LazyHTML.attribute("phx-click")

    assert ["dashboard-lifecycle-event-readiness"] =
             document
             |> LazyHTML.query("#dashboard-selected-activity-refresh-readiness")
             |> LazyHTML.attribute("data-dashboard-selected-activity-refresh-readiness")

    assert ["improved"] =
             document
             |> LazyHTML.query("#dashboard-selected-activity-refresh-readiness")
             |> LazyHTML.attribute("data-dashboard-selected-activity-refresh-readiness-state")

    assert [explicit_href, source_evidence_href] =
             document
             |> LazyHTML.query("[data-dashboard-selected-activity-remediation-link]")
             |> LazyHTML.attribute("href")

    assert String.starts_with?(explicit_href, "/missions/mission-1/ops/data-sources?")
    assert String.starts_with?(source_evidence_href, "/missions/mission-1/ops/data-sources?")

    query =
      explicit_href
      |> URI.parse()
      |> Map.fetch!(:query)
      |> URI.decode_query()

    assert query == %{
             "data_source_id" => "rehearsal-source",
             "source_dashboard_id" => "dashboard-1",
             "source_binding_id" => "rehearsal-binding",
             "source_empty_reason" => "unsupported_source_capability",
             "source_return_activity_event" => "dashboard-lifecycle-event-readiness",
             "source_return_activity_filter" => "publish_readiness",
             "source_return_panel" => "versions"
           }

    source_evidence_query =
      source_evidence_href
      |> URI.parse()
      |> Map.fetch!(:query)
      |> URI.decode_query()

    assert source_evidence_query == %{
             "data_source_id" => "rehearsal-source",
             "logical_source" => "telemetry",
             "replay_run_id" => "replay-run-7",
             "selected_evidence_kind" => "source",
             "selected_source_evidence_mode" => "health",
             "source_dashboard_id" => "dashboard-1",
             "source_binding_id" => "rehearsal-binding",
             "source_empty_reason" => "unsupported_source_capability",
             "source_return_activity_event" => "dashboard-lifecycle-event-readiness",
             "source_return_activity_filter" => "publish_readiness",
             "source_return_panel" => "versions"
           }
  end

  test "versions_panel links connection-test publish readiness activity to source evidence" do
    readiness_event =
      lifecycle_event(
        "dashboard-lifecycle-event-readiness",
        :publish_readiness_checked,
        dashboard_version: 2,
        occurred_at: ~U[2026-06-27 12:05:00Z],
        payload: %{
          "result" => "still_blocked",
          "issue_count" => 1,
          "remediation_targets" => [
            %{
              "label" => "Fix source connection",
              "target" => "data_sources",
              "message" => "Open Data Sources and inspect the failed connection test.",
              "params" => %{
                "data_source_id" => "rehearsal-source",
                "source_binding_id" => "rehearsal-binding",
                "source_empty_reason" => "connection_test_failed",
                "selected_evidence_kind" => "source",
                "selected_source_evidence_mode" => "health",
                "selected_source_evidence_state" => "connection_test_failed",
                "connection_test_result" => "failed",
                "connection_test_kind" => "adapter_io",
                "connection_test_message" => "Adapter connection test failed."
              }
            }
          ]
        }
      )

    html =
      render_component(&VersionHistoryPanelComponents.versions_panel/1,
        dashboard_document: dashboard_document(),
        dashboard_summary: nil,
        dashboard_versions: [],
        dashboard_lifecycle_events: [readiness_event],
        dashboard_activity_filter: :publish_readiness,
        dashboard_activity_event_id: "dashboard-lifecycle-event-readiness",
        dashboard_readiness_return_intent: "source_return",
        dashboard_publish_readiness: nil,
        dashboard_current_path: "/missions/mission-1/ops/dashboards/dashboard-1"
      )

    document = LazyHTML.from_fragment(html)

    assert ["Fix source connection"] =
             document
             |> LazyHTML.query("[data-dashboard-selected-activity-remediation]")
             |> LazyHTML.attribute("data-dashboard-selected-activity-remediation")

    assert [href] =
             document
             |> LazyHTML.query("[data-dashboard-selected-activity-remediation-link]")
             |> LazyHTML.attribute("href")

    assert String.starts_with?(href, "/missions/mission-1/ops/data-sources?")

    assert URI.decode_query(URI.parse(href).query) == %{
             "connection_test_kind" => "adapter_io",
             "connection_test_message" => "Adapter connection test failed.",
             "connection_test_result" => "failed",
             "data_source_id" => "rehearsal-source",
             "selected_evidence_kind" => "source",
             "selected_source_evidence_mode" => "health",
             "selected_source_evidence_state" => "connection_test_failed",
             "source_binding_id" => "rehearsal-binding",
             "source_dashboard_id" => "dashboard-1",
             "source_empty_reason" => "connection_test_failed",
             "source_return_activity_event" => "dashboard-lifecycle-event-readiness",
             "source_return_activity_filter" => "publish_readiness",
             "source_return_panel" => "versions"
           }
  end

  test "versions_panel links selected publish readiness activity to dashboard editor focus" do
    selected_issue_id =
      "error:unready_publish_source_request:placement-ground-state:unsupported_observable_scope:ground.station.connection_state"

    readiness_event =
      lifecycle_event(
        "dashboard-lifecycle-event-readiness",
        :publish_readiness_checked,
        dashboard_version: 2,
        occurred_at: ~U[2026-06-27 12:05:00Z],
        payload: %{
          "result" => "still_blocked",
          "issue_count" => 1,
          "remediation_targets" => [
            %{
              "issue_id" => selected_issue_id,
              "label" => "Change widget context",
              "target" => "dashboard_editor",
              "message" =>
                "Open the dashboard editor and choose observables that support this context.",
              "params" => %{
                "placement_id" => "placement-ground-state",
                "selected_publish_issue" => selected_issue_id,
                "source_empty_reason" => "unsupported_observable_scope",
                "unsupported_observables" => "ground.station.connection_state"
              }
            }
          ]
        }
      )

    html =
      render_component(&VersionHistoryPanelComponents.versions_panel/1,
        dashboard_document: dashboard_document(),
        dashboard_summary: nil,
        dashboard_versions: [],
        dashboard_lifecycle_events: [readiness_event],
        dashboard_activity_filter: :publish_readiness,
        dashboard_activity_event_id: "dashboard-lifecycle-event-readiness",
        dashboard_publish_readiness: nil,
        dashboard_current_path: "/missions/mission-1/ops/dashboards/dashboard-1"
      )

    document = LazyHTML.from_fragment(html)

    assert [selected_issue_id] =
             document
             |> LazyHTML.query("[data-dashboard-selected-activity-remediation]")
             |> LazyHTML.attribute("data-dashboard-selected-activity-remediation-issue")

    assert ["dashboard_editor"] =
             document
             |> LazyHTML.query("[data-dashboard-selected-activity-remediation]")
             |> LazyHTML.attribute("data-dashboard-selected-activity-remediation-target")

    assert "Open Widget Editor" =
             document
             |> LazyHTML.query("[data-dashboard-selected-activity-remediation-link]")
             |> selected_text()

    assert [href] =
             document
             |> LazyHTML.query("[data-dashboard-selected-activity-remediation-link]")
             |> LazyHTML.attribute("href")

    assert String.starts_with?(href, "/missions/mission-1/ops/dashboards/dashboard-1?")

    assert URI.decode_query(URI.parse(href).query) == %{
             "panel" => "dashboard_editor",
             "selected_placement" => "placement-ground-state",
             "selected_publish_issue" => selected_issue_id,
             "source_empty_reason" => "unsupported_observable_scope",
             "unsupported_observables" => "ground.station.connection_state"
           }
  end

  defp dashboard_document do
    %Document{
      dashboard_id: "dashboard-1",
      organization_id: "org-1",
      mission_id: "mission-1",
      name: "Dashboard"
    }
  end

  defp version(version, snapshot_kind, change_summary) do
    %Version{
      dashboard_version_id: "version-#{version}",
      organization_id: "org-1",
      mission_id: "mission-1",
      dashboard_id: "dashboard-1",
      version: version,
      document: dashboard_document(),
      snapshot_kind: snapshot_kind,
      parent_version: previous_version(version),
      based_on_version: previous_version(version),
      change_summary: change_summary,
      created_by: "operator",
      inserted_at: ~U[2026-06-24 12:00:00Z]
    }
  end

  defp runtime_default_version(version, realm, data_view, data_source_id, source_binding_id) do
    %Version{
      dashboard_version_id: "version-#{version}",
      organization_id: "org-1",
      mission_id: "mission-1",
      dashboard_id: "dashboard-1",
      version: version,
      document: %Document{
        dashboard_id: "dashboard-1",
        organization_id: "org-1",
        mission_id: "mission-1",
        name: "Dashboard",
        defaults: %{
          "data" => %{
            "realm" => realm,
            "view" => data_view,
            "source_contexts" => %{
              "telemetry" => %{
                "data_source_id" => data_source_id,
                "source_binding_id" => source_binding_id
              }
            }
          }
        },
        metadata: %{version: version}
      },
      snapshot_kind: :draft_save,
      inserted_at: ~U[2026-06-24 12:00:00Z]
    }
  end

  defp previous_version(version) when is_integer(version) and version > 1, do: version - 1
  defp previous_version(_version), do: nil

  defp publish_readiness(validation, freshness) do
    PublishReadinessModel.build(validation, freshness)
  end

  defp selected_text(lazy_html) do
    lazy_html
    |> LazyHTML.text()
    |> String.trim()
  end
end
