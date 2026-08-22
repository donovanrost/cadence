defmodule CadenceWeb.OpsDashboardShowLive.VersionHistoryPublishReadinessComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Cadence.Dashboards.{Document, ValidationResult}
  alias CadenceWeb.OpsDashboardShowLive.{PublishReadinessModel, VersionHistoryPanelComponents}

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

  defp dashboard_document do
    %Document{
      dashboard_id: "dashboard-1",
      organization_id: "org-1",
      mission_id: "mission-1",
      name: "Dashboard"
    }
  end

  defp publish_readiness(validation, freshness) do
    PublishReadinessModel.build(validation, freshness)
  end

  defp selected_text(lazy_html) do
    lazy_html
    |> LazyHTML.text()
    |> String.trim()
  end
end
