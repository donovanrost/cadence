defmodule Cadence.Runtime.GenerationApplied do
  @moduledoc """
  Data-plane observation that an exact mission generation is active.
  """

  alias Cadence.Runtime.MissionRuntimeSpec

  @type t :: %__MODULE__{
          organization_id: binary() | nil,
          activation_request_id: binary() | nil,
          mission_id: binary(),
          activation_id: binary(),
          generation: pos_integer(),
          binding_set_content_sha256: binary(),
          applied_at: DateTime.t()
        }

  @enforce_keys [
    :mission_id,
    :activation_id,
    :generation,
    :binding_set_content_sha256,
    :applied_at
  ]
  defstruct @enforce_keys ++ [activation_request_id: nil, organization_id: nil]

  @spec new(MissionRuntimeSpec.t(), DateTime.t()) :: t()
  def new(%MissionRuntimeSpec{} = spec, %DateTime{} = applied_at) do
    %__MODULE__{
      organization_id: spec.organization_id,
      activation_request_id: spec.activation_request_id,
      mission_id: spec.mission_id,
      activation_id: spec.activation_id,
      generation: spec.generation,
      binding_set_content_sha256: spec.binding_set_content_sha256,
      applied_at: applied_at
    }
  end
end
