defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowActionExplanationComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowActionExplanationComponents

  test "action_explanations renders unavailable workflow actions" do
    html =
      render_component(&HistoricalWorkflowActionExplanationComponents.action_explanations/1,
        blocked_action_explanations: [
          %{
            id: "correction_request",
            kind: "correction",
            label: "Request correction",
            reason: "job_failed",
            explanation: "A correction request needs failed job evidence.",
            state_summary: "job job-1; status failed",
            available_when: "Available after review."
          }
        ]
      )

    document = LazyHTML.from_fragment(html)

    assert ["correction_request"] =
             document
             |> LazyHTML.query("[data-workflow-action-explanation-id]")
             |> LazyHTML.attribute("data-workflow-action-explanation-id")

    assert ["job job-1; status failed"] =
             document
             |> LazyHTML.query("[data-workflow-action-explanation-state]")
             |> LazyHTML.attribute("data-workflow-action-explanation-state")

    assert document
           |> LazyHTML.query("#dashboard-historical-workflow-action-explanations")
           |> LazyHTML.text()
           |> String.contains?("Available after review.")
  end

  test "action_explanations renders nothing for an empty action list" do
    html =
      render_component(&HistoricalWorkflowActionExplanationComponents.action_explanations/1,
        blocked_action_explanations: []
      )
      |> LazyHTML.from_fragment()

    assert [] =
             html
             |> LazyHTML.query("#dashboard-historical-workflow-action-explanations")
             |> LazyHTML.attribute("id")
  end
end
