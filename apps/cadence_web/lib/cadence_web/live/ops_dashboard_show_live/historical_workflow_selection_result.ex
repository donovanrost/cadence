defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowSelectionResult do
  @moduledoc false

  alias Cadence.Dashboards.DataLink
  alias CadenceWeb.OpsDashboardShowLive.SelectionQuery

  @type t :: %__MODULE__{
          event: map() | nil,
          query: SelectionQuery.t(),
          link: DataLink.t()
        }

  defstruct event: nil,
            query: nil,
            link: nil
end
