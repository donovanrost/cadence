defmodule Cadence.Control.Activations.ActivationExecution do
  @moduledoc "Durable Control-plane result for one approved activation handoff."

  alias Cadence.Ids

  @type status :: :in_progress | :succeeded | :failed
  @type t :: %__MODULE__{
          activation_execution_id: binary(),
          activation_request_id: binary(),
          organization_id: binary(),
          mission_id: binary(),
          status: status(),
          executor_actor_document: map(),
          activation_id: binary() | nil,
          generation: pos_integer() | nil,
          binding_set_content_sha256: binary(),
          error_document: map(),
          started_at: DateTime.t(),
          completed_at: DateTime.t() | nil
        }

  defstruct [
    :activation_execution_id,
    :activation_request_id,
    :organization_id,
    :mission_id,
    :status,
    :executor_actor_document,
    :activation_id,
    :generation,
    :binding_set_content_sha256,
    :error_document,
    :started_at,
    :completed_at
  ]

  @spec new(map()) :: t()
  def new(attrs) do
    struct!(
      __MODULE__,
      Map.put_new(attrs, :activation_execution_id, Ids.new("activation_execution"))
    )
  end
end
