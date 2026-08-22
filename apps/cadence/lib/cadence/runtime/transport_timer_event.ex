defmodule Cadence.Runtime.TransportTimerEvent do
  @moduledoc """
  Canonical timer lifecycle event for one transport-extension timer.
  """

  @type event_kind :: :scheduled | :fired | :canceled

  @type t :: %__MODULE__{
          timer_event_id: binary(),
          mission_id: binary(),
          realized_contact_id: binary(),
          path_id: binary(),
          capability_instance_id: binary(),
          family_key: atom(),
          activation_id: binary(),
          binding_set_id: binary(),
          binding_set_version: pos_integer(),
          partition_affinity: atom(),
          partition_value: binary(),
          timer_key: binary(),
          event_kind: event_kind(),
          due_at: DateTime.t() | nil,
          occurred_at: DateTime.t(),
          metadata: map()
        }

  defstruct [
    :timer_event_id,
    :mission_id,
    :realized_contact_id,
    :path_id,
    :capability_instance_id,
    :family_key,
    :activation_id,
    :binding_set_id,
    :binding_set_version,
    :partition_affinity,
    :partition_value,
    :timer_key,
    :event_kind,
    :due_at,
    :occurred_at,
    metadata: %{}
  ]
end
