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

    presentation = publish_validation_presentation(html)
    freshness = presentation["freshness"]

    assert freshness["attrs"]["data-publish-validation-freshness-state"] == "current"

    assert freshness["attrs"]["data-publish-validation-evaluated-at"] ==
             "2026-06-27T12:00:00Z"

    assert freshness["attrs"]["data-publish-validation-draft-version"] == "2"

    assert freshness["attrs"]["data-publish-validation-freshness-reason"] ==
             "draft_current"

    assert freshness["message"]["text"] ==
             "Publish readiness was evaluated against the current draft version."

    assert presentation["header"]["refresh"]["attrs"]["phx-click"] ==
             "refresh_publish_readiness"

    assert presentation["result"]["attrs"]["data-publish-validation-result-state"] ==
             "still_blocked"

    assert presentation["result"]["message"]["text"] =~
             "Latest check still has publish blockers."

    [issue] = presentation["issues"]["rows"]
    action = issue["action"]

    assert action["attrs"]["data-publish-validation-action-target"] == "data_sources"

    assert action["label"]["text"] == "Create or select a source binding"

    assert action["link"]["text"] =~ "Open Data Sources"

    href = action["link"]["href"]
    assert is_binary(href)

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

    assert action["link"]["attrs"] == %{
             "data-publish-validation-action-link" => "unready_publish_source_request",
             "data-publish-validation-action-href" => href,
             "data-phx-link" => "redirect",
             "data-phx-link-state" => "push"
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

    presentation = publish_validation_presentation(html)

    assert presentation["root"]["attrs"][
             "data-publish-validation-selected-issue-state"
           ] == "selected"

    assert presentation["root"]["attrs"]["data-publish-validation-selected-issue"] ==
             selected_issue_id

    [issue] = presentation["issues"]["rows"]

    assert issue["attrs"]["data-publish-validation-issue-selected"] == "true"

    issue_href = issue["header"]["focus"]["href"]
    assert is_binary(issue_href)

    assert URI.decode_query(URI.parse(issue_href).query) == %{
             "panel" => "versions",
             "selected_publish_issue" => selected_issue_id
           }

    assert issue["message"]["text"] =~
             "Dashboard context cannot support selected operational observables: ground.station.connection_state."

    action = issue["action"]

    assert action["attrs"]["data-publish-validation-action-target"] == "dashboard_editor"

    assert action["label"]["text"] == "Change widget context"

    href = action["link"]["href"]
    assert is_binary(href)

    assert action["link"]["text"] == "Open Widget Editor"

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

    summary_rows = issue["summary"]["rows"]
    [placement, requested_scope, unsupported_observables] = summary_rows

    assert placement["value"]["text"] == "placement-ground-state"

    assert requested_scope["value"]["text"] == "spacecraft"

    assert unsupported_observables["value"]["text"] ==
             "ground.station.connection_state"

    assert Enum.map(summary_rows, & &1["value"]["attrs"]) == [
             %{"data-publish-validation-summary-row" => "placement_id"},
             %{"data-publish-validation-summary-row" => "requested_scope"},
             %{"data-publish-validation-summary-row" => "unsupported_observables"}
           ]

    assert issue["header"]["focus"]["attrs"] == %{
             "data-publish-validation-issue-focus-link" => selected_issue_id,
             "data-phx-link" => "patch",
             "data-phx-link-state" => "push"
           }

    assert action["link"]["attrs"] == %{
             "data-publish-validation-action-link" => "unready_publish_source_request",
             "data-publish-validation-action-href" => href,
             "data-phx-link" => "patch",
             "data-phx-link-state" => "push"
           }
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

    presentation = publish_validation_presentation(html)

    assert presentation["root"]["attrs"]["data-publish-validation-status"] == "clean"

    assert presentation["result"]["attrs"]["data-publish-validation-result-state"] ==
             "resolved"

    assert presentation["result"]["message"]["text"] =~
             "Latest check found no publish blockers."

    assert presentation["root"]["attrs"][
             "data-publish-validation-selected-issue-state"
           ] == "resolved"

    assert presentation["resolved_notice"]["text"] ==
             "Selected publish issue is no longer present in this check."

    assert presentation["resolved_notice"]["visible"] == true
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

  defp publish_validation_presentation(html) do
    vue = LiveVue.Test.get_vue(html, id: "dashboard-publish-validation-component")
    assert vue.component == "PublishValidation"
    assert vue.id == "dashboard-publish-validation-component"
    assert vue.ssr == false
    assert vue.class == "contents"
    assert vue.handlers == %{}
    assert vue.slots == %{}
    assert vue.props == Jason.decode!(Jason.encode!(vue.props))
    vue.props["presentation"]
  end
end
