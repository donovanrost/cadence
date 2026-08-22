defmodule Cadence.Runtime.TransportActionRequest do
  @moduledoc """
  Canonical persisted platform-owned action request emitted by a transport
  extension.
  """

  @type t :: %__MODULE__{
          action_request_id: binary(),
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
          command_release_attempt_id: binary() | nil,
          command_request_id: binary() | nil,
          source_endpoint_ref: binary() | nil,
          command_name: binary() | nil,
          signal_phase: :acceptance | :start | :completion | :custom | nil,
          action_kind: atom(),
          request_document: map(),
          requested_at: DateTime.t(),
          metadata: map()
        }

  defstruct [
    :action_request_id,
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
    :command_release_attempt_id,
    :command_request_id,
    :source_endpoint_ref,
    :command_name,
    :signal_phase,
    :action_kind,
    :request_document,
    :requested_at,
    metadata: %{}
  ]
end
