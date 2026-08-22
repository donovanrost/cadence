defmodule Cadence.Replay.Run do
  @moduledoc """
  Summary of one replay execution over persisted evidence and governed config.
  """

  alias Cadence.Ids

  @type status :: :running | :completed | :failed

  @type t :: %__MODULE__{
          replay_run_id: binary(),
          mission_id: binary(),
          binding_set_id: binary(),
          binding_set_version: pos_integer(),
          status: status(),
          replayed_evidence_count: non_neg_integer(),
          replayed_packet_count: non_neg_integer(),
          replayed_sample_count: non_neg_integer(),
          failure_reason: term() | nil,
          started_at: DateTime.t(),
          completed_at: DateTime.t() | nil,
          metadata: map()
        }

  defstruct [
    :replay_run_id,
    :mission_id,
    :binding_set_id,
    :binding_set_version,
    :status,
    :replayed_evidence_count,
    :replayed_packet_count,
    :replayed_sample_count,
    :failure_reason,
    :started_at,
    :completed_at,
    metadata: %{}
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      replay_run_id: Map.get(attrs, :replay_run_id, Ids.new("replay_run")),
      mission_id: Map.fetch!(attrs, :mission_id),
      binding_set_id: Map.fetch!(attrs, :binding_set_id),
      binding_set_version: Map.fetch!(attrs, :binding_set_version),
      status: Map.get(attrs, :status, :running),
      replayed_evidence_count: Map.get(attrs, :replayed_evidence_count, 0),
      replayed_packet_count: Map.get(attrs, :replayed_packet_count, 0),
      replayed_sample_count: Map.get(attrs, :replayed_sample_count, 0),
      failure_reason: Map.get(attrs, :failure_reason),
      started_at: Map.get(attrs, :started_at, DateTime.utc_now()),
      completed_at: Map.get(attrs, :completed_at),
      metadata: Map.get(attrs, :metadata, %{})
    }
  end
end
