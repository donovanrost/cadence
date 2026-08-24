defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowLatestActionComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias CadenceWeb.OpsDashboardShowLive.{
    HistoricalWorkflowActionOutcomePresentation,
    HistoricalWorkflowLatestActionComponents
  }

  test "latest_action renders result handoff links and retry disposition details" do
    html =
      render_component(&HistoricalWorkflowLatestActionComponents.latest_action/1,
        latest_action_outcome: %{
          class: "border-info/30 bg-info/10",
          action: "retry_job",
          action_label: "Retry job",
          status: "ok",
          status_label: "Queued",
          badge_class: "badge-info",
          reason: "retry_job_queued",
          stage: "started",
          job_id: "job-1",
          count: "1",
          retried: "true",
          retry_nonretryable: "1",
          retry_skipped: "1",
          retry_errors: "0",
          retry_scope: "replacement_jobs",
          retry_run_ids: "run-004-corrected",
          retry_disposition: %{
            nonretryable_run_ids: "run-nonretryable",
            nonretryable_event_ids: "failed-event-nonretryable",
            nonretryable_items:
              "run=run-nonretryable event=failed-event-nonretryable action=correct_workflow_request reason=correction_required",
            skipped_run_ids: "run-skipped",
            skipped_event_ids: "failed-event-skipped",
            skipped_items:
              "run=run-skipped event=failed-event-skipped job=job-skipped status=running reason=job_not_failed"
          },
          retry_error_run_ids: "run-004-corrected",
          retry_error_event_ids: "failed-event-4",
          retry_error_items:
            "run=run-004-corrected event=failed-event-4 job=job-4 reason=queue_down",
          queued_jobs: "2",
          failed_jobs: "0",
          result_event_ids: "retry-event-1",
          target_event_id: "source-event-1",
          target_run_id: "run-1",
          dashboard_id: "dashboard-1",
          dashboard_version: "7",
          dashboard_time_mode: "replay_run",
          dashboard_replay_run_id: "replay-1",
          dashboard_data_view: "all_revisions",
          dashboard_limit_mode: "observed",
          message: "Historical workflow job retry queued."
        },
        dashboard_current_path:
          "/missions/mission-1/ops/dashboards/dashboard-1?scope_kind=mission&scope_id=mission-1&panel=versions&activity_filter=open_comparison_reviews&activity_event=review-event-1&selected_placement=placement-1"
      )

    presentation = latest_action_presentation(html)
    root = Map.fetch!(presentation, "root")
    root_attrs = Map.fetch!(root, "attrs")

    assert root == %{
             "id" => "dashboard-historical-workflow-latest-action",
             "class" => "rounded border p-2 text-xs border-info/30 bg-info/10",
             "attrs" => %{
               "data-workflow-latest-action" => "retry_job",
               "data-workflow-latest-action-count" => "1",
               "data-workflow-latest-action-dashboard-data-view" => "all_revisions",
               "data-workflow-latest-action-dashboard-id" => "dashboard-1",
               "data-workflow-latest-action-dashboard-limit-mode" => "observed",
               "data-workflow-latest-action-dashboard-replay-run-id" => "replay-1",
               "data-workflow-latest-action-dashboard-time-mode" => "replay_run",
               "data-workflow-latest-action-dashboard-version" => "7",
               "data-workflow-latest-action-failed-jobs" => "0",
               "data-workflow-latest-action-handoff-count" => "2",
               "data-workflow-latest-action-job-id" => "job-1",
               "data-workflow-latest-action-primary-result-event-id" => "source-event-1",
               "data-workflow-latest-action-queued-jobs" => "2",
               "data-workflow-latest-action-reason" => "retry_job_queued",
               "data-workflow-latest-action-result-event-ids" => "retry-event-1",
               "data-workflow-latest-action-retried" => "true",
               "data-workflow-latest-action-retry-error-event-ids" => "failed-event-4",
               "data-workflow-latest-action-retry-error-items" =>
                 "run=run-004-corrected event=failed-event-4 job=job-4 reason=queue_down",
               "data-workflow-latest-action-retry-error-run-ids" => "run-004-corrected",
               "data-workflow-latest-action-retry-errors" => "0",
               "data-workflow-latest-action-retry-nonretryable" => "1",
               "data-workflow-latest-action-retry-nonretryable-event-ids" =>
                 "failed-event-nonretryable",
               "data-workflow-latest-action-retry-nonretryable-items" =>
                 "run=run-nonretryable event=failed-event-nonretryable action=correct_workflow_request reason=correction_required",
               "data-workflow-latest-action-retry-nonretryable-run-ids" => "run-nonretryable",
               "data-workflow-latest-action-retry-run-ids" => "run-004-corrected",
               "data-workflow-latest-action-retry-scope" => "replacement_jobs",
               "data-workflow-latest-action-retry-skipped" => "1",
               "data-workflow-latest-action-retry-skipped-event-ids" => "failed-event-skipped",
               "data-workflow-latest-action-retry-skipped-items" =>
                 "run=run-skipped event=failed-event-skipped job=job-skipped status=running reason=job_not_failed",
               "data-workflow-latest-action-retry-skipped-run-ids" => "run-skipped",
               "data-workflow-latest-action-stage" => "started",
               "data-workflow-latest-action-status" => "ok",
               "data-workflow-latest-action-target-event-id" => "source-event-1",
               "data-workflow-latest-action-target-run-id" => "run-1"
             }
           }

    assert presentation["header"] == %{
             "class" => "flex items-center justify-between gap-2",
             "label" => %{"class" => "hud-label", "text" => "Last Action"},
             "status" => %{"class" => "badge badge-xs badge-info", "text" => "Queued"}
           }

    assert presentation["message"] == %{
             "class" => "mt-1 text-base-content/80",
             "text" => "Historical workflow job retry queued."
           }

    assert presentation["details"] == %{
             "class" => "mt-2 grid grid-cols-[5rem_minmax(0,1fr)] gap-x-2 gap-y-1",
             "rows" => [
               detail_row("action", "Action", "Retry job"),
               detail_row("reason", "Reason", "retry_job_queued"),
               detail_row("stage", "Stage", "started"),
               detail_row("job", "Job", "job-1"),
               detail_row("event", "Event", "source-event-1"),
               detail_row("run", "Run", "run-1"),
               detail_row("results", "Results", "retry-event-1"),
               detail_row("count", "Count", "1"),
               detail_row("retried", "Retried", "true"),
               detail_row("non-retry", "Non-retry", "1"),
               detail_row("skipped", "Skipped", "1"),
               detail_row("non-retry-runs", "Non-retry runs", "run-nonretryable"),
               detail_row(
                 "non-retry-events",
                 "Non-retry events",
                 "failed-event-nonretryable"
               ),
               detail_row(
                 "non-retry-items",
                 "Non-retry items",
                 "run=run-nonretryable event=failed-event-nonretryable action=correct_workflow_request reason=correction_required"
               ),
               detail_row("skipped-runs", "Skipped runs", "run-skipped"),
               detail_row("skipped-events", "Skipped events", "failed-event-skipped"),
               detail_row(
                 "skipped-items",
                 "Skipped items",
                 "run=run-skipped event=failed-event-skipped job=job-skipped status=running reason=job_not_failed"
               ),
               detail_row("errors", "Errors", "0"),
               detail_row("error-runs", "Error runs", "run-004-corrected"),
               detail_row("error-events", "Error events", "failed-event-4"),
               detail_row(
                 "error-items",
                 "Error items",
                 "run=run-004-corrected event=failed-event-4 job=job-4 reason=queue_down"
               ),
               detail_row("scope", "Scope", "replacement_jobs"),
               detail_row("retry-runs", "Retry runs", "run-004-corrected"),
               detail_row("queued", "Queued", "2"),
               detail_row("failed", "Failed", "0")
             ]
           }

    handoffs_presentation = Map.fetch!(presentation, "handoffs")
    handoff_links = Map.fetch!(handoffs_presentation, "links")

    assert Map.drop(handoffs_presentation, ["links"]) == %{
             "visible" => true,
             "id" => "dashboard-historical-workflow-latest-action-handoffs",
             "class" => "mt-2 space-y-2 rounded border border-base-300/60 bg-base-100/70 p-2",
             "attrs" => %{
               "data-workflow-latest-action-handoff-count" => "2",
               "data-workflow-latest-action-handoff-primary-event" => "source-event-1"
             },
             "header" => %{
               "class" => "flex items-center justify-between gap-2",
               "label" => %{"class" => "hud-label", "text" => "Result Handoff"},
               "count" => %{"class" => "font-mono text-base-content/70", "text" => "2"}
             },
             "links_container" => %{"class" => "flex flex-wrap gap-1"}
           }

    assert Enum.map(handoff_links, &Map.drop(&1, ["href", "attrs"])) == [
             %{
               "key" => "historical-workflow-latest-action-handoff-0",
               "navigation_kind" => "patch",
               "class" => "badge badge-xs badge-outline",
               "text" => "Selected event"
             },
             %{
               "key" => "historical-workflow-latest-action-handoff-1",
               "navigation_kind" => "patch",
               "class" => "badge badge-xs badge-outline",
               "text" => "Result 1"
             }
           ]

    assert Enum.all?(handoff_links, fn link ->
             link["href"] == link["attrs"]["data-workflow-latest-action-handoff-href"] and
               link["attrs"]["data-phx-link"] == "patch" and
               link["attrs"]["data-phx-link-state"] == "push"
           end)

    assert "2" == root_attrs["data-workflow-latest-action-handoff-count"]

    assert "source-event-1" ==
             root_attrs["data-workflow-latest-action-primary-result-event-id"]

    assert "run-nonretryable" ==
             root_attrs["data-workflow-latest-action-retry-nonretryable-run-ids"]

    assert "1" == root_attrs["data-workflow-latest-action-retry-nonretryable"]

    assert "1" == root_attrs["data-workflow-latest-action-retry-skipped"]

    assert "0" == root_attrs["data-workflow-latest-action-retry-errors"]

    assert "failed-event-skipped" ==
             root_attrs["data-workflow-latest-action-retry-skipped-event-ids"]

    assert "run=run-skipped event=failed-event-skipped job=job-skipped status=running reason=job_not_failed" ==
             root_attrs["data-workflow-latest-action-retry-skipped-items"]

    assert "run=run-004-corrected event=failed-event-4 job=job-4 reason=queue_down" ==
             root_attrs["data-workflow-latest-action-retry-error-items"]

    assert "2" == root_attrs["data-workflow-latest-action-queued-jobs"]

    assert "0" == root_attrs["data-workflow-latest-action-failed-jobs"]

    assert "replay-1" == root_attrs["data-workflow-latest-action-dashboard-replay-run-id"]

    assert "all_revisions" == root_attrs["data-workflow-latest-action-dashboard-data-view"]

    assert "observed" == root_attrs["data-workflow-latest-action-dashboard-limit-mode"]

    assert presentation["message"]["text"] == "Historical workflow job retry queued."

    detail_values = Map.new(presentation["details"]["rows"], &{&1["key"], &1["value"]["text"]})

    assert detail_values["non-retry-items"] =~
             "run=run-nonretryable event=failed-event-nonretryable action=correct_workflow_request reason=correction_required"

    assert detail_values["skipped-items"] =~
             "run=run-skipped event=failed-event-skipped job=job-skipped status=running reason=job_not_failed"

    assert detail_values["error-items"] =~
             "run=run-004-corrected event=failed-event-4 job=job-4 reason=queue_down"

    handoffs =
      Enum.map(handoff_links, fn link ->
        attrs = Map.fetch!(link, "attrs")

        {
          attrs["data-workflow-latest-action-handoff"],
          attrs["data-workflow-latest-action-handoff-role"],
          attrs["data-workflow-latest-action-handoff-label"],
          link["text"],
          review_href_query(link["href"])
        }
      end)

    assert handoffs == [
             {"source-event-1", "target", "Selected event", "Selected event",
              %{
                "scope_kind" => "mission",
                "scope_id" => "mission-1",
                "panel" => "data_link",
                "selected_target" => "telemetry_backfill_lifecycle_event",
                "selected_id" => "source-event-1"
              }},
             {"retry-event-1", "result", "Result 1", "Result 1",
              %{
                "scope_kind" => "mission",
                "scope_id" => "mission-1",
                "panel" => "data_link",
                "selected_target" => "telemetry_backfill_lifecycle_event",
                "selected_id" => "retry-event-1"
              }}
           ]
  end

  test "latest_action renders no-eligible group policy outcome context" do
    html =
      render_component(&HistoricalWorkflowLatestActionComponents.latest_action/1,
        latest_action_outcome: %{
          class: "border-base-300/70 bg-base-100/60 text-base-content",
          action: "group_stage_transition",
          action_label: "Group stage",
          status: "no_op",
          status_label: "No-op",
          badge_class: "badge-ghost",
          reason: "no_eligible_group_items",
          stage: "approved",
          request_group_id: "request-group-1",
          job_id: nil,
          count: nil,
          retried: nil,
          retry_nonretryable: nil,
          retry_skipped: nil,
          retry_errors: nil,
          retry_scope: nil,
          retry_run_ids: nil,
          retry_disposition: %{},
          retry_error_run_ids: nil,
          retry_error_event_ids: nil,
          retry_error_items: nil,
          queued_jobs: nil,
          failed_jobs: nil,
          result_event_ids: nil,
          target_event_id: nil,
          target_run_id: nil,
          message:
            "No approve items are eligible in request group request-group-1. The workflow panel was refreshed with current eligibility counts."
        },
        dashboard_current_path: "/missions/mission-1/ops/dashboards/dashboard-1"
      )

    presentation = latest_action_presentation(html)
    root_attrs = presentation["root"]["attrs"]

    assert presentation["root"] == %{
             "id" => "dashboard-historical-workflow-latest-action",
             "class" =>
               "rounded border p-2 text-xs border-base-300/70 bg-base-100/60 text-base-content",
             "attrs" => %{
               "data-workflow-latest-action" => "group_stage_transition",
               "data-workflow-latest-action-handoff-count" => "0",
               "data-workflow-latest-action-reason" => "no_eligible_group_items",
               "data-workflow-latest-action-request-group-id" => "request-group-1",
               "data-workflow-latest-action-stage" => "approved",
               "data-workflow-latest-action-status" => "no_op"
             }
           }

    assert presentation["header"] == %{
             "class" => "flex items-center justify-between gap-2",
             "label" => %{"class" => "hud-label", "text" => "Last Action"},
             "status" => %{"class" => "badge badge-xs badge-ghost", "text" => "No-op"}
           }

    assert presentation["message"] == %{
             "class" => "mt-1 text-base-content/80",
             "text" =>
               "No approve items are eligible in request group request-group-1. The workflow panel was refreshed with current eligibility counts."
           }

    assert presentation["details"] == %{
             "class" => "mt-2 grid grid-cols-[5rem_minmax(0,1fr)] gap-x-2 gap-y-1",
             "rows" => [
               detail_row("action", "Action", "Group stage"),
               detail_row("reason", "Reason", "no_eligible_group_items"),
               detail_row("stage", "Stage", "approved"),
               detail_row("group", "Group", "request-group-1")
             ]
           }

    assert presentation["handoffs"] == %{
             "visible" => false,
             "id" => "dashboard-historical-workflow-latest-action-handoffs",
             "class" => "mt-2 space-y-2 rounded border border-base-300/60 bg-base-100/70 p-2",
             "attrs" => %{"data-workflow-latest-action-handoff-count" => "0"},
             "header" => %{
               "class" => "flex items-center justify-between gap-2",
               "label" => %{"class" => "hud-label", "text" => "Result Handoff"},
               "count" => %{"class" => "font-mono text-base-content/70", "text" => "0"}
             },
             "links_container" => %{"class" => "flex flex-wrap gap-1"},
             "links" => []
           }

    assert "request-group-1" ==
             root_attrs["data-workflow-latest-action-request-group-id"]

    assert "no_eligible_group_items" == root_attrs["data-workflow-latest-action-reason"]

    assert presentation["message"]["text"] =~
             "No approve items are eligible in request group request-group-1"

    detail_text =
      presentation["details"]["rows"]
      |> Enum.flat_map(&[&1["label"]["text"], &1["value"]["text"]])
      |> Enum.join(" ")

    assert detail_text =~ "Group"
    assert detail_text =~ "request-group-1"

    assert presentation["handoffs"]["links"] == []
  end

  test "latest_action renders no card when there is no outcome" do
    html =
      render_component(&HistoricalWorkflowLatestActionComponents.latest_action/1,
        latest_action_outcome: nil,
        dashboard_current_path: "/missions/mission-1/ops/dashboards/dashboard-1"
      )

    assert_raise RuntimeError,
                 ~s(No Vue component found with id="dashboard-historical-workflow-latest-action-component". Available components: ),
                 fn ->
                   LiveVue.Test.get_vue(html,
                     id: "dashboard-historical-workflow-latest-action-component"
                   )
                 end

    false_html =
      render_component(&HistoricalWorkflowLatestActionComponents.latest_action/1,
        latest_action_outcome: false,
        dashboard_current_path: "/missions/mission-1/ops/dashboards/dashboard-1"
      )

    assert_raise RuntimeError,
                 ~s(No Vue component found with id="dashboard-historical-workflow-latest-action-component". Available components: ),
                 fn ->
                   LiveVue.Test.get_vue(false_html,
                     id: "dashboard-historical-workflow-latest-action-component"
                   )
                 end

    scalar_html =
      render_component(&HistoricalWorkflowLatestActionComponents.latest_action/1,
        latest_action_outcome: %HistoricalWorkflowActionOutcomePresentation{
          class: "border-info/30 bg-info/10",
          action: false,
          action_label: false,
          status: true,
          status_label: true,
          kind: "",
          reason: false,
          stage: true,
          job_id: 7,
          message: nil,
          badge_class: "badge-info"
        },
        dashboard_current_path: "/missions/mission-1/ops/dashboards/dashboard-1"
      )

    scalar_presentation = latest_action_presentation(scalar_html)
    scalar_attrs = scalar_presentation["root"]["attrs"]

    assert scalar_attrs == %{
             "data-workflow-latest-action-handoff-count" => "0",
             "data-workflow-latest-action-job-id" => "7",
             "data-workflow-latest-action-stage" => "",
             "data-workflow-latest-action-status" => ""
           }

    refute Map.has_key?(scalar_attrs, "data-workflow-latest-action")
    refute Map.has_key?(scalar_attrs, "data-workflow-latest-action-kind")
    refute Map.has_key?(scalar_attrs, "data-workflow-latest-action-reason")

    assert scalar_presentation["header"]["status"]["text"] == "true"
    assert scalar_presentation["message"]["text"] == ""

    assert scalar_presentation["details"]["rows"] == [
             detail_row("action", "Action", "false")
           ]
  end

  defp latest_action_presentation(html) do
    vue =
      LiveVue.Test.get_vue(html,
        id: "dashboard-historical-workflow-latest-action-component"
      )

    assert vue.component == "HistoricalWorkflowLatestAction"
    assert vue.id == "dashboard-historical-workflow-latest-action-component"
    assert vue.ssr == false
    assert vue.class == "contents"
    assert vue.handlers == %{}
    assert Map.keys(vue.props) == ["presentation"]
    assert vue.props == Jason.decode!(Jason.encode!(vue.props))

    Map.fetch!(vue.props, "presentation")
  end

  defp detail_row(key, label, value) do
    %{
      "key" => key,
      "label" => %{"class" => "text-base-content/60", "text" => label},
      "value" => %{"class" => "font-mono break-all", "text" => value}
    }
  end

  defp review_href_query(href) do
    href
    |> URI.parse()
    |> Map.fetch!(:query)
    |> URI.decode_query()
  end
end
