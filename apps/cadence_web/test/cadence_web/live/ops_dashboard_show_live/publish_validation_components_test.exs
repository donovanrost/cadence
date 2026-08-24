defmodule CadenceWeb.OpsDashboardShowLive.PublishValidationComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Cadence.Dashboards.{Document, ValidationResult}
  alias CadenceWeb.OpsDashboardShowLive.{PublishReadinessModel, PublishValidationComponents}

  test "publish_validation renders source remediation action links" do
    html =
      render_component(&PublishValidationComponents.publish_validation/1,
        dashboard_document: dashboard_document(),
        publish_readiness:
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
        selected_publish_issue_id: nil,
        dashboard_current_path: "/missions/mission-1/ops/dashboards/dashboard-1"
      )

    vue = publish_validation_vue(html)
    presentation = vue.props["presentation"]

    assert presentation == Jason.decode!(Jason.encode!(presentation))

    assert presentation["root"] == %{
             "id" => "dashboard-publish-validation",
             "class" => "space-y-2 border border-base-300/70 bg-base-100/40 p-2",
             "attrs" => %{
               "data-publish-validation-status" => "blocked",
               "data-publish-validation-selected-issue" => "",
               "data-publish-validation-selected-issue-state" => "none"
             }
           }

    assert Map.keys(presentation) |> Enum.sort() ==
             ~w(freshness header issues message resolved_notice result root)

    assert presentation["header"]["class"] == "flex items-center justify-between gap-3"

    assert presentation["header"]["heading"] == %{
             "class" => "hud-label",
             "text" => "Publish Check"
           }

    assert presentation["header"]["controls"] == %{"class" => "flex items-center gap-2"}

    assert presentation["header"]["badge"] == %{
             "class" => "badge badge-xs badge-error",
             "text" => "blocked"
           }

    assert presentation["message"] == %{
             "class" => "text-xs text-base-content/70",
             "text" => "Resolve validation errors before publishing this draft."
           }

    freshness = presentation["freshness"]

    assert freshness["attrs"]["data-publish-validation-freshness-state"] == "current"

    assert presentation["header"]["refresh"] == %{
             "id" => "refresh-publish-readiness",
             "type" => "button",
             "class" =>
               "inline-flex items-center gap-1 text-xs font-semibold text-primary hover:text-primary-focus",
             "text" => "Re-check",
             "icon" => %{"name" => "hero-arrow-path", "class" => "h-3 w-3"},
             "attrs" => %{"phx-click" => "refresh_publish_readiness"}
           }

    assert freshness == %{
             "id" => "dashboard-publish-validation-freshness",
             "class" =>
               "grid grid-cols-2 gap-2 border border-base-300/70 bg-base-100/40 px-2 py-1.5 text-xs",
             "attrs" => %{
               "data-publish-validation-freshness-state" => "current",
               "data-publish-validation-freshness-reason" => "draft_current",
               "data-publish-validation-evaluated-at" => "2026-06-27T12:00:00Z",
               "data-publish-validation-draft-version" => "2",
               "data-publish-validation-summary-draft-version" => "2",
               "data-publish-validation-latest-version" => "2",
               "data-publish-validation-published-version" => "1"
             },
             "evaluated" => %{
               "label" => %{"class" => "hud-label", "text" => "evaluated"},
               "value" => %{
                 "class" => "font-mono text-base-content/70",
                 "text" => "2026-06-27T12:00:00Z"
               }
             },
             "draft_state" => %{
               "label" => %{"class" => "hud-label", "text" => "draft state"},
               "value" => %{
                 "class" => "font-mono text-base-content/70",
                 "text" => "current draft"
               }
             },
             "reason" => %{
               "visible" => true,
               "label" => %{"class" => "hud-label", "text" => "reason"},
               "value" => %{
                 "class" => "font-mono text-base-content/70",
                 "text" => "draft current"
               }
             },
             "message" => %{
               "visible" => true,
               "class" => "col-span-2 text-base-content/70",
               "text" => "Publish readiness was evaluated against the current draft version.",
               "attrs" => %{"data-publish-validation-freshness-message" => ""}
             }
           }

    [issue] = presentation["issues"]["rows"]

    assert presentation["issues"]["visible"] == true
    assert presentation["issues"]["class"] == "space-y-1"

    assert Enum.map(presentation["issues"]["rows"], & &1["key"]) == [
             "publish-validation-issue-0"
           ]

    assert issue["id"] == "dashboard-publish-validation-issue-#{issue_id()}"
    assert issue["class"] == "rounded border px-2 py-1 text-xs border-base-300/70"
    assert issue["attrs"]["data-publish-validation-issue-id"] == issue_id()

    assert issue["header"]["severity"] == %{
             "class" => "badge badge-xs badge-error",
             "text" => "error"
           }

    assert issue["header"]["code"] == %{
             "class" => "font-mono text-base-content/80",
             "text" => "unready_publish_source_request"
           }

    assert issue["message"] == %{
             "class" => "mt-1 text-base-content/80",
             "text" => "Dashboard source binding cannot be resolved for the publish context.",
             "attrs" => %{
               "data-publish-validation-message" => "unready_publish_source_request"
             }
           }

    assert issue["summary"] == nil

    action = issue["action"]

    assert action["attrs"]["data-publish-validation-action-target"] == "data_sources"

    source_link = action["link"]
    href = source_link["href"]
    assert is_binary(href)

    assert action["class"] == "mt-2 border-l-2 border-info/70 pl-2"

    assert action["label"] == %{
             "class" => "hud-label",
             "text" => "Create or select a source binding"
           }

    assert action["message"] == %{
             "class" => "mt-0.5 text-base-content/70",
             "text" =>
               "Open Data Sources and bind this dashboard's logical source to an active data source for the publish context."
           }

    assert Map.take(source_link, ["class", "text", "icon"]) == %{
             "class" =>
               "mt-1 inline-flex items-center gap-1 text-xs font-semibold text-primary hover:text-primary-focus",
             "text" => "Open Data Sources",
             "icon" => %{
               "name" => "hero-arrow-top-right-on-square",
               "class" => "h-3 w-3"
             }
           }

    assert source_link["attrs"] == %{
             "data-publish-validation-action-link" => "unready_publish_source_request",
             "data-publish-validation-action-href" => href,
             "data-phx-link" => "redirect",
             "data-phx-link-state" => "push"
           }

    assert source_link["navigation_kind"] == "navigate"

    assert issue["header"]["focus"]["attrs"] == %{
             "data-publish-validation-issue-focus-link" => issue_id(),
             "data-phx-link" => "patch",
             "data-phx-link-state" => "push"
           }

    assert Enum.map(issue["details"]["rows"], fn row ->
             {row["label"]["text"], row["value"]["text"]}
           end) == [
             {"Source message", "No active binding resolves for telemetry"},
             {"Source warning", "missing_source_binding"},
             {"logical_source", "telemetry"},
             {"realm", "rehearsal"},
             {"scope_id", "spacecraft-1"},
             {"scope_kind", "spacecraft"}
           ]

    assert Enum.map(issue["details"]["rows"], & &1["value"]["attrs"]) == [
             %{"data-publish-validation-detail" => "Source message"},
             %{"data-publish-validation-detail" => "Source warning"},
             %{"data-publish-validation-detail" => "logical_source"},
             %{"data-publish-validation-detail" => "realm"},
             %{"data-publish-validation-detail" => "scope_id"},
             %{"data-publish-validation-detail" => "scope_kind"}
           ]

    assert String.starts_with?(href, "/missions/mission-1/ops/data-sources?")

    assert URI.decode_query(URI.parse(href).query) == %{
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

  test "publish_validation renders operational capability actions into editor focus links" do
    html =
      render_component(&PublishValidationComponents.publish_validation/1,
        dashboard_document: dashboard_document(),
        publish_readiness:
          publish_readiness(
            %ValidationResult{
              valid?: false,
              errors: [
                %{
                  code: :unready_publish_source_request,
                  details: %{
                    source_warning_code: :unsupported_source_capability,
                    placement_id: "placement-link-history",
                    details: %{
                      logical_source: :operational_observables,
                      requested_observables: ["link.snr_db"],
                      unsupported_observables: ["link.snr_db"],
                      requested_sampling: :raw_series,
                      requested_products: [:link_rf],
                      requested_source_products: [:link_rf_metric_history],
                      requested_product_families: [:link_rf],
                      supported_products: [:operational_metric_history]
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
              state_label: "current draft"
            }
          ),
        selected_publish_issue_id:
          "error:unready_publish_source_request:placement-link-history:unsupported_source_capability:link.snr_db",
        dashboard_current_path: "/missions/mission-1/ops/dashboards/dashboard-1"
      )

    vue = publish_validation_vue(html)
    presentation = vue.props["presentation"]
    assert presentation == Jason.decode!(Jason.encode!(presentation))

    assert presentation["root"]["attrs"] == %{
             "data-publish-validation-status" => "blocked",
             "data-publish-validation-selected-issue" => selected_capability_issue_id(),
             "data-publish-validation-selected-issue-state" => "selected"
           }

    [issue] = presentation["issues"]["rows"]

    assert issue["attrs"] == %{
             "data-publish-validation-issue-id" => selected_capability_issue_id(),
             "data-publish-validation-issue-selected" => "true",
             "data-publish-validation-severity" => "error",
             "data-publish-validation-code" => "unready_publish_source_request"
           }

    assert issue["class"] ==
             "rounded border px-2 py-1 text-xs border-warning/70 bg-warning/10"

    assert issue["header"]["focus"]["navigation_kind"] == "patch"

    assert issue["header"]["focus"]["attrs"] == %{
             "data-publish-validation-issue-focus-link" => selected_capability_issue_id(),
             "data-phx-link" => "patch",
             "data-phx-link-state" => "push"
           }

    assert URI.decode_query(URI.parse(issue["header"]["focus"]["href"]).query) == %{
             "panel" => "versions",
             "selected_publish_issue" => selected_capability_issue_id()
           }

    action = issue["action"]

    assert action["attrs"]["data-publish-validation-action-target"] == "dashboard_editor"

    editor_link = action["link"]
    href = editor_link["href"]
    assert is_binary(href)

    assert action["label"] == %{
             "class" => "hud-label",
             "text" => "Review operational history binding"
           }

    assert Map.take(editor_link, ["class", "text", "icon"]) == %{
             "class" =>
               "mt-1 inline-flex items-center gap-1 text-xs font-semibold text-primary hover:text-primary-focus",
             "text" => "Open Widget Editor",
             "icon" => %{"name" => "hero-pencil-square", "class" => "h-3 w-3"}
           }

    assert editor_link["attrs"] == %{
             "data-publish-validation-action-link" => "unready_publish_source_request",
             "data-publish-validation-action-href" => href,
             "data-phx-link" => "patch",
             "data-phx-link-state" => "push"
           }

    assert editor_link["navigation_kind"] == "patch"

    assert String.starts_with?(href, "/missions/mission-1/ops/dashboards/dashboard-1?")

    assert URI.decode_query(URI.parse(href).query) == %{
             "panel" => "dashboard_editor",
             "requested_observables" => "link.snr_db",
             "requested_product_families" => "link_rf",
             "requested_products" => "link_rf",
             "requested_sampling" => "raw_series",
             "requested_source_products" => "link_rf_metric_history",
             "selected_placement" => "placement-link-history",
             "selected_publish_issue" =>
               "error:unready_publish_source_request:placement-link-history:unsupported_source_capability:link.snr_db",
             "source_empty_reason" => "unsupported_source_capability",
             "supported_products" => "operational_metric_history",
             "unsupported_observables" => "link.snr_db"
           }
  end

  test "publish_validation marks selected issue resolved after a clean check" do
    html =
      render_component(&PublishValidationComponents.publish_validation/1,
        dashboard_document: dashboard_document(),
        publish_readiness:
          publish_readiness(%ValidationResult{}, %{
            evaluated_at: "2026-06-27T12:05:00Z",
            draft_version: "2",
            summary_draft_version: "2",
            latest_version: "2",
            published_version: "1",
            state: "current",
            state_label: "current draft"
          }),
        selected_publish_issue_id: "error:invalid_grid",
        dashboard_current_path: "/missions/mission-1/ops/dashboards/dashboard-1"
      )

    vue = publish_validation_vue(html)
    presentation = vue.props["presentation"]

    assert presentation["root"]["attrs"]["data-publish-validation-status"] == "clean"

    assert presentation["root"]["attrs"][
             "data-publish-validation-selected-issue-state"
           ] == "resolved"

    assert presentation["resolved_notice"]["text"] ==
             "Selected publish issue is no longer present in this check."

    assert presentation["resolved_notice"] == %{
             "visible" => true,
             "class" =>
               "rounded border border-success/40 bg-success/10 px-2 py-1 text-xs text-success",
             "text" => "Selected publish issue is no longer present in this check.",
             "attrs" => %{"data-publish-validation-selected-issue-resolved" => ""}
           }

    assert presentation["issues"] == %{
             "visible" => false,
             "class" => "space-y-1",
             "rows" => []
           }

    assert presentation["result"] == %{
             "id" => "dashboard-publish-validation-result",
             "class" => "border border-base-300/70 bg-base-100/40 px-2 py-1.5 text-xs",
             "attrs" => %{
               "data-publish-validation-result-state" => "resolved",
               "data-publish-validation-result-label" => "resolved"
             },
             "label" => %{"class" => "hud-label", "text" => "resolved"},
             "message" => %{
               "class" => "text-base-content/70",
               "text" => "Latest check found no publish blockers."
             }
           }
  end

  test "publish_validation preserves optional freshness truthiness and attribute values" do
    html =
      render_component(&PublishValidationComponents.publish_validation/1,
        dashboard_document: dashboard_document(),
        publish_readiness:
          publish_readiness(%ValidationResult{}, %{
            evaluated_at: "2026-06-27T12:05:00Z",
            draft_version: "2",
            summary_draft_version: "2",
            latest_version: "2",
            published_version: false,
            state: "current",
            state_label: "current draft",
            reason: false,
            reason_label: "",
            message: false
          }),
        selected_publish_issue_id: "",
        dashboard_current_path: "/missions/mission-1/ops/dashboards/dashboard-1"
      )

    presentation = html |> publish_validation_vue() |> then(& &1.props["presentation"])
    freshness = presentation["freshness"]

    assert presentation == Jason.decode!(Jason.encode!(presentation))
    assert presentation["root"]["attrs"]["data-publish-validation-selected-issue"] == ""
    assert presentation["root"]["attrs"]["data-publish-validation-selected-issue-state"] == "none"
    assert freshness["attrs"]["data-publish-validation-freshness-reason"] == ""
    assert freshness["attrs"]["data-publish-validation-published-version"] == nil
    assert freshness["reason"]["visible"] == true
    assert freshness["reason"]["value"]["text"] == ""
    assert freshness["message"]["visible"] == false
    assert freshness["message"]["text"] == "false"

    without_freshness =
      render_component(&PublishValidationComponents.publish_validation/1,
        dashboard_document: dashboard_document(),
        publish_readiness: publish_readiness(%ValidationResult{}, nil),
        selected_publish_issue_id: nil,
        dashboard_current_path: "/missions/mission-1/ops/dashboards/dashboard-1"
      )
      |> publish_validation_vue()
      |> then(& &1.props["presentation"])

    assert without_freshness["freshness"] == nil
  end

  test "publish_validation renders no island for nil readiness" do
    html =
      render_component(&PublishValidationComponents.publish_validation/1,
        dashboard_document: dashboard_document(),
        publish_readiness: nil,
        selected_publish_issue_id: nil,
        dashboard_current_path: "/missions/mission-1/ops/dashboards/dashboard-1"
      )

    assert [] =
             html
             |> LazyHTML.from_fragment()
             |> LazyHTML.query("#dashboard-publish-validation-component")
             |> LazyHTML.attribute("id")
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

  defp publish_validation_vue(html) do
    vue = LiveVue.Test.get_vue(html, id: "dashboard-publish-validation-component")
    assert vue.component == "PublishValidation"
    assert vue.id == "dashboard-publish-validation-component"
    assert vue.ssr == false
    assert vue.class == "contents"
    assert vue.handlers == %{}
    assert vue.slots == %{}
    vue
  end

  defp issue_id, do: "error:unready_publish_source_request:missing_source_binding"

  defp selected_capability_issue_id do
    "error:unready_publish_source_request:placement-link-history:unsupported_source_capability:link.snr_db"
  end
end
