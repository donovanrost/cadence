defmodule Cadence.Telemetry.BackfillLifecycleChanged do
  @moduledoc """
  Public committed fact for a telemetry backfill or import lifecycle change.

  Consumers use this value instead of depending on the telemetry persistence
  representation that produced it.
  """

  @fields [
    :backfill_lifecycle_event_id,
    :backfill_run_id,
    :organization_id,
    :mission_id,
    :realm,
    :replay_run_id,
    :data_source_id,
    :binding_id,
    :observable_id,
    :point_id,
    :spacecraft_id,
    :event_type,
    :source_from,
    :source_to,
    :receipt_from,
    :receipt_to,
    :sample_count,
    :authority,
    :reason,
    :actor_id,
    :actor_kind,
    :occurred_at,
    :payload
  ]

  @type t :: %__MODULE__{
          backfill_lifecycle_event_id: binary(),
          backfill_run_id: binary(),
          organization_id: binary(),
          mission_id: binary(),
          realm: atom() | binary(),
          replay_run_id: binary() | nil,
          data_source_id: binary() | nil,
          binding_id: binary() | nil,
          observable_id: binary() | nil,
          point_id: binary() | nil,
          spacecraft_id: binary() | nil,
          event_type: atom(),
          source_from: DateTime.t() | nil,
          source_to: DateTime.t() | nil,
          receipt_from: DateTime.t() | nil,
          receipt_to: DateTime.t() | nil,
          sample_count: non_neg_integer() | nil,
          authority: atom(),
          reason: binary() | atom() | nil,
          actor_id: binary() | nil,
          actor_kind: binary() | nil,
          occurred_at: DateTime.t(),
          payload: map()
        }

  defstruct @fields

  @spec from_committed_event(map()) :: t()
  def from_committed_event(event) when is_map(event) do
    struct!(__MODULE__, Map.take(event, @fields))
  end
end
