defmodule Cadence.SemanticRuntime.Result do
  @moduledoc "Complete result of one ordered semantic engine step."

  defstruct parameter_updates: [], monitoring_results: [], alarm_transitions: [], diagnostics: []
end
