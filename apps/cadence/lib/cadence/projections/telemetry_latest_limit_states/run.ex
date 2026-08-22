defmodule Cadence.Projections.TelemetryLatestLimitStates.Run do
  @moduledoc """
  Summary of one latest limit-state projection rebuild run.
  """

  alias Cadence.Ids

  @type status :: :running | :completed | :failed

  @type t :: %__MODULE__{
          rebuild_run_id: binary(),
          mission_id: binary(),
          status: status(),
          rebuilt_state_count: non_neg_integer(),
          failure_reason: term() | nil,
          started_at: DateTime.t(),
          completed_at: DateTime.t() | nil,
          metadata: map()
        }

  defstruct [
    :rebuild_run_id,
    :mission_id,
    :status,
    :rebuilt_state_count,
    :failure_reason,
    :started_at,
    :completed_at,
    metadata: %{}
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      rebuild_run_id: Map.get(attrs, :rebuild_run_id, Ids.new("limit_state_rebuild_run")),
      mission_id: Map.fetch!(attrs, :mission_id),
      status: Map.get(attrs, :status, :running),
      rebuilt_state_count: Map.get(attrs, :rebuilt_state_count, 0),
      failure_reason: Map.get(attrs, :failure_reason),
      started_at: Map.get(attrs, :started_at, DateTime.utc_now()),
      completed_at: Map.get(attrs, :completed_at),
      metadata: Map.get(attrs, :metadata, %{})
    }
  end
end
