defmodule CadenceWeb.OpsDashboardShowLive.RevisionDecisionEvents do
  @moduledoc false

  alias CadenceWeb.OpsDashboardShowLive.RevisionDecision

  def apply_decision(socket, params, opts \\ []) do
    # authz pending: Gate dashboard revision-decision mutations once RBAC exists.
    apply_decision_fn(opts).(socket, params, opts)
  end

  defp apply_decision_fn(opts),
    do: Keyword.get(opts, :apply_revision_decision_event, &RevisionDecision.apply_decision/3)
end
