defmodule Cadence.SemanticRuntime.State do
  @moduledoc "Deterministic partition-local state for semantic execution."

  defstruct latest: %{}, algorithm_state: %{}, monitoring_state: %{}, sequence: 0
end
