defmodule CadenceWeb.OpsDataOperationsLive.HistoricalWorkflowRetryGroupFailedJobsHandoff do
  @moduledoc false

  @type t :: %__MODULE__{
          kind: :retry_group_failed_jobs,
          request_group_id: String.t(),
          actor_attrs: map()
        }

  defstruct kind: :retry_group_failed_jobs,
            request_group_id: nil,
            actor_attrs: %{}
end
