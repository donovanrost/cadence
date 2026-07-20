defmodule Cadence.Catalog.Command.Compiler.ConstraintPlan do
  @moduledoc """
  Runtime-facing compiled command transmission-constraint plan.
  """

  alias Cadence.Catalog.Command.MatchCriteria

  @type constraint_type :: :precondition | :interlock | :timing_window | :custom

  @type t :: %__MODULE__{
          command_id: binary(),
          constraint_id: binary(),
          name: binary(),
          description: binary() | nil,
          constraint_type: constraint_type(),
          criteria: MatchCriteria.t() | nil,
          timeout_ms: non_neg_integer() | nil,
          blocking: boolean(),
          metadata: map()
        }

  defstruct [
    :command_id,
    :constraint_id,
    :name,
    :description,
    :constraint_type,
    :criteria,
    :timeout_ms,
    blocking: true,
    metadata: %{}
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      command_id: Map.fetch!(attrs, :command_id),
      constraint_id: Map.fetch!(attrs, :constraint_id),
      name: Map.fetch!(attrs, :name),
      description: Map.get(attrs, :description),
      constraint_type: Map.fetch!(attrs, :constraint_type),
      criteria: Map.get(attrs, :criteria),
      timeout_ms: Map.get(attrs, :timeout_ms),
      blocking: Map.get(attrs, :blocking, true),
      metadata: Map.get(attrs, :metadata, %{})
    }
  end
end
