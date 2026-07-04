defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowStageHandoff do
  @moduledoc false

  @type t :: %__MODULE__{
          kind: :stage,
          workflow: String.t() | nil,
          stage: String.t() | nil,
          attrs: map(),
          event_id: String.t() | nil,
          correction_source_event_id: String.t() | nil,
          selection_params: map()
        }

  defstruct kind: :stage,
            workflow: nil,
            stage: nil,
            attrs: %{},
            event_id: nil,
            correction_source_event_id: nil,
            selection_params: %{}
end
