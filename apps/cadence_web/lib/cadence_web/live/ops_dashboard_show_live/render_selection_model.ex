defmodule CadenceWeb.OpsDashboardShowLive.RenderSelectionModel do
  @moduledoc false

  alias CadenceWeb.OpsDashboardShowLive.RenderSelectionAssigns

  def selection(assigns) when is_map(assigns) do
    context = RenderSelectionAssigns.selection_context(assigns)

    %{
      state: context.state,
      target: context.target,
      source_binding: context.source_binding,
      data_view: context.data_view,
      series_role: context.series_role,
      compare_of: context.compare_of
    }
  end

  def evidence(assigns) when is_map(assigns) do
    context = RenderSelectionAssigns.evidence_context(assigns)

    %{
      state: context.state,
      kind: context.kind,
      source_request: context.source_request,
      logical_source: context.logical_source,
      realm: context.realm,
      data_source_id: context.data_source_id,
      source_binding_id: context.source_binding_id,
      time_mode: context.time_mode,
      time_axis: context.time_axis,
      replay_run_id: context.replay_run_id,
      requested_realm: context.requested_realm,
      requested_data_view: context.requested_data_view,
      requested_data_source_id: context.requested_data_source_id,
      requested_source_binding_id: context.requested_source_binding_id,
      requested_dataset: context.requested_dataset,
      requested_validity_state: context.requested_validity_state
    }
  end
end
