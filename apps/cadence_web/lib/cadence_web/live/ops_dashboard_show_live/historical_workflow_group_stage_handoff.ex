defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowGroupStageHandoff do
  @moduledoc false

  @type t :: %__MODULE__{
          kind: :group_stage,
          workflow: String.t() | nil,
          stage: String.t() | nil,
          attrs: map(),
          request_group_id: String.t(),
          group_transition_scope: String.t() | nil,
          group_correction_tasks: String.t() | nil,
          replacement_run_ids: [String.t()],
          selection_params: map()
        }

  defstruct kind: :group_stage,
            workflow: nil,
            stage: nil,
            attrs: %{},
            request_group_id: nil,
            group_transition_scope: nil,
            group_correction_tasks: nil,
            replacement_run_ids: [],
            selection_params: %{}
end
