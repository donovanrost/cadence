defmodule Cadence.Management.Activations.ActivationDecision do
  @moduledoc "Append-only human decision for a governed activation request."

  alias Cadence.Ids

  @type t :: %__MODULE__{
          activation_decision_id: binary(),
          activation_request_id: binary(),
          organization_id: binary(),
          mission_id: binary(),
          decision: :approved | :rejected,
          actor_kind: :user,
          actor_id: binary(),
          actor_document: map(),
          reason: binary(),
          decided_at: DateTime.t()
        }

  defstruct [
    :activation_decision_id,
    :activation_request_id,
    :organization_id,
    :mission_id,
    :decision,
    :actor_kind,
    :actor_id,
    :actor_document,
    :reason,
    :decided_at
  ]

  @spec new(map()) :: t()
  def new(attrs) do
    struct!(
      __MODULE__,
      Map.put_new(attrs, :activation_decision_id, Ids.new("activation_decision"))
    )
  end
end
