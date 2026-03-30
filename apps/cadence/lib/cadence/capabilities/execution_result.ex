defmodule Cadence.Capabilities.ExecutionResult do
  @moduledoc """
  Standard result envelope returned by managed capability callbacks.
  """

  @type t :: %__MODULE__{
          state: term(),
          records: [term()],
          action_requests: [term()],
          metadata: map()
        }

  defstruct [:state, records: [], action_requests: [], metadata: %{}]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      state: Map.get(attrs, :state),
      records: Map.get(attrs, :records, []),
      action_requests: Map.get(attrs, :action_requests, []),
      metadata: Map.get(attrs, :metadata, %{})
    }
  end
end
