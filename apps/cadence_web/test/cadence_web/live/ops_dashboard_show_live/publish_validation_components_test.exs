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

    document = LazyHTML.from_fragment(html)

    assert ["current"] =
             document
             |> LazyHTML.query("#dashboard-publish-validation-freshness")
             |> LazyHTML.attribute("data-publish-validation-freshness-state")

    assert ["refresh_publish_readiness"] =
             document
             |> LazyHTML.query("#refresh-publish-readiness")
             |> LazyHTML.attribute("phx-click")

    assert ["data_sources"] =
             document
             |> LazyHTML.query(
               ~s([data-publish-validation-action="unready_publish_source_request"])
             )
             |> LazyHTML.attribute("data-publish-validation-action-target")

    assert [href] =
             document
             |> LazyHTML.query(
               ~s([data-publish-validation-action-link="unready_publish_source_request"])
             )
             |> LazyHTML.attribute("href")

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

    document = LazyHTML.from_fragment(html)

    assert ["dashboard_editor"] =
             document
             |> LazyHTML.query(
               ~s([data-publish-validation-action="unready_publish_source_request"])
             )
             |> LazyHTML.attribute("data-publish-validation-action-target")

    assert [href] =
             document
             |> LazyHTML.query(
               ~s([data-publish-validation-action-link="unready_publish_source_request"])
             )
             |> LazyHTML.attribute("href")

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

    document = LazyHTML.from_fragment(html)

    assert ["clean"] =
             document
             |> LazyHTML.query("#dashboard-publish-validation")
             |> LazyHTML.attribute("data-publish-validation-status")

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
