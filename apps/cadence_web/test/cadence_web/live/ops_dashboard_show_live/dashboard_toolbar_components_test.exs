defmodule CadenceWeb.OpsDashboardShowLive.DashboardToolbarComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Cadence.Dashboards.ComparisonReviewQueue

  alias Cadence.DataSources.DataBinding
  alias CadenceWeb.OpsDashboardShowLive.DashboardToolbarComponents

  test "dashboard_toolbar exposes mission scope alongside spacecraft context search" do
    html =
      render_component(
        &DashboardToolbarComponents.dashboard_toolbar/1,
        toolbar_assigns(
          context_scope_kind: "mission",
          context_scope_id: "mission-1",
          query: "lunar"
        )
      )

    document = LazyHTML.from_fragment(html)

    assert ["mission"] =
             document
             |> LazyHTML.query(~s(button[phx-value-scope-kind="mission"]))
             |> LazyHTML.attribute("phx-value-scope-kind")

    assert ["mission-1"] =
             document
             |> LazyHTML.query(~s(button[phx-value-scope-kind="mission"]))
             |> LazyHTML.attribute("phx-value-scope-id")

    assert html =~ "Lunar Demo"
    assert html =~ "Find mission, spacecraft, contact, source, transport, ground, or link"

    assert ["#"] =
             document
             |> LazyHTML.query("#dashboard-versions-button")
             |> LazyHTML.attribute("href")
  end

  test "dashboard_toolbar exposes scheduled and realized contacts as runtime contexts" do
    html =
      render_component(
        &DashboardToolbarComponents.dashboard_toolbar/1,
        toolbar_assigns(
          spacecraft: [],
          scheduled_contacts: [
            %{
              scheduled_contact_id: "contact-scheduled-1",
              source_endpoint_refs: ["gs-alpha"]
            }
          ],
          realized_contacts: [
            %{
              realized_contact_id: "contact-realized-1",
              scheduled_contact_id: "contact-scheduled-1",
              source_endpoint_refs: ["gs-alpha"]
            }
          ],
          context_scope_kind: "contact",
          context_scope_id: "contact-realized-1",
          query: "gs-alpha"
        )
      )

    document = LazyHTML.from_fragment(html)

    assert html =~ "realized / contact-realized-1 / gs-alpha"

    assert ["contact"] =
             document
             |> LazyHTML.query(
               ~s(button[data-dashboard-context-contact-id="contact-scheduled-1"])
             )
             |> LazyHTML.attribute("phx-value-scope-kind")

    assert ["contact-scheduled-1"] =
             document
             |> LazyHTML.query(
               ~s(button[data-dashboard-context-contact-id="contact-scheduled-1"])
             )
             |> LazyHTML.attribute("phx-value-scope-id")

    assert ["scheduled"] =
             document
             |> LazyHTML.query(
               ~s(button[data-dashboard-context-contact-id="contact-scheduled-1"])
             )
             |> LazyHTML.attribute("data-dashboard-context-contact-kind")

    assert ["contact-realized-1"] =
             document
             |> LazyHTML.query(~s(button[data-dashboard-context-contact-kind="realized"]))
             |> LazyHTML.attribute("phx-value-scope-id")
  end

  test "dashboard_toolbar exposes unsupported limit mode fallback" do
    html =
      render_component(
        &DashboardToolbarComponents.dashboard_toolbar/1,
        toolbar_assigns(
          show_context?: false,
          time_mode: "archive",
          time_from: "2026-06-17T12:00:00Z",
          time_to: "2026-06-17T12:05:00Z",
          limit_mode: "observed",
          limit_mode_fallback: %{
            "requested_mode" => "projected",
            "applied_mode" => "observed",
            "reason" => "unsupported_limit_semantics_mode"
          }
        )
      )

    document = LazyHTML.from_fragment(html)

    assert ["projected"] =
             document
             |> LazyHTML.query("#dashboard-limit-mode-fallback")
             |> LazyHTML.attribute("data-requested-limit-mode")

    assert ["observed"] =
             document
             |> LazyHTML.query("#dashboard-limit-mode-fallback")
             |> LazyHTML.attribute("data-applied-limit-mode")

    assert ["unsupported_limit_semantics_mode"] =
             document
             |> LazyHTML.query("#dashboard-limit-mode-fallback")
             |> LazyHTML.attribute("data-limit-mode-fallback-reason")

    assert ["Requested projected limit semantics; using observed."] =
             document
             |> LazyHTML.query("#dashboard-limit-mode-fallback")
             |> LazyHTML.attribute("title")
  end

  test "dashboard_toolbar routes lifecycle and data operations out of the viewer" do
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

    assert [] =
             document
             |> LazyHTML.query(~s(button[data-dashboard-lifecycle-action="publish"]))
             |> LazyHTML.attribute("data-dashboard-action-available")

    assert [] =
             document
             |> LazyHTML.query(~s(button[data-dashboard-lifecycle-action="archive"]))
             |> LazyHTML.attribute("data-dashboard-action-available")

    assert [historical_request_path] =
             document
             |> LazyHTML.query("#dashboard-historical-workflow-request-button")
             |> LazyHTML.attribute("href")

    assert historical_request_path =~ "/missions/mission-1/ops/data-operations?"

    assert ["#"] =
             document
             |> LazyHTML.query("#dashboard-diagnostics-button")
             |> LazyHTML.attribute("href")

    assert [] =
             document
             |> LazyHTML.query("#runtime-context-controls")
             |> LazyHTML.attribute("id")
  end

  test "dashboard_toolbar renders publish readiness summary" do
    html =
      render_component(
        &DashboardToolbarComponents.dashboard_toolbar/1,
        toolbar_assigns(
          edit_mode?: true,
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
          edit_mode?: true,
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

  test "dashboard_toolbar exposes the page-local Compare inspector" do
    html =
      render_component(
        &DashboardToolbarComponents.dashboard_toolbar/1,
        toolbar_assigns(
          comparison_available?: true,
          comparison_open?: true,
          comparison_open_count: 2
        )
      )

    document = LazyHTML.from_fragment(html)

    assert ["toggle_comparison_inspector"] =
             document
             |> LazyHTML.query("#dashboard-comparison-toggle")
             |> LazyHTML.attribute("phx-click")

    assert ["true"] =
             document
             |> LazyHTML.query("#dashboard-comparison-toggle")
             |> LazyHTML.attribute("aria-expanded")

    assert ["2"] =
             document
             |> LazyHTML.query("[data-dashboard-comparison-open-count]")
             |> LazyHTML.attribute("data-dashboard-comparison-open-count")
  end

  test "dashboard_toolbar hides an available but inactive comparison" do
    document =
      render_component(
        &DashboardToolbarComponents.dashboard_toolbar/1,
        toolbar_assigns(comparison_available?: true)
      )
      |> LazyHTML.from_fragment()

    assert [] =
             document
             |> LazyHTML.query("#dashboard-comparison-toggle")
             |> LazyHTML.attribute("id")
  end

  test "healthy viewer keeps only scope and time as primary controls" do
    document =
      render_component(&DashboardToolbarComponents.dashboard_toolbar/1, toolbar_assigns([]))
      |> LazyHTML.from_fragment()

    assert ["scope", "time"] =
             document
             |> LazyHTML.query("[data-dashboard-primary-control]")
             |> LazyHTML.attribute("data-dashboard-primary-control")

    assert [] =
             document
             |> LazyHTML.query("#dashboard-query-options")
             |> LazyHTML.attribute("open")

    assert [] =
             document
             |> LazyHTML.query("[data-dashboard-data-override]")
             |> LazyHTML.attribute("data-dashboard-data-override")

    assert [] =
             document
             |> LazyHTML.query("#dashboard-investigate-toggle")
             |> LazyHTML.attribute("id")
  end

  test "non-default data context opens provenance controls and exposes a compact override" do
    document =
      render_component(
        &DashboardToolbarComponents.dashboard_toolbar/1,
        toolbar_assigns(data_realm: "replay", data_view: "as_recorded", limit_mode: "current")
      )
      |> LazyHTML.from_fragment()

    assert [""] =
             document
             |> LazyHTML.query("#dashboard-query-options")
             |> LazyHTML.attribute("open")

    assert [""] =
             document
             |> LazyHTML.query("[data-dashboard-data-override]")
             |> LazyHTML.attribute("data-dashboard-data-override")

    assert document |> LazyHTML.query("[data-dashboard-data-override]") |> LazyHTML.text() =~
             "Replay · As recorded"
  end

  test "dashboard_toolbar keeps telemetry primary and consolidates data issues" do
    html =
      render_component(
        &DashboardToolbarComponents.dashboard_toolbar/1,
        toolbar_assigns(
          dashboard_document: %{
            dashboard_id: "dashboard-1",
            name: "Ops",
            description: "Operations"
          },
          dashboard_degraded?: true,
          dashboard_warnings: [
            %{
              code: :stale_data,
              code_text: "stale_data",
              severity: :warning,
              label: "Stale data",
              message: "One widget is stale",
              details: %{},
              detail_rows: [],
              evidence: [],
              links: []
            }
          ],
          dashboard_health: %{state: :degraded, affected_count: 3}
        )
      )

    document = LazyHTML.from_fragment(html)

    assert ["dashboard-telemetry-toolbar"] =
             document
             |> LazyHTML.query("#dashboard-telemetry-toolbar")
             |> LazyHTML.attribute("id")

    assert ["live"] =
             document
             |> LazyHTML.query("[data-dashboard-time-summary]")
             |> LazyHTML.attribute("data-dashboard-time-summary")

    assert ["3"] =
             document
             |> LazyHTML.query("#dashboard-data-issues")
             |> LazyHTML.attribute("data-dashboard-data-issue-count")

    assert ["data_sources"] =
             document
             |> LazyHTML.query("#dashboard-data-issues-open")
             |> LazyHTML.attribute("data-dashboard-data-issue-action")

    assert [source_path] =
             document
             |> LazyHTML.query("#dashboard-data-issues-open")
             |> LazyHTML.attribute("href")

    assert source_path =~ "/missions/mission-1/ops/data-sources"

    assert [diagnostics_path] =
             document
             |> LazyHTML.query("#dashboard-data-issues-diagnostics")
             |> LazyHTML.attribute("href")

    assert diagnostics_path =~ "/missions/mission-1/ops/dashboards/dashboard-1/diagnostics"

    assert ["dashboard-data-controls-panel"] =
             document
             |> LazyHTML.query("#dashboard-data-controls-panel")
             |> LazyHTML.attribute("id")

    assert ["dashboard-query-options-panel"] =
             document
             |> LazyHTML.query("#dashboard-query-options-panel")
             |> LazyHTML.attribute("id")

    assert ["dashboard-time-controls-panel"] =
             document
             |> LazyHTML.query("#dashboard-time-controls-panel")
             |> LazyHTML.attribute("id")

    assert ["Dashboard operational scope"] =
             document
             |> LazyHTML.query("#dashboard-data-controls-toggle")
             |> LazyHTML.attribute("aria-label")

    assert ["Dashboard data options"] =
             document
             |> LazyHTML.query("#dashboard-query-options-toggle")
             |> LazyHTML.attribute("aria-label")

    assert ["Dashboard time range"] =
             document
             |> LazyHTML.query("#dashboard-time-controls-toggle")
             |> LazyHTML.attribute("aria-label")

    assert ["dashboard-menu-menu"] =
             document
             |> LazyHTML.query("#dashboard-menu-menu")
             |> LazyHTML.attribute("id")

    assert ["dashboard-investigate-telemetry"] =
             document
             |> LazyHTML.query("#dashboard-menu-menu #dashboard-investigate-telemetry")
             |> LazyHTML.attribute("id")
  end

  test "publish readiness stays out of the viewing toolbar" do
    html =
      render_component(
        &DashboardToolbarComponents.dashboard_toolbar/1,
        toolbar_assigns(
          dashboard_publish_readiness: %{status: "blocked", issues: [%{severity: :error}]}
        )
      )

    document = LazyHTML.from_fragment(html)

    assert [] =
             document
             |> LazyHTML.query("#dashboard-publish-readiness-summary")
             |> LazyHTML.attribute("id")
  end

  test "viewing toolbar exposes correlated time state and context-preserving drilldowns" do
    html =
      render_component(
        &DashboardToolbarComponents.dashboard_toolbar/1,
        toolbar_assigns(
          dashboard_document: %{
            dashboard_id: "dashboard-1",
            name: "Ops",
            description: "Operations"
          },
          context_spacecraft_id: "spacecraft-1",
          time_mode: "archive",
          time_from: "2026-06-17T12:00:00Z",
          time_to: "2026-06-17T12:05:00Z",
          data_source_id: "source-1",
          source_binding_id: "binding-1"
        )
      )

    document = LazyHTML.from_fragment(html)

    assert ["archive"] =
             document
             |> LazyHTML.query("#dashboard-active-time-range")
             |> LazyHTML.attribute("data-dashboard-time-mode")

    assert ["set_time_preset"] =
             document
             |> LazyHTML.query("#dashboard-time-preset-live")
             |> LazyHTML.attribute("phx-click")

    assert ["live"] =
             document
             |> LazyHTML.query("#dashboard-time-preset-live")
             |> LazyHTML.attribute("phx-value-preset")

    assert [href] =
             document
             |> LazyHTML.query("#dashboard-investigate-telemetry")
             |> LazyHTML.attribute("href")

    uri = URI.parse(href)
    query = URI.decode_query(uri.query)

    assert uri.path == "/missions/mission-1/ops/explore"
    assert query["source_dashboard_id"] == "dashboard-1"
    assert query["spacecraft_id"] == "spacecraft-1"
    assert query["from"] == "2026-06-17T12:00:00Z"
    assert query["to"] == "2026-06-17T12:05:00Z"
    assert query["data_source_id"] == "source-1"
    assert query["source_binding_id"] == "binding-1"
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
