defmodule CadenceWeb.OpsDashboardShowLive.DashboardWarningComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias CadenceWeb.OpsDashboardShowLive.Components

  test "dashboard warnings expose selected clock and missing limit samples" do
    html =
      render_component(&Components.dashboard_warnings/1,
        degraded?: true,
        warnings: [
          %{
            code: :incomplete_limit_evaluation,
            code_text: "incomplete_limit_evaluation",
            severity: :warning,
            severity_text: "warning",
            label: "Incomplete limit analysis",
            message:
              "Some telemetry samples have no active complete limit definition for recomputation",
            details: %{
              selected_limit_clock: %{
                observed: :limit_event_receipt_time,
                requested_time_axis: :receipt_time,
                requested_time_mode: "archive"
              },
              missing_sample_ids: ["sample-missing"],
              requested_semantics_mode: :recomputed
            },
            detail_rows: [
              %{label: "Selected clock", value: "observed=limit_event_receipt_time"},
              %{label: "Missing samples", value: "sample-missing"}
            ],
            evidence: [],
            links: [],
            actions: []
          }
        ]
      )

    document = LazyHTML.from_fragment(html)

    assert ["incomplete_limit_evaluation"] =
             document
             |> LazyHTML.query("#dashboard-engine-warnings")
             |> LazyHTML.attribute("data-warning-codes")

    vue = LiveVue.Test.get_vue(html, id: "dashboard-engine-warning-0-component")
    assert vue.component == "WidgetWarning"
    assert vue.id == "dashboard-engine-warning-0-component"
    assert vue.ssr == false
    assert vue.class == "contents"
    warning = vue.props["presentation"]

    assert [
             "observed=limit_event_receipt_time requested_time_axis=receipt_time requested_time_mode=archive"
           ] == [warning["overlay"]["attrs"]["data-limit-selected-clock"]]

    assert warning["overlay"]["attrs"]["data-limit-missing-samples"] == "sample-missing"
    assert warning["overlay"]["attrs"]["data-limit-mode"] == "recomputed"

    assert "Selected clock" in Enum.map(
             warning["body"]["details"]["rows"],
             & &1["value"]["attrs"]["data-warning-detail"]
           )
  end

  test "dashboard warnings assign unique popover ids to repeated warning codes" do
    repeated_warning = %{
      code: :unknown_limit_definition,
      code_text: "unknown_limit_definition",
      severity: :warning,
      severity_text: "warning",
      label: "Unknown limit definition",
      message: "A limit definition could not be resolved.",
      details: %{},
      detail_rows: [],
      evidence: [],
      links: [],
      actions: []
    }

    html =
      render_component(&Components.dashboard_warnings/1,
        degraded?: true,
        warnings: [repeated_warning, repeated_warning]
      )

    warnings =
      for index <- 0..1 do
        component_id = "dashboard-engine-warning-#{index}-component"
        vue = LiveVue.Test.get_vue(html, id: component_id)
        assert vue.component == "WidgetWarning"
        assert vue.id == component_id
        assert vue.ssr == false
        vue.props["presentation"]
      end

    assert Enum.map(warnings, & &1["overlay"]["id"]) == [
             "dashboard-engine-warning-0",
             "dashboard-engine-warning-1"
           ]

    assert Enum.map(warnings, & &1["overlay"]["attrs"]["data-engine-warning-detail"]) == [
             "unknown_limit_definition",
             "unknown_limit_definition"
           ]
  end
end
