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

    vue = action_explanations_vue(html)
    presentation = vue.props["presentation"]
    [correction_request] = presentation["items"]

    assert correction_request["attrs"]["data-workflow-action-explanation-id"] ==
             "correction_request"

    assert correction_request["attrs"]["data-workflow-action-explanation-state"] ==
             "job job-1; status failed"

    assert correction_request["available_when"]["text"] == "Available after review."

    assert presentation == %{
             "root" => %{
               "id" => "dashboard-historical-workflow-action-explanations",
               "class" => "space-y-1 rounded border border-base-300/70 bg-base-100/60 p-2 text-xs"
             },
             "header" => %{
               "class" => "flex items-center justify-between gap-2",
               "heading" => %{"class" => "hud-label", "text" => "Unavailable Actions"},
               "count" => %{"class" => "badge badge-xs badge-outline", "text" => "1"}
             },
             "items_container" => %{"class" => "space-y-1"},
             "items" => [
               %{
                 "key" => "historical-workflow-action-explanation-0",
                 "class" => "rounded border border-base-300/60 bg-base-200/40 px-2 py-1",
                 "attrs" => %{
                   "data-workflow-action-explanation-id" => "correction_request",
                   "data-workflow-action-explanation-kind" => "correction",
                   "data-workflow-action-explanation-reason" => "job_failed",
                   "data-workflow-action-explanation-state" => "job job-1; status failed"
                 },
                 "header" => %{"class" => "flex items-center justify-between gap-2"},
                 "label" => %{
                   "class" => "font-mono text-base-content",
                   "text" => "Request correction"
                 },
                 "reason" => %{
                   "class" => "font-mono text-base-content/60",
                   "text" => "job_failed"
                 },
                 "explanation" => %{
                   "class" => "mt-1 text-base-content/75",
                   "text" => "A correction request needs failed job evidence."
                 },
                 "state" => %{
                   "visible" => true,
                   "class" => "mt-1 font-mono text-base-content/65",
                   "text" => "job job-1; status failed"
                 },
                 "available_when" => %{
                   "visible" => true,
                   "class" => "mt-1 text-base-content/60",
                   "text" => "Available after review."
                 }
               }
             ]
           }
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

    assert [] =
             html
             |> LazyHTML.query("#dashboard-historical-workflow-action-explanations-component")
             |> LazyHTML.attribute("id")
  end

  test "action_explanations preserves raw HEEx attribute body and visibility semantics" do
    html =
      render_component(&HistoricalWorkflowActionExplanationComponents.action_explanations/1,
        blocked_action_explanations: [
          %{
            id: nil,
            kind: false,
            label: false,
            reason: true,
            explanation: nil,
            state_summary: "",
            available_when: 7
          },
          %{
            id: "",
            kind: true,
            label: true,
            reason: 42,
            explanation: false,
            state_summary: true,
            available_when: nil
          }
        ]
      )

    presentation =
      html
      |> action_explanations_vue()
      |> Map.fetch!(:props)
      |> Map.fetch!("presentation")

    [nil_and_false, true_empty_and_number] = presentation["items"]

    assert Enum.map(presentation["items"], & &1["key"]) == [
             "historical-workflow-action-explanation-0",
             "historical-workflow-action-explanation-1"
           ]

    assert Enum.map(presentation["items"], & &1["attrs"]) == [
             %{
               "data-workflow-action-explanation-reason" => "",
               "data-workflow-action-explanation-state" => ""
             },
             %{
               "data-workflow-action-explanation-id" => "",
               "data-workflow-action-explanation-kind" => "",
               "data-workflow-action-explanation-reason" => "42",
               "data-workflow-action-explanation-state" => ""
             }
           ]

    assert Enum.map(presentation["items"], fn item ->
             %{
               "label" => item["label"]["text"],
               "reason" => item["reason"]["text"],
               "explanation" => item["explanation"]["text"]
             }
           end) == [
             %{"label" => "false", "reason" => "true", "explanation" => ""},
             %{"label" => "true", "reason" => "42", "explanation" => "false"}
           ]

    assert {nil_and_false["state"], nil_and_false["available_when"]} ==
             {
               %{
                 "visible" => false,
                 "class" => "mt-1 font-mono text-base-content/65",
                 "text" => ""
               },
               %{
                 "visible" => false,
                 "class" => "mt-1 text-base-content/60",
                 "text" => "7"
               }
             }

    assert {true_empty_and_number["state"], true_empty_and_number["available_when"]} ==
             {
               %{
                 "visible" => false,
                 "class" => "mt-1 font-mono text-base-content/65",
                 "text" => "true"
               },
               %{
                 "visible" => false,
                 "class" => "mt-1 text-base-content/60",
                 "text" => ""
               }
             }
  end

  defp action_explanations_vue(html) do
    vue =
      LiveVue.Test.get_vue(html,
        id: "dashboard-historical-workflow-action-explanations-component"
      )

    assert vue.component == "HistoricalWorkflowActionExplanations"
    assert vue.id == "dashboard-historical-workflow-action-explanations-component"
    assert vue.ssr == false
    assert vue.class == "contents"
    assert vue.handlers == %{}
    assert Map.keys(vue.props) == ["presentation"]
    assert vue.props == Jason.decode!(Jason.encode!(vue.props))

    vue
  end
end
