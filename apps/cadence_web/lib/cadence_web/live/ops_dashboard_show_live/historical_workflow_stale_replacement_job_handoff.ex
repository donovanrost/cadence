defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowStaleReplacementJobHandoff do
  @moduledoc false

  @type t :: %__MODULE__{
          kind: :stale_replacement_job,
          job_id: String.t(),
          event_id: String.t(),
          actor_attrs: map()
        }

  defstruct kind: :stale_replacement_job,
            job_id: nil,
            event_id: nil,
            actor_attrs: %{}
end
