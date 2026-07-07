defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowActionOutcomePresentation do
  @moduledoc false

  @type t :: %__MODULE__{
          action: String.t() | nil,
          action_label: String.t() | nil,
          status: String.t(),
          status_label: String.t(),
          kind: String.t() | nil,
          reason: String.t() | nil,
          stage: String.t() | nil,
          request_group_id: String.t() | nil,
          job_id: String.t() | nil,
          count: String.t() | nil,
          retried: String.t() | nil,
          retry_nonretryable: String.t() | nil,
          retry_skipped: String.t() | nil,
          retry_errors: String.t() | nil,
          retry_scope: String.t() | nil,
          retry_run_ids: String.t() | nil,
          retry_disposition: map(),
          retry_error_run_ids: String.t() | nil,
          retry_error_event_ids: String.t() | nil,
          retry_error_items: String.t() | nil,
          queued_jobs: String.t() | nil,
          failed_jobs: String.t() | nil,
          result_event_ids: String.t() | nil,
          target_event_id: String.t() | nil,
          target_run_id: String.t() | nil,
          dashboard_context: map(),
          message: String.t() | nil,
          class: String.t(),
          badge_class: String.t()
        }

  defstruct [
    :action,
    :action_label,
    :kind,
    :reason,
    :stage,
    :request_group_id,
    :job_id,
    :count,
    :retried,
    :retry_nonretryable,
    :retry_skipped,
    :retry_errors,
    :retry_scope,
    :retry_run_ids,
    :retry_disposition,
    :retry_error_run_ids,
    :retry_error_event_ids,
    :retry_error_items,
    :queued_jobs,
    :failed_jobs,
    :result_event_ids,
    :target_event_id,
    :target_run_id,
    :message,
    dashboard_context: %{},
    status: "unknown",
    status_label: "unknown",
    class: "border-base-300/70 bg-base-100/60 text-base-content",
    badge_class: "badge-ghost"
  ]

  @stable_attr_fields [
    {:action, ""},
    {:status, "status"},
    {:kind, "kind"},
    {:reason, "reason"},
    {:stage, "stage"},
    {:request_group_id, "request-group-id"},
    {:job_id, "job-id"},
    {:count, "count"},
    {:retried, "retried"},
    {:retry_nonretryable, "retry-nonretryable"},
    {:retry_skipped, "retry-skipped"},
    {:retry_errors, "retry-errors"},
    {:retry_scope, "retry-scope"},
    {:retry_run_ids, "retry-run-ids"},
    {:retry_nonretryable_run_ids, "retry-nonretryable-run-ids"},
    {:retry_nonretryable_event_ids, "retry-nonretryable-event-ids"},
    {:retry_nonretryable_items, "retry-nonretryable-items"},
    {:retry_skipped_run_ids, "retry-skipped-run-ids"},
    {:retry_skipped_event_ids, "retry-skipped-event-ids"},
    {:retry_skipped_items, "retry-skipped-items"},
    {:retry_error_run_ids, "retry-error-run-ids"},
    {:retry_error_event_ids, "retry-error-event-ids"},
    {:retry_error_items, "retry-error-items"},
    {:queued_jobs, "queued-jobs"},
    {:failed_jobs, "failed-jobs"},
    {:result_event_ids, "result-event-ids"},
    {:target_event_id, "target-event-id"},
    {:target_run_id, "target-run-id"},
    {:dashboard_id, "dashboard-id"},
    {:dashboard_version, "dashboard-version"},
    {:dashboard_time_mode, "dashboard-time-mode"},
    {:dashboard_replay_run_id, "dashboard-replay-run-id"},
    {:dashboard_data_view, "dashboard-data-view"},
    {:dashboard_limit_mode, "dashboard-limit-mode"}
  ]

  @dashboard_context_fields [
    :dashboard_id,
    :dashboard_version,
    :dashboard_time_mode,
    :dashboard_replay_run_id,
    :dashboard_data_view,
    :dashboard_limit_mode
  ]

  @spec normalize(map() | term()) :: t()
  def normalize(attrs) when is_map(attrs) do
    status = text_value(Map.get(attrs, :status)) || "unknown"

    %__MODULE__{
      action: text_value(Map.get(attrs, :action)),
      action_label: text_value(Map.get(attrs, :action_label)),
      status: status,
      status_label: text_value(Map.get(attrs, :status_label)) || status,
      kind: text_value(Map.get(attrs, :kind)),
      reason: text_value(Map.get(attrs, :reason)),
      stage: text_value(Map.get(attrs, :stage)),
      request_group_id: text_value(Map.get(attrs, :request_group_id)),
      job_id: text_value(Map.get(attrs, :job_id)),
      count: text_value(Map.get(attrs, :count)),
      retried: text_value(Map.get(attrs, :retried)),
      retry_nonretryable: text_value(Map.get(attrs, :retry_nonretryable)),
      retry_skipped: text_value(Map.get(attrs, :retry_skipped)),
      retry_errors: text_value(Map.get(attrs, :retry_errors)),
      retry_scope: text_value(Map.get(attrs, :retry_scope)),
      retry_run_ids: text_value(Map.get(attrs, :retry_run_ids)),
      retry_disposition: retry_disposition(attrs),
      retry_error_run_ids: text_value(Map.get(attrs, :retry_error_run_ids)),
      retry_error_event_ids: text_value(Map.get(attrs, :retry_error_event_ids)),
      retry_error_items: text_value(Map.get(attrs, :retry_error_items)),
      queued_jobs: text_value(Map.get(attrs, :queued_jobs)),
      failed_jobs: text_value(Map.get(attrs, :failed_jobs)),
      result_event_ids: text_value(Map.get(attrs, :result_event_ids)),
      target_event_id: text_value(Map.get(attrs, :target_event_id)),
      target_run_id: text_value(Map.get(attrs, :target_run_id)),
      dashboard_context: dashboard_context(attrs),
      message: text_value(Map.get(attrs, :message)),
      class:
        text_value(Map.get(attrs, :class)) ||
          "border-base-300/70 bg-base-100/60 text-base-content",
      badge_class: text_value(Map.get(attrs, :badge_class)) || "badge-ghost"
    }
  end

  def normalize(_attrs), do: %__MODULE__{}

  @spec stable_attrs(t() | map() | nil, String.t(), keyword()) :: map()
  def stable_attrs(outcome, prefix \\ "data-workflow-latest-action", opts \\ [])

  def stable_attrs(nil, _prefix, _opts), do: %{}

  def stable_attrs(%__MODULE__{} = presentation, prefix, opts) when is_binary(prefix) do
    stable_attrs_for_presentation(presentation, prefix, opts)
  end

  def stable_attrs(outcome, prefix, opts) when is_binary(prefix) do
    outcome
    |> normalize()
    |> stable_attrs_for_presentation(prefix, opts)
  end

  defp stable_attrs_for_presentation(%__MODULE__{} = presentation, prefix, opts) do
    @stable_attr_fields
    |> Enum.reduce(%{}, fn {field, suffix}, attrs ->
      put_attr(attrs, attr_name(prefix, suffix), stable_value(presentation, field))
    end)
    |> put_attr("#{prefix}-handoff-count", Keyword.get(opts, :handoff_count))
    |> put_attr("#{prefix}-primary-result-event-id", Keyword.get(opts, :primary_result_event_id))
  end

  defp text_value(nil), do: nil
  defp text_value(value) when is_atom(value), do: Atom.to_string(value)
  defp text_value(value) when is_integer(value), do: Integer.to_string(value)
  defp text_value(value) when is_binary(value), do: value
  defp text_value(_value), do: nil

  defp stable_value(%__MODULE__{} = presentation, :retry_nonretryable_run_ids),
    do: retry_disposition_value(presentation, :nonretryable_run_ids)

  defp stable_value(%__MODULE__{} = presentation, :retry_nonretryable_event_ids),
    do: retry_disposition_value(presentation, :nonretryable_event_ids)

  defp stable_value(%__MODULE__{} = presentation, :retry_nonretryable_items),
    do: retry_disposition_value(presentation, :nonretryable_items)

  defp stable_value(%__MODULE__{} = presentation, :retry_skipped_run_ids),
    do: retry_disposition_value(presentation, :skipped_run_ids)

  defp stable_value(%__MODULE__{} = presentation, :retry_skipped_event_ids),
    do: retry_disposition_value(presentation, :skipped_event_ids)

  defp stable_value(%__MODULE__{} = presentation, :retry_skipped_items),
    do: retry_disposition_value(presentation, :skipped_items)

  defp stable_value(%__MODULE__{} = presentation, field)
       when field in [
              :dashboard_id,
              :dashboard_version,
              :dashboard_time_mode,
              :dashboard_replay_run_id,
              :dashboard_data_view,
              :dashboard_limit_mode
            ] do
    Map.get(presentation.dashboard_context, field)
  end

  defp stable_value(%__MODULE__{} = presentation, field), do: Map.get(presentation, field)

  defp attr_name(prefix, ""), do: prefix
  defp attr_name(prefix, suffix), do: "#{prefix}-#{suffix}"

  defp put_attr(attrs, _name, nil), do: attrs
  defp put_attr(attrs, _name, ""), do: attrs
  defp put_attr(attrs, name, value), do: Map.put(attrs, name, value)

  defp retry_disposition_value(%__MODULE__{retry_disposition: disposition}, key)
       when is_map(disposition) do
    Map.get(disposition, key)
  end

  defp retry_disposition_value(_presentation, _key), do: nil

  defp retry_disposition(attrs) when is_map(attrs) do
    case Map.get(attrs, :retry_disposition) do
      disposition when is_map(disposition) ->
        %{
          nonretryable_run_ids: text_value(Map.get(disposition, :nonretryable_run_ids)),
          nonretryable_event_ids: text_value(Map.get(disposition, :nonretryable_event_ids)),
          nonretryable_items: text_value(Map.get(disposition, :nonretryable_items)),
          skipped_run_ids: text_value(Map.get(disposition, :skipped_run_ids)),
          skipped_event_ids: text_value(Map.get(disposition, :skipped_event_ids)),
          skipped_items: text_value(Map.get(disposition, :skipped_items))
        }

      _other ->
        %{
          nonretryable_run_ids: text_value(Map.get(attrs, :retry_nonretryable_run_ids)),
          nonretryable_event_ids: text_value(Map.get(attrs, :retry_nonretryable_event_ids)),
          nonretryable_items: text_value(Map.get(attrs, :retry_nonretryable_items)),
          skipped_run_ids: text_value(Map.get(attrs, :retry_skipped_run_ids)),
          skipped_event_ids: text_value(Map.get(attrs, :retry_skipped_event_ids)),
          skipped_items: text_value(Map.get(attrs, :retry_skipped_items))
        }
    end
  end

  defp dashboard_context(attrs) when is_map(attrs) do
    source =
      case Map.get(attrs, :dashboard_context) || Map.get(attrs, "dashboard_context") do
        context when is_map(context) -> context
        _context -> attrs
      end

    @dashboard_context_fields
    |> Enum.map(fn field -> {field, text_value(context_value(source, field))} end)
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Map.new()
  end

  defp context_value(source, field) when is_map(source) and is_atom(field) do
    Map.get(source, field) || Map.get(source, Atom.to_string(field))
  end
end
