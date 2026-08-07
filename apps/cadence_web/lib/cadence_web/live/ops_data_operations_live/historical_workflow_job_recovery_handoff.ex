defmodule CadenceWeb.OpsDataOperationsLive.HistoricalWorkflowJobRecoveryHandoff do
  @moduledoc false

  @type action ::
          :retry_job
          | :inspect_stale_replacement_job
          | :requeue_stale_replacement_job

  @type t :: %__MODULE__{
          kind: :job_recovery,
          action: action(),
          job_id: String.t(),
          event_id: String.t(),
          actor_attrs: map()
        }

  defstruct kind: :job_recovery,
            action: nil,
            job_id: nil,
            event_id: nil,
            actor_attrs: %{}
end
