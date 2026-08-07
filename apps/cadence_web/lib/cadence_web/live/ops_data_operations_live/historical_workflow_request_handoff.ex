defmodule CadenceWeb.OpsDataOperationsLive.HistoricalWorkflowRequestHandoff do
  @moduledoc false

  @type t :: %__MODULE__{
          kind: :request,
          workflow: String.t(),
          stage: String.t(),
          attrs: map(),
          point_ids: [String.t()],
          selection_params: map()
        }

  defstruct kind: :request,
            workflow: "backfill",
            stage: "requested",
            attrs: %{},
            point_ids: [],
            selection_params: %{}
end
