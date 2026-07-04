defmodule CadenceWeb.OpsDashboardShowLive.ComparisonReviewActionOutcome do
  @moduledoc false

  @type t :: %__MODULE__{
          action: :comparison_review_bulk_decision,
          status: :ok | :degraded | :error | :blocked,
          kind: :info | :warning | :error,
          reason: String.t(),
          decision: String.t() | nil,
          decision_reason: String.t() | nil,
          source_request_event_id: String.t() | nil,
          workflow_id: String.t() | nil,
          requested: non_neg_integer() | String.t() | nil,
          applied: non_neg_integer() | String.t() | nil,
          failed: non_neg_integer() | String.t() | nil,
          result_event_ids: String.t() | nil,
          target_event_id: String.t() | nil,
          error: term(),
          message: String.t()
        }

  defstruct action: :comparison_review_bulk_decision,
            status: :ok,
            kind: :info,
            reason: "comparison_review_bulk_decision_applied",
            decision: nil,
            decision_reason: nil,
            source_request_event_id: nil,
            workflow_id: nil,
            requested: nil,
            applied: nil,
            failed: nil,
            result_event_ids: nil,
            target_event_id: nil,
            error: nil,
            message: "Comparison review decisions applied."

  @spec new(keyword() | map()) :: t()
  def new(attrs) when is_list(attrs), do: attrs |> Map.new() |> new()
  def new(attrs) when is_map(attrs), do: struct(__MODULE__, attrs)
end
