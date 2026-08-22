defmodule CadenceWeb.OpsDashboardShowLive.SelectionEvents do
  @moduledoc false

  alias CadenceWeb.OpsDashboardShowLive.SelectionPanel

  def open_evidence(socket, params, opts \\ []) do
    open_evidence_fn(opts).(socket, params, opts)
  end

  def open_data_link(socket, link_id, params, opts \\ []) do
    open_data_link_fn(opts).(socket, link_id, params, opts)
  end

  defp open_evidence_fn(opts),
    do: Keyword.get(opts, :open_evidence_event, &SelectionPanel.open_evidence/3)

  defp open_data_link_fn(opts),
    do: Keyword.get(opts, :open_data_link_event, &SelectionPanel.open_data_link/4)
end
