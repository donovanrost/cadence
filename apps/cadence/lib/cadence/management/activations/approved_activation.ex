defmodule Cadence.Management.Activations.ApprovedActivation do
  @moduledoc "Immutable Management-to-Control activation handoff."

  @type t :: %__MODULE__{
          activation_request_id: binary(),
          organization_id: binary(),
          mission_id: binary(),
          binding_set_id: binary(),
          binding_set_version: pos_integer(),
          binding_set_content_sha256: binary(),
          change_class: atom(),
          requester_actor_document: map(),
          approval_decision_ids: [binary()],
          policy_document: map(),
          metadata: map(),
          approved_at: DateTime.t()
        }

  @enforce_keys [
    :activation_request_id,
    :organization_id,
    :mission_id,
    :binding_set_id,
    :binding_set_version,
    :binding_set_content_sha256,
    :change_class,
    :requester_actor_document,
    :approval_decision_ids,
    :policy_document,
    :metadata,
    :approved_at
  ]
  defstruct @enforce_keys
end
