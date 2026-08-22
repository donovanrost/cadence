defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowActionOutcome do
  @moduledoc false

  @type t :: %__MODULE__{
          action: atom() | String.t() | nil,
          status: atom() | String.t() | nil,
          kind: atom() | String.t() | nil,
          reason: atom() | String.t() | nil,
          stage: String.t() | nil,
          request_group_id: String.t() | nil,
          job_id: String.t() | nil,
          count: non_neg_integer() | String.t() | nil,
          retried: non_neg_integer() | String.t() | nil,
          retry_nonretryable: non_neg_integer() | String.t() | nil,
          retry_skipped: non_neg_integer() | String.t() | nil,
          retry_errors: non_neg_integer() | String.t() | nil,
          retry_scope: String.t() | nil,
          retry_run_ids: String.t() | nil,
          retry_nonretryable_run_ids: String.t() | nil,
          retry_nonretryable_event_ids: String.t() | nil,
          retry_nonretryable_items: String.t() | nil,
          retry_skipped_run_ids: String.t() | nil,
          retry_skipped_event_ids: String.t() | nil,
          retry_skipped_items: String.t() | nil,
          retry_error_run_ids: String.t() | nil,
          retry_error_event_ids: String.t() | nil,
          retry_error_items: String.t() | nil,
          queued_jobs: non_neg_integer() | String.t() | nil,
          failed_jobs: non_neg_integer() | String.t() | nil,
          result_event_ids: String.t() | nil,
          target_event_id: String.t() | nil,
          target_run_id: String.t() | nil,
          dashboard_context: map(),
          error: term(),
          message: String.t() | nil
        }

  defstruct [
    :action,
    :status,
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
    :retry_nonretryable_run_ids,
    :retry_nonretryable_event_ids,
    :retry_nonretryable_items,
    :retry_skipped_run_ids,
    :retry_skipped_event_ids,
    :retry_skipped_items,
    :retry_error_run_ids,
    :retry_error_event_ids,
    :retry_error_items,
    :queued_jobs,
    :failed_jobs,
    :result_event_ids,
    :target_event_id,
    :target_run_id,
    :error,
    :message,
    dashboard_context: %{}
  ]

  @spec new(keyword() | map()) :: t()
  def new(attrs) when is_list(attrs), do: attrs |> Map.new() |> new()

  def new(attrs) when is_map(attrs) do
    struct(__MODULE__, attrs)
  end
end
