defmodule Cadence.Jobs.Job do
  @moduledoc """
  Durable background job state for Cadence runtime work.
  """

  alias Cadence.Ids

  @type status :: :queued | :running | :completed | :failed
  @type job_type ::
          :replay_telemetry_scope
          | :telemetry_latest_value_rebuild
          | :derived_telemetry_evaluation
          | :derived_telemetry_latest_value_rebuild
          | :telemetry_limit_evaluation
          | :telemetry_latest_limit_state_refresh
          | :telemetry_latest_limit_state_rebuild
          | :mission_event_rebuild
          | :catalog_import_run
          | :telemetry_historical_data_workflow
          | :managed_questdb_provisioning
          | :dashboard_tsdb_backend_lifecycle

  @type t :: %__MODULE__{
          job_id: binary(),
          mission_id: binary(),
          job_type: job_type(),
          run_id: binary(),
          status: status(),
          payload: map(),
          attempt_count: non_neg_integer(),
          failure_reason: term() | nil,
          started_at: DateTime.t() | nil,
          completed_at: DateTime.t() | nil
        }

  defstruct [
    :job_id,
    :mission_id,
    :job_type,
    :run_id,
    :status,
    :payload,
    :attempt_count,
    :failure_reason,
    :started_at,
    :completed_at
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      job_id: Map.get(attrs, :job_id, Ids.new("job")),
      mission_id: Map.fetch!(attrs, :mission_id),
      job_type: Map.fetch!(attrs, :job_type),
      run_id: Map.fetch!(attrs, :run_id),
      status: Map.get(attrs, :status, :queued),
      payload: Map.get(attrs, :payload, %{}),
      attempt_count: Map.get(attrs, :attempt_count, 0),
      failure_reason: Map.get(attrs, :failure_reason),
      started_at: Map.get(attrs, :started_at),
      completed_at: Map.get(attrs, :completed_at)
    }
  end
end
