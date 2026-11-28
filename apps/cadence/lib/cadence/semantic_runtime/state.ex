defmodule Cadence.SemanticRuntime.State do
  @moduledoc """
  Deterministic partition-local state for semantic execution. It is what a semantic snapshot holds
  (DECISIONS #94/#96): latest values, algorithm memory, monitoring state, and the timers' cursors
  (`timer_cursors`: a timer's key => when it last fired).

  `fingerprints` names the definitions the entries were evolved under (`Carry`), so a partition
  under a new runtime basis keeps exactly the entries whose identity did not change.
  """

  defstruct latest: %{},
            algorithm_state: %{},
            monitoring_state: %{},
            timer_cursors: %{},
            fingerprints: %{},
            sequence: 0
end
