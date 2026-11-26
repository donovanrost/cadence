defmodule Cadence.SemanticRuntime.State do
  @moduledoc """
  Deterministic partition-local state for semantic execution. It is what a semantic snapshot holds
  (DECISIONS #94/#96): latest values, algorithm memory, monitoring state, and the timers' cursors
  (`timer_cursors`: a timer's key => when it last fired).
  """

  defstruct latest: %{},
            algorithm_state: %{},
            monitoring_state: %{},
            timer_cursors: %{},
            sequence: 0
end
