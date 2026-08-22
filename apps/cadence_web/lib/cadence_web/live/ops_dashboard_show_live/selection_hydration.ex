defmodule CadenceWeb.OpsDashboardShowLive.SelectionHydration do
  @moduledoc false

  alias CadenceWeb.OpsDashboardShowLive.SelectionPanel

  def hydrate_from_query(socket, opts \\ []) do
    hydrate_selection_fn(opts).(socket)
  end

  defp hydrate_selection_fn(opts),
    do: Keyword.get(opts, :hydrate_selection, &hydrate_selection_from_panel(&1, opts))

  defp hydrate_selection_from_panel(socket, opts) do
    SelectionPanel.hydrate_selection_from_query(socket, opts)
  end
end
