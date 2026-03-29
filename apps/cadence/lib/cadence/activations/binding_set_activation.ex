defmodule Cadence.Activations.BindingSetActivation do
  @moduledoc """
  Immutable activation record for one mission binding-set basis.
  """

  alias Cadence.Ids

  @type t :: %__MODULE__{
          activation_id: binary(),
          organization_id: binary() | nil,
          mission_id: binary(),
          binding_set_id: binary(),
          binding_set_version: pos_integer(),
          metadata: map(),
          activated_at: DateTime.t()
        }

  defstruct [
    :activation_id,
    :organization_id,
    :mission_id,
    :binding_set_id,
    :binding_set_version,
    :activated_at,
    metadata: %{}
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      activation_id: Map.get(attrs, :activation_id, Ids.new("activation")),
      organization_id: Map.get(attrs, :organization_id, Map.get(attrs, "organization_id")),
      mission_id: Map.fetch!(attrs, :mission_id),
      binding_set_id: Map.fetch!(attrs, :binding_set_id),
      binding_set_version: Map.fetch!(attrs, :binding_set_version),
      metadata: Map.get(attrs, :metadata, %{}),
      activated_at: Map.get(attrs, :activated_at, DateTime.utc_now())
    }
  end
end
