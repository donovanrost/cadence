defmodule Cadence.Management.Activations.ActivationRequest do
  @moduledoc "Durable governed intent to activate one exact binding-set version."

  alias Cadence.Ids

  @type state :: :approval_pending | :approved | :rejected
  @type t :: %__MODULE__{
          activation_request_id: binary(),
          organization_id: binary(),
          mission_id: binary(),
          binding_set_id: binary(),
          binding_set_version: pos_integer(),
          binding_set_content_sha256: binary(),
          change_class: atom(),
          state: state(),
          requester_actor_kind: :user | :service,
          requester_actor_id: binary(),
          requester_actor_document: map(),
          policy_document: map(),
          requested_at: DateTime.t(),
          decided_at: DateTime.t() | nil
        }

  defstruct [
    :activation_request_id,
    :organization_id,
    :mission_id,
    :binding_set_id,
    :binding_set_version,
    :binding_set_content_sha256,
    :change_class,
    :state,
    :requester_actor_kind,
    :requester_actor_id,
    :requester_actor_document,
    :policy_document,
    :requested_at,
    :decided_at
  ]

  @spec new(map()) :: t()
  def new(attrs) do
    struct!(__MODULE__, Map.put_new(attrs, :activation_request_id, Ids.new("activation_request")))
  end
end
