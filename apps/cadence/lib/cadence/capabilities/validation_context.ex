defmodule Cadence.Capabilities.ValidationContext do
  @moduledoc """
  Validation context passed into capability-family configuration checks.
  """

  alias Cadence.Capabilities.Descriptor

  @type t :: %__MODULE__{
          mission_id: binary(),
          target_scope: Descriptor.scope(),
          input_stage: Descriptor.input_stage() | nil,
          metadata: map()
        }

  defstruct [:mission_id, :target_scope, :input_stage, metadata: %{}]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      mission_id: Map.fetch!(attrs, :mission_id),
      target_scope: Map.fetch!(attrs, :target_scope),
      input_stage: Map.get(attrs, :input_stage),
      metadata: Map.get(attrs, :metadata, %{})
    }
  end
end
