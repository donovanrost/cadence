defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowLatestActionComponents do
  @moduledoc false
  use CadenceWeb, :html

  alias CadenceWeb.OpsDashboardShowLive.DataLinkInspectorPanelPresentation
  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowActionOutcomePresentation
  alias CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowStatusNavigationPresentation

  attr :latest_action_outcome, :map, default: nil
  attr :dashboard_current_path, :string, default: nil

  def latest_action(%{latest_action_outcome: latest_action_outcome} = assigns)
      when latest_action_outcome in [nil, false],
      do: ~H""

  def latest_action(assigns) do
    assigns =
      assign(
        assigns,
        :presentation,
        presentation(
          assigns.latest_action_outcome,
          assigns.dashboard_current_path
        )
      )

    ~H"""
    <.vue
      id="dashboard-historical-workflow-latest-action-component"
      v-component="HistoricalWorkflowLatestAction"
      presentation={@presentation}
      v-ssr={false}
      class="contents"
    />
    """
  end

  def presentation(latest_action_outcome, _dashboard_current_path)
      when latest_action_outcome in [nil, false],
      do: nil

  def presentation(latest_action_outcome, dashboard_current_path) do
    latest_action_handoffs =
      HistoricalWorkflowStatusNavigationPresentation.latest_action_handoffs(
        latest_action_outcome,
        dashboard_current_path
      )

    latest_action_attrs =
      HistoricalWorkflowActionOutcomePresentation.stable_attrs(
        latest_action_outcome,
        "data-workflow-latest-action",
        handoff_count: length(latest_action_handoffs),
        primary_result_event_id:
          HistoricalWorkflowStatusNavigationPresentation.primary_handoff_event_id(
            latest_action_handoffs
          )
      )

    latest_action_dto(latest_action_outcome, latest_action_handoffs, latest_action_attrs)
  end

  defp latest_action_dto(latest_action_outcome, latest_action_handoffs, latest_action_attrs) do
    %{
      root: %{
        id: "dashboard-historical-workflow-latest-action",
        class:
          class_names([
            "rounded border p-2 text-xs",
            latest_action_outcome.class
          ]),
        attrs: raw_attrs(latest_action_attrs)
      },
      header: %{
        class: "flex items-center justify-between gap-2",
        label: %{class: "hud-label", text: "Last Action"},
        status: %{
          class: class_names(["badge badge-xs", latest_action_outcome.badge_class]),
          text: dom_text(latest_action_outcome.status_label)
        }
      },
      message: %{
        class: "mt-1 text-base-content/80",
        text: dom_text(latest_action_outcome.message)
      },
      details: latest_action_details_dto(latest_action_outcome),
      handoffs: latest_action_handoffs_dto(latest_action_handoffs)
    }
  end

  defp latest_action_details_dto(latest_action_outcome) do
    %{
      class: "mt-2 grid grid-cols-[5rem_minmax(0,1fr)] gap-x-2 gap-y-1",
      rows:
        [
          latest_action_detail_row("action", "Action", latest_action_outcome.action_label),
          optional_latest_action_detail_row(
            "reason",
            "Reason",
            latest_action_outcome.reason
          ),
          optional_latest_action_detail_row("stage", "Stage", latest_action_outcome.stage),
          optional_latest_action_detail_row(
            "group",
            "Group",
            latest_action_value(latest_action_outcome, :request_group_id)
          ),
          optional_latest_action_detail_row("job", "Job", latest_action_outcome.job_id),
          optional_latest_action_detail_row(
            "event",
            "Event",
            latest_action_outcome.target_event_id
          ),
          optional_latest_action_detail_row("run", "Run", latest_action_outcome.target_run_id),
          optional_latest_action_detail_row(
            "results",
            "Results",
            latest_action_outcome.result_event_ids
          ),
          optional_latest_action_detail_row("count", "Count", latest_action_outcome.count),
          optional_latest_action_detail_row("retried", "Retried", latest_action_outcome.retried),
          optional_latest_action_detail_row(
            "non-retry",
            "Non-retry",
            latest_action_outcome.retry_nonretryable
          ),
          optional_latest_action_detail_row(
            "skipped",
            "Skipped",
            latest_action_outcome.retry_skipped
          ),
          optional_latest_action_detail_row(
            "non-retry-runs",
            "Non-retry runs",
            retry_disposition(latest_action_outcome, :nonretryable_run_ids)
          ),
          optional_latest_action_detail_row(
            "non-retry-events",
            "Non-retry events",
            retry_disposition(latest_action_outcome, :nonretryable_event_ids)
          ),
          optional_latest_action_detail_row(
            "non-retry-items",
            "Non-retry items",
            retry_disposition(latest_action_outcome, :nonretryable_items)
          ),
          optional_latest_action_detail_row(
            "skipped-runs",
            "Skipped runs",
            retry_disposition(latest_action_outcome, :skipped_run_ids)
          ),
          optional_latest_action_detail_row(
            "skipped-events",
            "Skipped events",
            retry_disposition(latest_action_outcome, :skipped_event_ids)
          ),
          optional_latest_action_detail_row(
            "skipped-items",
            "Skipped items",
            retry_disposition(latest_action_outcome, :skipped_items)
          ),
          optional_latest_action_detail_row(
            "errors",
            "Errors",
            latest_action_outcome.retry_errors
          ),
          optional_latest_action_detail_row(
            "error-runs",
            "Error runs",
            latest_action_outcome.retry_error_run_ids
          ),
          optional_latest_action_detail_row(
            "error-events",
            "Error events",
            latest_action_outcome.retry_error_event_ids
          ),
          optional_latest_action_detail_row(
            "error-items",
            "Error items",
            latest_action_outcome.retry_error_items
          ),
          optional_latest_action_detail_row("scope", "Scope", latest_action_outcome.retry_scope),
          optional_latest_action_detail_row(
            "retry-runs",
            "Retry runs",
            latest_action_outcome.retry_run_ids
          ),
          optional_latest_action_detail_row(
            "queued",
            "Queued",
            latest_action_outcome.queued_jobs
          ),
          optional_latest_action_detail_row("failed", "Failed", latest_action_outcome.failed_jobs)
        ]
        |> Enum.reject(&is_nil/1)
    }
  end

  defp optional_latest_action_detail_row(key, label, value) do
    if DataLinkInspectorPanelPresentation.present_text?(value) do
      latest_action_detail_row(key, label, value)
    end
  end

  defp latest_action_detail_row(key, label, value) do
    %{
      key: key,
      label: %{class: "text-base-content/60", text: label},
      value: %{class: "font-mono break-all", text: dom_text(value)}
    }
  end

  defp latest_action_handoffs_dto(latest_action_handoffs) do
    %{
      visible: latest_action_handoffs != [],
      id: "dashboard-historical-workflow-latest-action-handoffs",
      class: "mt-2 space-y-2 rounded border border-base-300/60 bg-base-100/70 p-2",
      attrs:
        raw_attrs(%{
          "data-workflow-latest-action-handoff-count" => length(latest_action_handoffs),
          "data-workflow-latest-action-handoff-primary-event" =>
            HistoricalWorkflowStatusNavigationPresentation.primary_handoff_event_id(
              latest_action_handoffs
            )
        }),
      header: %{
        class: "flex items-center justify-between gap-2",
        label: %{class: "hud-label", text: "Result Handoff"},
        count: %{
          class: "font-mono text-base-content/70",
          text: dom_text(length(latest_action_handoffs))
        }
      },
      links_container: %{class: "flex flex-wrap gap-1"},
      links:
        latest_action_handoffs
        |> Enum.with_index()
        |> Enum.map(fn {handoff, index} -> latest_action_handoff_dto(handoff, index) end)
    }
  end

  defp latest_action_handoff_dto(handoff, index) do
    %{
      key: "historical-workflow-latest-action-handoff-#{index}",
      href: handoff.href,
      navigation_kind: "patch",
      class: "badge badge-xs badge-outline",
      text: dom_text(handoff.label),
      attrs:
        raw_attrs(%{
          "data-workflow-latest-action-handoff" => handoff.event_id,
          "data-workflow-latest-action-handoff-role" => handoff.role,
          "data-workflow-latest-action-handoff-label" => handoff.label,
          "data-workflow-latest-action-handoff-href" => handoff.href,
          "data-phx-link" => "patch",
          "data-phx-link-state" => "push"
        })
    }
  end

  defp class_names(values) do
    values
    |> Enum.reject(&(&1 in [nil, false]))
    |> Enum.map_join(" ", &dom_text/1)
  end

  defp raw_attrs(attrs) do
    Enum.reduce(attrs, %{}, fn
      {_name, value}, rendered when value in [nil, false] ->
        rendered

      {name, true}, rendered ->
        Map.put(rendered, name, "")

      {name, value}, rendered ->
        Map.put(rendered, name, dom_text(value))
    end)
  end

  defp dom_text(value), do: to_string(value)

  defp retry_disposition(%{retry_disposition: disposition}, key) when is_map(disposition) do
    Map.get(disposition, key)
  end

  defp retry_disposition(_latest_action_outcome, _key), do: nil

  defp latest_action_value(latest_action_outcome, key) when is_map(latest_action_outcome) do
    Map.get(latest_action_outcome, key)
  end
end
