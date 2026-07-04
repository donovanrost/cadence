defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowCorrectionRequestHandoff do
  @moduledoc false

  @type t :: %__MODULE__{
          kind: :correction_request,
          workflow: String.t() | nil,
          stage: String.t(),
          attrs: map(),
          correction_params: map(),
          selection_params: map()
        }

  defstruct kind: :correction_request,
            workflow: nil,
            stage: "requested",
            attrs: %{},
            correction_params: %{},
            selection_params: %{}
end
