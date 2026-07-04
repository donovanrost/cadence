defmodule CadenceWeb.OpsDashboardShowLive.LateDataPolicyEvents do
  @moduledoc false

  alias CadenceWeb.OpsDashboardShowLive.LateDataPolicy

  def record_decision(socket, params, opts \\ []) do
    # authz pending: Gate dashboard late-data policy mutations once RBAC exists.
    record_decision_fn(opts).(socket, params, opts)
  end

  defp record_decision_fn(opts),
    do: Keyword.get(opts, :record_late_data_policy_event, &LateDataPolicy.record_decision/3)
end
