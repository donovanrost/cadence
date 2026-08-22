defmodule Cadence.Runtime.ManagedCapabilityRecord do
  @moduledoc """
  Canonical persisted record of one managed capability execution step.
  """

  @type event_kind :: :initialized | :record_handled | :timer_handled

  @type t :: %__MODULE__{
          capability_record_id: binary(),
          mission_id: binary(),
          capability_instance_id: binary(),
          family_key: atom(),
          activation_id: binary(),
          binding_set_id: binary(),
          binding_set_version: pos_integer(),
          partition_affinity: atom(),
          partition_value: binary(),
          event_kind: event_kind(),
          packet_id: binary() | nil,
          evidence_id: binary() | nil,
          timer_key: binary() | nil,
          emitted_record_kinds: [atom()],
          emitted_record_count: non_neg_integer(),
          action_request_count: non_neg_integer(),
          state_snapshot: map(),
          recorded_at: DateTime.t(),
          metadata: map()
        }

  defstruct [
    :capability_record_id,
    :mission_id,
    :capability_instance_id,
    :family_key,
    :activation_id,
    :binding_set_id,
    :binding_set_version,
    :partition_affinity,
    :partition_value,
    :event_kind,
    :packet_id,
    :evidence_id,
    :timer_key,
    :emitted_record_kinds,
    :emitted_record_count,
    :action_request_count,
    :state_snapshot,
    :recorded_at,
    metadata: %{}
  ]
end
