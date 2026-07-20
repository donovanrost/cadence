defmodule Cadence.Catalog.Command.Compiler.Result do
  @moduledoc """
  Output of compiling a canonical command snapshot into narrower runtime-facing
  command artifacts.
  """

  alias Cadence.Catalog.Diagnostic

  alias Cadence.Catalog.Command.Compiler.{
    ConstraintPlan,
    OperationalBinding,
    RuntimeDefinition,
    VerifierPlan
  }

  @type t :: %__MODULE__{
          runtime_definitions: [RuntimeDefinition.t()],
          constraint_plans: [ConstraintPlan.t()],
          verifier_plans: [VerifierPlan.t()],
          operational_bindings: [OperationalBinding.t()],
          diagnostics: [Diagnostic.t()]
        }

  defstruct runtime_definitions: [],
            constraint_plans: [],
            verifier_plans: [],
            operational_bindings: [],
            diagnostics: []

  @spec new(map()) :: t()
  def new(attrs \\ %{}) when is_map(attrs) do
    %__MODULE__{
      runtime_definitions: Map.get(attrs, :runtime_definitions, []),
      constraint_plans: Map.get(attrs, :constraint_plans, []),
      verifier_plans: Map.get(attrs, :verifier_plans, []),
      operational_bindings: Map.get(attrs, :operational_bindings, []),
      diagnostics: Map.get(attrs, :diagnostics, [])
    }
  end
end
