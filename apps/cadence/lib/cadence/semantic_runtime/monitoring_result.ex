defmodule Cadence.SemanticRuntime.MonitoringResult do
  @moduledoc "One monitoring evaluation and optional effective-state transition."

  @enforce_keys [:policy_id, :parameter_id, :update_id, :evaluated_state, :effective_state]
  defstruct @enforce_keys ++
              [
                :previous_state,
                :transition,
                :matched_context,
                violation_count: 0,
                conformance_count: 0,
                metadata: %{}
              ]
end
