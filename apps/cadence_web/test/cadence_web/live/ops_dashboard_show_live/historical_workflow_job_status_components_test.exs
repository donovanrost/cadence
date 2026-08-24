defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowJobStatusComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowJobStatusComponents

  test "job_status renders guidance, review links, and retry action metadata" do
    html =
      render_component(&HistoricalWorkflowJobStatusComponents.job_status/1,
        workflow_context: workflow_context(),
        workflow_controls: workflow_controls(),
        dashboard_current_path:
          "/missions/mission-1/ops/dashboards/dashboard-1?scope_kind=mission&scope_id=mission-1&panel=data_link"
      )

    presentation = job_status_presentation(html)
    root = presentation["root"]
    guidance = presentation["guidance"]
    review_origin = presentation["review_origin"]
    retry_button = presentation["retry_button"]

    assert root["attrs"]["data-historical-workflow-job-id"] == "job-1"

    assert root["attrs"]["data-historical-workflow-job-next-action"] == "retry_job"

    assert guidance["attrs"]["data-historical-workflow-job-guidance-retry-eligible"] ==
             "true"

    assert guidance["attrs"]["data-historical-workflow-job-guidance-correction-reason"] ==
             "correction_not_required"

    assert String.contains?(guidance["guidance"]["text"], "Retry job job-1.")

    job_review_href = review_origin["review_link"]["href"]

    assert review_href_query(job_review_href) == %{
             "scope_kind" => "mission",
             "scope_id" => "mission-1",
             "panel" => "versions",
             "activity_filter" => "open_comparison_reviews",
             "activity_event" => "review-request-1"
           }

    assert Enum.map(review_origin["placements"]["links"], & &1["text"]) == [
             "placement-1",
             "placement-2"
           ]

    assert Enum.any?(
             presentation["details"]["rows"],
             &(&1["value"]["text"] == "dispatcher unavailable")
           )

    assert retry_button["attrs"]["phx-click"] == "retry_historical_workflow_job"

    assert retry_button["attrs"]["phx-value-job-id"] == "job-1"

    assert root == %{
             "id" => "dashboard-historical-workflow-job-status",
             "class" => "rounded border p-2 text-xs border-error/30 bg-error/10",
             "attrs" => %{
               "data-historical-workflow-job-id" => "job-1",
               "data-historical-workflow-job-status" => "failed",
               "data-historical-workflow-job-comparison-review-request" => "review-request-1",
               "data-historical-workflow-job-comparison-review-kind" =>
                 "comparison_open_findings_review",
               "data-historical-workflow-job-comparison-review-open-count" => "2",
               "data-historical-workflow-job-comparison-review-placements" =>
                 "placement-1,placement-2",
               "data-historical-workflow-job-next-action" => "retry_job"
             }
           }

    assert presentation["header"] == %{
             "class" => "flex items-center justify-between gap-2",
             "label" => %{"class" => "hud-label", "text" => "Workflow Job"},
             "status" => %{
               "class" => "font-mono uppercase tracking-normal",
               "text" => "failed"
             }
           }

    assert guidance["attrs"] == %{
             "data-historical-workflow-job-guidance-next-action" => "retry_job",
             "data-historical-workflow-job-guidance-retry-eligible" => "true",
             "data-historical-workflow-job-guidance-retry-reason" => "failed_job_retryable",
             "data-historical-workflow-job-guidance-retry-preview" => "Retry job job-1.",
             "data-historical-workflow-job-guidance-retry-explanation" =>
               "This failed workflow job can be retried.",
             "data-historical-workflow-job-guidance-retry-state" =>
               "job job-1; status failed; retryable true; recovery retry_job",
             "data-historical-workflow-job-guidance-correction-eligible" => "false",
             "data-historical-workflow-job-guidance-correction-reason" =>
               "correction_not_required",
             "data-historical-workflow-job-guidance-correction-preview" =>
               "Correction request is not currently eligible",
             "data-historical-workflow-job-guidance-correction-explanation" =>
               "This failure does not require a corrected workflow request.",
             "data-historical-workflow-job-guidance-correction-state" =>
               "job job-1; status failed; retryable true; recovery retry_job",
             "data-historical-workflow-job-guidance-correction-available-when" =>
               "Correction becomes available when the failure recovery action requires a corrected request.",
             "data-historical-workflow-job-guidance-active-state" => "failed"
           }

    assert Map.delete(guidance, "attrs") == %{
             "id" => "dashboard-historical-workflow-job-guidance",
             "class" => "mt-2 rounded border border-base-300/60 bg-base-100/70 p-2",
             "header" => %{
               "class" => "flex items-center justify-between gap-2",
               "label" => %{"class" => "hud-label", "text" => "Job Guidance"},
               "next_action" => %{
                 "class" => "font-mono text-base-content/70",
                 "text" => "retry_job"
               }
             },
             "guidance" => %{
               "class" => "mt-1 text-base-content/75",
               "text" => "Retry job job-1."
             },
             "policy_state" => %{
               "visible" => true,
               "class" => "mt-1 font-mono text-base-content/65",
               "text" => "job job-1; status failed; retryable true; recovery retry_job"
             },
             "available_when" => %{
               "visible" => true,
               "class" => "mt-1 text-base-content/60",
               "text" =>
                 "Correction becomes available when the failure recovery action requires a corrected request."
             }
           }

    assert review_origin["attrs"] == %{
             "data-historical-workflow-job-review-origin-request" => "review-request-1",
             "data-historical-workflow-job-review-origin-kind" =>
               "comparison_open_findings_review",
             "data-historical-workflow-job-review-origin-open-count" => "2",
             "data-historical-workflow-job-review-origin-placements" => "placement-1,placement-2",
             "data-historical-workflow-job-review-origin-placement-count" => "2"
           }

    assert Map.take(review_origin, ["visible", "id", "class", "header"]) == %{
             "visible" => true,
             "id" => "dashboard-historical-workflow-job-review-origin",
             "class" => "mt-2 space-y-2 rounded border border-info/40 bg-info/10 p-2",
             "header" => %{
               "class" => "flex items-center justify-between gap-2",
               "label" => %{"class" => "hud-label", "text" => "Review Origin"}
             }
           }

    assert Map.drop(review_origin["review_link"], ["href"]) == %{
             "navigation_kind" => "patch",
             "class" =>
               "inline-flex items-center gap-1 font-mono text-primary hover:text-primary-focus",
             "text" => "Open review",
             "icon" => %{
               "name" => "hero-arrow-top-right-on-square",
               "class" => "h-3 w-3"
             },
             "attrs" => %{
               "data-historical-workflow-job-review-origin-link" => "review-request-1",
               "data-historical-workflow-job-review-origin-href" => job_review_href,
               "data-phx-link" => "patch",
               "data-phx-link-state" => "push"
             }
           }

    placement_links = review_origin["placements"]["links"]
    [placement_1_href, placement_2_href] = Enum.map(placement_links, & &1["href"])

    assert Enum.map([placement_1_href, placement_2_href], &review_href_query/1) == [
             %{
               "scope_kind" => "mission",
               "scope_id" => "mission-1",
               "panel" => "versions",
               "activity_filter" => "open_comparison_reviews",
               "activity_event" => "review-request-1",
               "selected_placement" => "placement-1"
             },
             %{
               "scope_kind" => "mission",
               "scope_id" => "mission-1",
               "panel" => "versions",
               "activity_filter" => "open_comparison_reviews",
               "activity_event" => "review-request-1",
               "selected_placement" => "placement-2"
             }
           ]

    assert review_origin["placements"] == %{
             "visible" => true,
             "class" => "flex flex-wrap gap-1",
             "attrs" => %{
               "data-historical-workflow-job-review-origin-placement-count" => "2"
             },
             "links" => [
               %{
                 "key" => "historical-workflow-job-review-placement-0",
                 "href" => placement_1_href,
                 "navigation_kind" => "patch",
                 "class" => "badge badge-xs badge-outline",
                 "text" => "placement-1",
                 "attrs" => %{
                   "data-historical-workflow-job-review-origin-placement" => "placement-1",
                   "data-historical-workflow-job-review-origin-placement-href" =>
                     placement_1_href,
                   "data-phx-link" => "patch",
                   "data-phx-link-state" => "push"
                 }
               },
               %{
                 "key" => "historical-workflow-job-review-placement-1",
                 "href" => placement_2_href,
                 "navigation_kind" => "patch",
                 "class" => "badge badge-xs badge-outline",
                 "text" => "placement-2",
                 "attrs" => %{
                   "data-historical-workflow-job-review-origin-placement" => "placement-2",
                   "data-historical-workflow-job-review-origin-placement-href" =>
                     placement_2_href,
                   "data-phx-link" => "patch",
                   "data-phx-link-state" => "push"
                 }
               }
             ]
           }

    assert presentation["details"] == %{
             "class" => "mt-1 grid grid-cols-[5rem_minmax(0,1fr)] gap-x-2 gap-y-1",
             "rows" => [
               detail_row("job", "Job", "job-1", "font-mono break-all"),
               detail_row("attempts", "Attempts", "1", "font-mono"),
               detail_row(
                 "failure",
                 "Failure",
                 "dispatcher unavailable",
                 "font-mono break-all"
               ),
               detail_row(
                 "failure-code",
                 "Failure code",
                 "dispatcher_down",
                 "font-mono break-all"
               ),
               detail_row("retryable", "Retryable", "true", "font-mono"),
               detail_row(
                 "recovery",
                 "Recovery",
                 "retry_job",
                 "font-mono break-all"
               )
             ]
           }

    assert retry_button == %{
             "visible" => true,
             "id" => "dashboard-historical-workflow-retry-job",
             "type" => "button",
             "class" => "btn btn-xs btn-error btn-outline mt-2",
             "text" => "Retry job",
             "icon" => %{"name" => "hero-arrow-path", "class" => "size-3"},
             "attrs" => %{
               "phx-click" => "retry_historical_workflow_job",
               "phx-value-job-id" => "job-1",
               "phx-value-event-id" => "source-event-1",
               "data-workflow-action-id" => "retry-job",
               "data-workflow-action-eligible" => "true",
               "data-workflow-action-reason" => "failed_job_retryable",
               "data-workflow-action-preview" => "Retry job job-1."
             }
           }

    refute presentation["stale_actions"]["visible"]
    refute presentation["missing_actions"]["visible"]
  end

  test "job_status renders no job card when job status is disabled" do
    for job_status <- [false, nil] do
      html =
        render_component(&HistoricalWorkflowJobStatusComponents.job_status/1,
          workflow_context: workflow_context(),
          workflow_controls: %{workflow_controls() | job_status: job_status},
          dashboard_current_path: "/missions/mission-1/ops/dashboards/dashboard-1"
        )

      document = LazyHTML.from_fragment(html)

      assert [] =
               document
               |> LazyHTML.query("#dashboard-historical-workflow-job-status")
               |> LazyHTML.attribute("id")

      assert [] =
               document
               |> LazyHTML.query("#dashboard-historical-workflow-job-status-component")
               |> LazyHTML.attribute("id")
    end
  end

  test "job_status renders stale active-job guidance metadata" do
    html =
      render_component(&HistoricalWorkflowJobStatusComponents.job_status/1,
        workflow_context:
          Map.merge(workflow_context(), %{
            job_status: "running",
            run_id: "run-stale-replacement",
            job_started_at: "2026-06-22T10:01:00Z",
            stale_replacement_job_age_seconds: "1200",
            stale_replacement_stale_after_seconds: "900"
          }),
        workflow_controls: %{
          workflow_controls()
          | job_retryable: false,
            job_retry_action: %{eligible?: false},
            correction_request_action: %{eligible?: false}
        },
        dashboard_current_path: "/missions/mission-1/ops/dashboards/dashboard-1"
      )

    presentation = job_status_presentation(html)
    root = presentation["root"]
    guidance = presentation["guidance"]
    stale_actions = presentation["stale_actions"]
    [inspect_button, requeue_button] = stale_actions["buttons"]

    assert root["attrs"]["data-historical-workflow-job-next-action"] ==
             "inspect_stale_job"

    assert guidance["attrs"]["data-historical-workflow-job-guidance-active-state"] == "stale"

    assert guidance["attrs"]["data-historical-workflow-job-guidance-started-at"] ==
             "2026-06-22T10:01:00Z"

    assert guidance["attrs"]["data-historical-workflow-job-guidance-age-seconds"] == "1200"

    assert guidance["attrs"]["data-historical-workflow-job-guidance-stale-after-seconds"] ==
             "900"

    assert String.contains?(guidance["guidance"]["text"], "crossed the stale threshold")

    assert stale_actions["attrs"]["data-workflow-action-scope"] == "job_status"

    assert stale_actions["attrs"]["data-workflow-action-job-id"] == "job-1"

    assert stale_actions["attrs"]["data-workflow-action-event-id"] == "source-event-1"

    assert inspect_button["attrs"]["phx-click"] ==
             "inspect_stale_historical_workflow_replacement_job"

    assert inspect_button["attrs"]["data-workflow-action-id"] ==
             "inspect_stale_replacement_job"

    assert inspect_button["attrs"]["phx-value-replacement-run-id"] ==
             "run-stale-replacement"

    assert inspect_button["attrs"]["data-workflow-action-replacement-run"] ==
             "run-stale-replacement"

    assert requeue_button["attrs"]["phx-click"] ==
             "requeue_stale_historical_workflow_replacement_job"

    assert requeue_button["attrs"]["data-workflow-action-id"] ==
             "requeue_stale_replacement_job"

    assert requeue_button["attrs"]["phx-value-replacement-run-id"] ==
             "run-stale-replacement"

    assert requeue_button["attrs"]["data-workflow-action-replacement-run"] ==
             "run-stale-replacement"

    assert Map.drop(stale_actions, ["buttons"]) == %{
             "visible" => true,
             "id" => "dashboard-historical-workflow-stale-job-actions",
             "class" => "mt-2 flex flex-wrap gap-2",
             "attrs" => %{
               "data-workflow-action-scope" => "job_status",
               "data-workflow-action-job-id" => "job-1",
               "data-workflow-action-event-id" => "source-event-1",
               "data-workflow-action-job-started" => "2026-06-22T10:01:00Z",
               "data-workflow-action-job-age-seconds" => "1200",
               "data-workflow-action-job-stale-after-seconds" => "900"
             }
           }

    assert stale_actions["buttons"] == [
             %{
               "id" => "dashboard-historical-workflow-stale-job-inspect",
               "type" => "button",
               "class" => "btn btn-xs btn-warning btn-outline",
               "text" => "Inspect stale job",
               "icon" => %{"name" => "hero-magnifying-glass", "class" => "size-3"},
               "attrs" => %{
                 "phx-click" => "inspect_stale_historical_workflow_replacement_job",
                 "phx-value-job-id" => "job-1",
                 "phx-value-event-id" => "source-event-1",
                 "phx-value-replacement-run-id" => "run-stale-replacement",
                 "data-workflow-action-id" => "inspect_stale_replacement_job",
                 "data-workflow-action-job-id" => "job-1",
                 "data-workflow-action-event-id" => "source-event-1",
                 "data-workflow-action-replacement-run" => "run-stale-replacement",
                 "data-workflow-action-job-started" => "2026-06-22T10:01:00Z"
               }
             },
             %{
               "id" => "dashboard-historical-workflow-stale-job-requeue",
               "type" => "button",
               "class" => "btn btn-xs btn-warning",
               "text" => "Requeue stale job",
               "icon" => %{"name" => "hero-arrow-path", "class" => "size-3"},
               "attrs" => %{
                 "phx-click" => "requeue_stale_historical_workflow_replacement_job",
                 "phx-value-job-id" => "job-1",
                 "phx-value-event-id" => "source-event-1",
                 "phx-value-replacement-run-id" => "run-stale-replacement",
                 "data-workflow-action-id" => "requeue_stale_replacement_job",
                 "data-workflow-action-job-id" => "job-1",
                 "data-workflow-action-event-id" => "source-event-1",
                 "data-workflow-action-replacement-run" => "run-stale-replacement",
                 "data-workflow-action-job-started" => "2026-06-22T10:01:00Z"
               }
             }
           ]

    refute presentation["retry_button"]["visible"]
    refute presentation["missing_actions"]["visible"]
  end

  test "job_status renders missing replacement job inspection action metadata" do
    html =
      render_component(&HistoricalWorkflowJobStatusComponents.job_status/1,
        workflow_context:
          Map.merge(workflow_context(), %{
            job_status: "missing",
            request_group_id: "group-1",
            missing_replacement_run_id: "run-1-corrected",
            missing_replacement_expected_job_type: "telemetry_historical_data_workflow"
          }),
        workflow_controls: %{
          workflow_controls()
          | job_retryable: false,
            job_retry_action: %{eligible?: false},
            correction_request_action: %{eligible?: false}
        },
        dashboard_current_path: "/missions/mission-1/ops/dashboards/dashboard-1"
      )

    presentation = job_status_presentation(html)
    root = presentation["root"]
    guidance = presentation["guidance"]
    missing_actions = presentation["missing_actions"]
    [inspect_button] = missing_actions["buttons"]

    assert root["attrs"]["data-historical-workflow-job-next-action"] ==
             "inspect_missing_job"

    assert guidance["attrs"]["data-historical-workflow-job-guidance-active-state"] ==
             "missing"

    assert String.contains?(
             guidance["guidance"]["text"],
             "replacement workflow job is missing"
           )

    assert missing_actions["attrs"]["data-workflow-action-scope"] == "job_status"

    assert missing_actions["attrs"]["data-workflow-action-request-group-id"] == "group-1"

    assert missing_actions["attrs"]["data-workflow-action-replacement-run"] ==
             "run-1-corrected"

    assert missing_actions["attrs"]["data-workflow-action-expected-job-type"] ==
             "telemetry_historical_data_workflow"

    assert inspect_button["attrs"]["phx-click"] ==
             "inspect_missing_historical_workflow_replacement_job"

    assert inspect_button["attrs"]["phx-value-request-group-id"] == "group-1"

    assert inspect_button["attrs"]["phx-value-replacement-run-id"] ==
             "run-1-corrected"

    assert inspect_button["attrs"]["data-workflow-action-id"] ==
             "inspect_missing_replacement_job"

    assert Map.drop(missing_actions, ["buttons"]) == %{
             "visible" => true,
             "id" => "dashboard-historical-workflow-missing-job-actions",
             "class" => "mt-2 flex flex-wrap gap-2",
             "attrs" => %{
               "data-workflow-action-scope" => "job_status",
               "data-workflow-action-request-group-id" => "group-1",
               "data-workflow-action-replacement-run" => "run-1-corrected",
               "data-workflow-action-expected-job-type" => "telemetry_historical_data_workflow"
             }
           }

    assert missing_actions["buttons"] == [
             %{
               "id" => "dashboard-historical-workflow-missing-job-inspect",
               "type" => "button",
               "class" => "btn btn-xs btn-warning btn-outline",
               "text" => "Inspect missing job",
               "icon" => %{"name" => "hero-magnifying-glass", "class" => "size-3"},
               "attrs" => %{
                 "phx-click" => "inspect_missing_historical_workflow_replacement_job",
                 "phx-value-request-group-id" => "group-1",
                 "phx-value-replacement-run-id" => "run-1-corrected",
                 "data-workflow-action-id" => "inspect_missing_replacement_job",
                 "data-workflow-action-request-group-id" => "group-1",
                 "data-workflow-action-replacement-run" => "run-1-corrected",
                 "data-workflow-action-expected-job-type" => "telemetry_historical_data_workflow"
               }
             }
           ]

    refute presentation["retry_button"]["visible"]
    refute presentation["stale_actions"]["visible"]
  end

  test "job_status preserves raw HEEx value and server visibility semantics" do
    controls = semantic_workflow_controls()

    presentations =
      Enum.map([nil, false, true, "", 7], fn job_id ->
        render_component(&HistoricalWorkflowJobStatusComponents.job_status/1,
          workflow_context: %{workflow_context() | job_id: job_id},
          workflow_controls: controls,
          dashboard_current_path: nil
        )
        |> job_status_presentation()
      end)

    assert Enum.map(presentations, fn presentation ->
             Map.has_key?(
               presentation["root"]["attrs"],
               "data-historical-workflow-job-id"
             )
           end) == [false, false, true, true, true]

    assert Enum.map(
             presentations,
             &Map.get(&1["root"]["attrs"], "data-historical-workflow-job-id")
           ) == [nil, nil, "", "", "7"]

    assert Enum.map(presentations, fn presentation ->
             presentation["details"]["rows"]
             |> List.first()
             |> get_in(["value", "text"])
           end) == ["", "false", "true", "", "7"]

    first_presentation = List.first(presentations)

    assert first_presentation["guidance"]["policy_state"] == %{
             "visible" => false,
             "class" => "mt-1 font-mono text-base-content/65",
             "text" => "true"
           }

    assert first_presentation["guidance"]["available_when"] == %{
             "visible" => false,
             "class" => "mt-1 text-base-content/60",
             "text" => "7"
           }

    assert first_presentation["review_origin"]["visible"] == false

    assert first_presentation["review_origin"]["placements"] == %{
             "visible" => false,
             "class" => "flex flex-wrap gap-1",
             "attrs" => %{
               "data-historical-workflow-job-review-origin-placement-count" => "0"
             },
             "links" => []
           }

    detail_visibility_presentation =
      render_component(&HistoricalWorkflowJobStatusComponents.job_status/1,
        workflow_context:
          Map.merge(workflow_context(), %{
            job_attempts: true,
            job_failure: 7,
            failure_code: "",
            retryable: false,
            recovery_action: nil,
            retry_blockers: "blocked"
          }),
        workflow_controls: controls,
        dashboard_current_path: nil
      )
      |> job_status_presentation()

    assert Enum.map(
             detail_visibility_presentation["details"]["rows"],
             & &1["label"]["text"]
           ) == ["Job", "Blockers"]

    assert Enum.map(
             detail_visibility_presentation["details"]["rows"],
             & &1["value"]["text"]
           ) == ["job-1", "blocked"]
  end

  defp workflow_context do
    %{
      event_id: "source-event-1",
      job_id: "job-1",
      job_status: "failed",
      job_attempts: "1",
      job_failure: "dispatcher unavailable",
      failure_code: "dispatcher_down",
      retryable: "true",
      recovery_action: "retry_job",
      retry_blockers: "",
      comparison_review_request_event_id: "review-request-1",
      comparison_review_request_kind: "comparison_open_findings_review",
      comparison_review_open_count: "2",
      comparison_review_open_placement_ids: "placement-1,placement-2"
    }
  end

  defp workflow_controls do
    %{
      job_status: true,
      job_status_class: "border-error/30 bg-error/10",
      job_retryable: true,
      job_retry_action: %{
        id: "retry-job",
        eligible?: true,
        reason: "failed_job_retryable",
        preview: "Retry job job-1.",
        explanation: "This failed workflow job can be retried.",
        state_summary: "job job-1; status failed; retryable true; recovery retry_job"
      },
      correction_request_action: %{
        id: "correction-request",
        eligible?: false,
        reason: "correction_not_required",
        preview: "Correction request is not currently eligible",
        explanation: "This failure does not require a corrected workflow request.",
        state_summary: "job job-1; status failed; retryable true; recovery retry_job",
        available_when:
          "Correction becomes available when the failure recovery action requires a corrected request."
      }
    }
  end

  defp semantic_workflow_controls do
    controls = workflow_controls()

    %{
      controls
      | job_retryable: false,
        job_retry_action:
          Map.merge(controls.job_retry_action, %{
            eligible?: false,
            state_summary: true,
            available_when: 7
          }),
        correction_request_action: %{eligible?: false}
    }
  end

  defp job_status_presentation(html) do
    vue =
      LiveVue.Test.get_vue(html,
        id: "dashboard-historical-workflow-job-status-component"
      )

    assert vue.component == "HistoricalWorkflowJobStatus"
    assert vue.id == "dashboard-historical-workflow-job-status-component"
    assert vue.ssr == false
    assert vue.class == "contents"
    assert vue.handlers == %{}
    assert Map.keys(vue.props) == ["presentation"]
    assert vue.props == Jason.decode!(Jason.encode!(vue.props))

    Map.fetch!(vue.props, "presentation")
  end

  defp detail_row(key, label, value, value_class) do
    %{
      "key" => key,
      "label" => %{"class" => "text-base-content/60", "text" => label},
      "value" => %{"class" => value_class, "text" => value}
    }
  end

  defp review_href_query(href) do
    href
    |> URI.parse()
    |> Map.fetch!(:query)
    |> URI.decode_query()
  end
end