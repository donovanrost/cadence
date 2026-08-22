defmodule Cadence.ContactPlanning.FleetOptimizationResult do
  @moduledoc "Deterministic output and explanation evidence from one fleet optimization pass."

  @type t :: %__MODULE__{
          selected_snapshot_ids: [binary()],
          selected_snapshots: [struct()],
          decisions: [map()],
          coverage_by_requirement: map(),
          resource_summary: map(),
          budget_summary: map(),
          termination_document: map()
        }

  defstruct selected_snapshot_ids: [],
            selected_snapshots: [],
            decisions: [],
            coverage_by_requirement: %{},
            resource_summary: %{},
            budget_summary: %{},
            termination_document: %{}
end
