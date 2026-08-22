defmodule Cadence.Catalog.Command.Compiler.VerifierPlan do
  @moduledoc """
  Runtime-facing compiled command verifier plan.
  """

  alias Cadence.Catalog.Command.MatchCriteria

  @type phase :: :acceptance | :start | :completion | :custom
  @type severity :: :info | :warning | :error | :critical | nil

  @type t :: %__MODULE__{
          command_id: binary(),
          verifier_id: binary(),
          name: binary(),
          description: binary() | nil,
          phase: phase(),
          success_criteria: MatchCriteria.t() | nil,
          failure_criteria: MatchCriteria.t() | nil,
          timeout_ms: non_neg_integer() | nil,
          delay_ms: non_neg_integer() | nil,
          severity: severity(),
          metadata: map()
        }

  defstruct [
    :command_id,
    :verifier_id,
    :name,
    :description,
    :phase,
    :success_criteria,
    :failure_criteria,
    :timeout_ms,
    :delay_ms,
    :severity,
    metadata: %{}
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      command_id: Map.fetch!(attrs, :command_id),
      verifier_id: Map.fetch!(attrs, :verifier_id),
      name: Map.fetch!(attrs, :name),
      description: Map.get(attrs, :description),
      phase: Map.fetch!(attrs, :phase),
      success_criteria: Map.get(attrs, :success_criteria),
      failure_criteria: Map.get(attrs, :failure_criteria),
      timeout_ms: Map.get(attrs, :timeout_ms),
      delay_ms: Map.get(attrs, :delay_ms),
      severity: Map.get(attrs, :severity),
      metadata: Map.get(attrs, :metadata, %{})
    }
  end
end
