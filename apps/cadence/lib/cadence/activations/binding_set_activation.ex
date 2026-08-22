defmodule Cadence.Activations.BindingSetActivation do
  @moduledoc """
  Immutable activation record for one mission binding-set basis.
  """

  alias Cadence.Ids

  @type t :: %__MODULE__{
          activation_id: binary(),
          activation_request_id: binary() | nil,
          organization_id: binary() | nil,
          mission_id: binary(),
          generation: pos_integer(),
          binding_set_id: binary(),
          binding_set_version: pos_integer(),
          binding_set_content_sha256: binary() | nil,
          metadata: map(),
          activated_at: DateTime.t()
        }

  defstruct [
    :activation_id,
    :activation_request_id,
    :organization_id,
    :mission_id,
    :generation,
    :binding_set_id,
    :binding_set_version,
    :binding_set_content_sha256,
    :activated_at,
    metadata: %{}
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      activation_id: Map.get(attrs, :activation_id, Ids.new("activation")),
      activation_request_id: Map.get(attrs, :activation_request_id),
      organization_id: Map.get(attrs, :organization_id, Map.get(attrs, "organization_id")),
      mission_id: Map.fetch!(attrs, :mission_id),
      generation: Map.get(attrs, :generation, 1),
      binding_set_id: Map.fetch!(attrs, :binding_set_id),
      binding_set_version: Map.fetch!(attrs, :binding_set_version),
      binding_set_content_sha256: Map.get(attrs, :binding_set_content_sha256),
      metadata: Map.get(attrs, :metadata, %{}),
      activated_at: Map.get(attrs, :activated_at, DateTime.utc_now())
    }
  end
end
