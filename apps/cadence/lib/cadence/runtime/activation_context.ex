defmodule Cadence.Runtime.ActivationContext do
  @moduledoc """
  Explicit runtime context supplied when building partition-owned capability
  instances from an active mission basis.
  """

  alias Cadence.Runtime.PartitionKey

  @type t :: %__MODULE__{
          mission_id: binary(),
          activation_id: binary(),
          binding_set_id: binary(),
          binding_set_version: pos_integer(),
          partition_key: PartitionKey.t(),
          metadata: map()
        }

  defstruct [
    :mission_id,
    :activation_id,
    :binding_set_id,
    :binding_set_version,
    :partition_key,
    metadata: %{}
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      mission_id: Map.fetch!(attrs, :mission_id),
      activation_id: Map.fetch!(attrs, :activation_id),
      binding_set_id: Map.fetch!(attrs, :binding_set_id),
      binding_set_version: Map.fetch!(attrs, :binding_set_version),
      partition_key: Map.fetch!(attrs, :partition_key),
      metadata: Map.get(attrs, :metadata, %{})
    }
  end
end
