defmodule Cadence.Capabilities.ExecutionContext do
  @moduledoc """
  Explicit runtime context supplied when executing a managed capability
  instance.
  """

  alias Cadence.Runtime.PartitionKey

  @type t :: %__MODULE__{
          mission_id: binary(),
          activation_id: binary(),
          binding_set_id: binary(),
          binding_set_version: pos_integer(),
          current_time: DateTime.t(),
          partition_key: PartitionKey.t(),
          capability_instance_id: binary(),
          scope_ref: binary(),
          metadata: map()
        }

  defstruct [
    :mission_id,
    :activation_id,
    :binding_set_id,
    :binding_set_version,
    :current_time,
    :partition_key,
    :capability_instance_id,
    :scope_ref,
    metadata: %{}
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      mission_id: Map.fetch!(attrs, :mission_id),
      activation_id: Map.fetch!(attrs, :activation_id),
      binding_set_id: Map.fetch!(attrs, :binding_set_id),
      binding_set_version: Map.fetch!(attrs, :binding_set_version),
      current_time: Map.fetch!(attrs, :current_time),
      partition_key: Map.fetch!(attrs, :partition_key),
      capability_instance_id: Map.fetch!(attrs, :capability_instance_id),
      scope_ref: Map.fetch!(attrs, :scope_ref),
      metadata: Map.get(attrs, :metadata, %{})
    }
  end
end
