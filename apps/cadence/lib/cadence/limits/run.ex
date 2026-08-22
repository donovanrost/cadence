defmodule Cadence.Limits.Run do
  @moduledoc """
  Summary of one telemetry limit evaluation run.
  """

  alias Cadence.Ids

  @type status :: :running | :completed | :failed

  @type t :: %__MODULE__{
          limit_run_id: binary(),
          mission_id: binary(),
          status: status(),
          evaluated_sample_count: non_neg_integer(),
          emitted_event_count: non_neg_integer(),
          definition_count: non_neg_integer(),
          failure_reason: term() | nil,
          started_at: DateTime.t(),
          completed_at: DateTime.t() | nil,
          metadata: map()
        }

  defstruct [
    :limit_run_id,
    :mission_id,
    :status,
    :evaluated_sample_count,
    :emitted_event_count,
    :definition_count,
    :failure_reason,
    :started_at,
    :completed_at,
    metadata: %{}
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      limit_run_id: Map.get(attrs, :limit_run_id, Ids.new("limit_run")),
      mission_id: Map.fetch!(attrs, :mission_id),
      status: Map.get(attrs, :status, :running),
      evaluated_sample_count: Map.get(attrs, :evaluated_sample_count, 0),
      emitted_event_count: Map.get(attrs, :emitted_event_count, 0),
      definition_count: Map.get(attrs, :definition_count, 0),
      failure_reason: Map.get(attrs, :failure_reason),
      started_at: Map.get(attrs, :started_at, DateTime.utc_now()),
      completed_at: Map.get(attrs, :completed_at),
      metadata: Map.get(attrs, :metadata, %{})
    }
  end
end
