defmodule CadenceWeb.OpsDashboardShowLive.DashboardWarningComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias CadenceWeb.OpsDashboardShowLive.Components
  alias CadenceWeb.OpsDashboardShowLive.WidgetWarningComponents

  test "dashboard warnings expose selected clock and missing limit samples" do
    source_warning = %{
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

    html =
      render_component(&Components.dashboard_warnings/1,
        degraded?: true,
        warnings: [source_warning]
      )

    vue = LiveVue.Test.get_vue(html, id: "dashboard-engine-warnings-component")

    assert vue.component == "DashboardWarnings"
    assert vue.id == "dashboard-engine-warnings-component"
    assert vue.ssr == false
    assert vue.class == "contents"
    assert vue.handlers == %{}
    assert vue.props == Jason.decode!(Jason.encode!(vue.props))

    presentation = vue.props["presentation"]

    assert presentation["root"] == %{
             "attrs" => %{
               "data-engine-degraded" => "true",
               "data-warning-codes" => "incomplete_limit_evaluation"
             },
             "class" =>
               "shrink-0 flex items-center gap-2 px-2 py-1 border-b border-warning/30 bg-warning/10 text-xs",
             "id" => "dashboard-engine-warnings"
           }

    [warning] = presentation["warnings"]

    expected_warning =
      WidgetWarningComponents.warning_presentation(
        "dashboard-engine-warning-0",
        source_warning,
        nil
      )
      |> Jason.encode!()
      |> Jason.decode!()

    assert warning == expected_warning
    assert warning["component_id"] == "dashboard-engine-warning-0-component"

    assert warning["body"]["evidence_button"]["attrs"] == %{
             "data-warning-evidence-open" => "",
             "phx-click" => "open_evidence",
             "phx-value-kind" => "warning",
             "phx-value-warning-code" => "incomplete_limit_evaluation"
           }

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

    vue = LiveVue.Test.get_vue(html, id: "dashboard-engine-warnings-component")
    assert vue.component == "DashboardWarnings"
    assert vue.id == "dashboard-engine-warnings-component"
    assert vue.ssr == false

    warnings =
      for {warning, index} <- Enum.with_index(vue.props["presentation"]["warnings"]) do
        component_id = "dashboard-engine-warning-#{index}-component"
        assert warning["component_id"] == component_id
        assert warning["overlay"]["id"] == "dashboard-engine-warning-#{index}"
        warning
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

  test "dashboard warnings preserve the degraded fallback and hidden empty state" do
    degraded_html =
      render_component(&Components.dashboard_warnings/1,
        degraded?: true,
        warnings: []
      )

    vue = LiveVue.Test.get_vue(degraded_html, id: "dashboard-engine-warnings-component")
    presentation = vue.props["presentation"]

    assert presentation["root"]["attrs"] == %{
             "data-engine-degraded" => "true",
             "data-warning-codes" => ""
           }

    assert presentation["label"] == %{
             "class" => "font-semibold text-warning",
             "text" => "Dashboard degraded"
           }

    assert presentation["fallback"] == %{
             "class" => "text-base-content/70",
             "text" => "One or more sources returned degraded data.",
             "visible" => true
           }

    assert presentation["warnings"] == []

    warning_only_html =
      render_component(&Components.dashboard_warnings/1,
        degraded?: false,
        warnings: [
          %{
            code_text: "source_degraded",
            severity: :warning,
            label: "Source degraded",
            message: "A source returned degraded data.",
            details: %{},
            detail_rows: [],
            evidence: [],
            links: []
          }
        ]
      )

    warning_only_vue =
      LiveVue.Test.get_vue(warning_only_html, id: "dashboard-engine-warnings-component")

    warning_only = warning_only_vue.props["presentation"]

    assert warning_only["root"]["attrs"]["data-engine-degraded"] == "false"
    assert warning_only["root"]["attrs"]["data-warning-codes"] == "source_degraded"
    assert warning_only["fallback"]["visible"] == false

    hidden_html =
      render_component(&Components.dashboard_warnings/1,
        degraded?: false,
        warnings: []
      )

    assert [] ==
             hidden_html
             |> LazyHTML.from_fragment()
             |> LazyHTML.query("#dashboard-engine-warnings-component")
             |> LazyHTML.attribute("id")
  end
end
