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
    status: "unknown",
    status_label: "unknown",
    class: "border-base-300/70 bg-base-100/60 text-base-content",
    badge_class: "badge-ghost"
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
      message: text_value(Map.get(attrs, :message)),
      class:
        text_value(Map.get(attrs, :class)) ||
          "border-base-300/70 bg-base-100/60 text-base-content",
      badge_class: text_value(Map.get(attrs, :badge_class)) || "badge-ghost"
    }
  end

  def normalize(_attrs), do: %__MODULE__{}

  defp text_value(nil), do: nil
  defp text_value(value) when is_atom(value), do: Atom.to_string(value)
  defp text_value(value) when is_integer(value), do: Integer.to_string(value)
  defp text_value(value) when is_binary(value), do: value
  defp text_value(_value), do: nil

  defp retry_disposition(attrs) when is_map(attrs) do
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
