defmodule Cadence.Catalog.MissionModel.CompilerResult do
  @moduledoc "Result of composing, resolving, and lowering Mission Model layers."

  alias Cadence.Catalog.MissionModel.{Revision, RuntimePlan}

  @type t :: %__MODULE__{revision: Revision.t(), plans: %{atom() => RuntimePlan.t()}}
  @enforce_keys [:revision, :plans]
  defstruct @enforce_keys
end
