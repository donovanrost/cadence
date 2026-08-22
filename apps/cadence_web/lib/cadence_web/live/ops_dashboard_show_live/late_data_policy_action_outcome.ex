defmodule CadenceWeb.OpsDashboardShowLive.LateDataPolicyActionOutcome do
  @moduledoc false

  @type t :: %__MODULE__{
          action: :late_data_policy,
          status: :ok | :error | :blocked,
          kind: :info | :error,
          reason: String.t(),
          decision: String.t() | nil,
          execution_mode: String.t() | nil,
          dashboard_time_mode: String.t() | nil,
          dashboard_replay_run_id: String.t() | nil,
          dashboard_data_view: String.t() | nil,
          dashboard_limit_mode: String.t() | nil,
          result_event_id: String.t() | nil,
          target_event_id: String.t() | nil,
          target_run_id: String.t() | nil,
          error: term(),
          message: String.t()
        }

  defstruct action: :late_data_policy,
            status: :ok,
            kind: :info,
            reason: "late_data_policy_applied",
            decision: nil,
            execution_mode: nil,
            dashboard_time_mode: nil,
            dashboard_replay_run_id: nil,
            dashboard_data_view: nil,
            dashboard_limit_mode: nil,
            result_event_id: nil,
            target_event_id: nil,
            target_run_id: nil,
            error: nil,
            message: "Late-data policy applied."

  @spec new(keyword() | map()) :: t()
  def new(attrs) when is_list(attrs), do: attrs |> Map.new() |> new()
  def new(attrs) when is_map(attrs), do: struct(__MODULE__, attrs)
end
