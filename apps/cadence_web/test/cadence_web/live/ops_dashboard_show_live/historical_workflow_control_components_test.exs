defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowControlComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowControlComponents

  @component_id "dashboard-historical-workflow-controls-component"
  @child_components [
    "HistoricalWorkflowLatestAction",
    "HistoricalWorkflowActionExplanations",
    "HistoricalWorkflowGroupStatus",
    "HistoricalWorkflowJobStatus",
    "HistoricalWorkflowCorrectionForm",
    "HistoricalWorkflowStageForm",
    "HistoricalWorkflowGroupForm"
  ]

  test "historical_workflow_controls exposes one JSON-safe full composition" do
    html =
      render_component(&HistoricalWorkflowControlComponents.historical_workflow_controls/1,
        inspector: full_inspector(),
        action_outcome: action_outcome(),
        dashboard_current_path:
          "/missions/mission-1/ops/dashboards/dashboard-1?scope_kind=mission&scope_id=mission-1&panel=data_link"
      )

    presentation = controls_presentation(html)

    assert presentation["root"] == %{
             "id" => "dashboard-historical-workflow-controls",
             "class" => "space-y-2",
             "attrs" => %{
               "data-historical-workflow" => "backfill",
               "data-historical-workflow-stage" => "failed",
               "data-historical-workflow-run-id" => "run-1"
             }
           }

    assert presentation["heading"] == %{
             "class" => "hud-label",
             "text" => "Workflow Actions"
           }

    assert presentation["action_outcome"] == %{
             "root" => %{
               "id" => "dashboard-historical-workflow-action-outcome",
               "class" => "hidden",
               "attrs" => %{
                 "data-workflow-action" => "stage_transition",
                 "data-workflow-action-job-id" => "job-1",
                 "data-workflow-action-kind" => "error",
                 "data-workflow-action-reason" => "confirmation_required",
                 "data-workflow-action-stage" => "approved",
                 "data-workflow-action-status" => "blocked",
                 "data-workflow-action-target-event-id" => "event-1",
                 "data-workflow-action-target-run-id" => "run-1"
               }
             },
             "message" =>
               "Confirm the historical data workflow approved transition before recording it."
           }

    assert ordered_child_roots(presentation) == [
             {"latest_action", "dashboard-historical-workflow-latest-action"},
             {"action_explanations", "dashboard-historical-workflow-action-explanations"},
             {"group_status", "dashboard-historical-workflow-group-summary"},
             {"job_status", "dashboard-historical-workflow-job-status"},
             {"correction_form", "dashboard-historical-workflow-correction-form"},
             {"stage_form", "dashboard-historical-workflow-form"},
             {"group_form", "dashboard-historical-workflow-group-form"}
           ]

    assert presentation["latest_action"]["root"]["attrs"][
             "data-workflow-latest-action"
           ] == "stage_transition"

    assert presentation["correction_form"]["root"]["attrs"]["phx-submit"] ==
             "record_corrected_historical_workflow_request"

    assert presentation["stage_form"]["root"]["attrs"]["phx-submit"] ==
             "record_historical_workflow_stage"

    assert presentation["group_form"]["root"]["attrs"]["phx-submit"] ==
             "record_historical_workflow_group_stage"

    assert_vue_source_composition()
  end

  test "historical_workflow_controls represents conditionally absent children as nil" do
    html =
      render_component(&HistoricalWorkflowControlComponents.historical_workflow_controls/1,
        inspector: sparse_inspector(),
        action_outcome: nil,
        dashboard_current_path: "/missions/mission-1/ops/dashboards/dashboard-1"
      )

    presentation = controls_presentation(html)

    assert presentation["action_outcome"] == nil
    assert presentation["latest_action"] == nil
    assert presentation["group_status"] == nil
    assert presentation["job_status"] == nil
    assert presentation["correction_form"] == nil
    assert presentation["group_form"] == nil
    assert is_map(presentation["action_explanations"])

    assert presentation["stage_form"]["root"]["attrs"]["id"] ==
             "dashboard-historical-workflow-form"
  end

  defp controls_presentation(html) do
    assert [@component_id] =
             html
             |> LazyHTML.from_fragment()
             |> LazyHTML.query(~s([phx-hook="VueHook"]))
             |> LazyHTML.attribute("id")

    vue = LiveVue.Test.get_vue(html, id: @component_id)

    assert vue.component == "HistoricalWorkflowControls"
    assert vue.id == @component_id
    assert vue.ssr == false
    assert vue.class == "contents"
    assert vue.handlers == %{}
    assert Map.keys(vue.props) == ["presentation"]
    assert vue.props == Jason.decode!(Jason.encode!(vue.props))

    Map.fetch!(vue.props, "presentation")
  end

  defp ordered_child_roots(presentation) do
    ~w(latest_action action_explanations group_status job_status correction_form stage_form group_form)
    |> Enum.map(fn key -> {key, child_root_id(Map.fetch!(presentation, key))} end)
  end

  defp child_root_id(%{"root" => %{"id" => id}}), do: id
  defp child_root_id(%{"root" => %{"attrs" => %{"id" => id}}}), do: id

  defp assert_vue_source_composition do
    source =
      File.read!(Path.expand("../../../../assets/vue/HistoricalWorkflowControls.vue", __DIR__))

    assert Enum.all?(@child_components, fn component ->
             source =~ ~s(import #{component} from "./#{component}.vue")
           end)

    assert @child_components ==
             @child_components
             |> Enum.map(fn component ->
               {position, _length} = :binary.match(source, "<#{component}")
               {position, component}
             end)
             |> Enum.sort()
             |> Enum.map(&elem(&1, 1))
  end

  defp full_inspector do
    %{
      rows: [
        row("Backfill lifecycle event", "event-1"),
        row("Event type", "backfill_failed"),
        row("Workflow", "backfill"),
        row("Workflow stage", "failed"),
        row("Workflow run", "run-1"),
        row("Realm", "flight"),
        row("Data source", "questdb-flight"),
        row("Source binding", "binding-flight"),
        row("Observable", "HK.counter"),
        row("Point", "HK.counter"),
        row("Source from", "2026-06-22T10:00:00Z"),
        row("Source to", "2026-06-22T11:00:00Z"),
        row("Request mode", "bulk_points"),
        row("Request group", "group-1"),
        row("Request item", "2/3"),
        row("Request group state", "failed"),
        row("Request group progress", "1/3"),
        row("Request group retryable failed", "1"),
        row("Workflow job", "job-1"),
        row("Workflow job status", "failed"),
        row("Workflow retryable", "true"),
        row("Workflow recovery action", "correct_workflow_request"),
        row("Workflow source point", "HK.counter"),
        row("Workflow source realm", "flight"),
        row("Workflow source data source", "questdb-flight"),
        row("Workflow source binding", "binding-flight")
      ]
    }
  end

  defp sparse_inspector do
    %{
      rows: [
        row("Backfill lifecycle event", "event-1"),
        row("Event type", "backfill_requested"),
        row("Workflow", "backfill"),
        row("Workflow stage", "requested"),
        row("Workflow run", "run-1"),
        row("Realm", "flight"),
        row("Data source", "questdb-flight"),
        row("Source binding", "binding-flight")
      ]
    }
  end

  defp action_outcome do
    %{
      action: "stage_transition",
      status: "blocked",
      kind: "error",
      reason: "confirmation_required",
      stage: "approved",
      job_id: "job-1",
      target_event_id: "event-1",
      target_run_id: "run-1",
      message: "Confirm the historical data workflow approved transition before recording it."
    }
  end

  defp row(label, value), do: %{label: label, value: value}
end
