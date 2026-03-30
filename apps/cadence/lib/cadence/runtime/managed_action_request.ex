defmodule Cadence.Runtime.ManagedActionRequest do
  @moduledoc """
  Canonical persisted record of one platform-owned action request emitted by a
  managed capability.
  """

  @type t :: %__MODULE__{
          action_request_id: binary(),
          mission_id: binary(),
          capability_instance_id: binary(),
          family_key: atom(),
          activation_id: binary(),
          binding_set_id: binary(),
          binding_set_version: pos_integer(),
          partition_affinity: atom(),
          partition_value: binary(),
          action_kind: atom(),
          packet_id: binary() | nil,
          evidence_id: binary() | nil,
          request_document: map(),
          requested_at: DateTime.t()
        }

  defstruct [
    :action_request_id,
    :mission_id,
    :capability_instance_id,
    :family_key,
    :activation_id,
    :binding_set_id,
    :binding_set_version,
    :partition_affinity,
    :partition_value,
    :action_kind,
    :packet_id,
    :evidence_id,
    :request_document,
    :requested_at
  ]
end
