defmodule CadenceWeb.OpsDashboardShowLive.RenderRootAssigns do
  @moduledoc false

  alias CadenceWeb.OpsDashboardShowLive.RenderSelectionAssigns

  @spec normalize(Phoenix.LiveView.Socket.t() | map()) :: map()
  def normalize(%{assigns: assigns}) when is_map(assigns), do: assigns
  def normalize(assigns) when is_map(assigns), do: assigns

  @spec root_context(Phoenix.LiveView.Socket.t() | map()) :: map()
  def root_context(socket_or_assigns) do
    assigns = normalize(socket_or_assigns)
    selection_context = RenderSelectionAssigns.selection_context(assigns)
    evidence_context = RenderSelectionAssigns.evidence_context(assigns)

    %{
      engine_result: Map.get(assigns, :dashboard_engine_result),
      compare_engine_result: Map.get(assigns, :dashboard_compare_engine_result),
      runtime_coordinator: Map.get(assigns, :dashboard_runtime_coordinator),
      runtime_decisions: Map.get(assigns, :dashboard_runtime_decisions, []),
      runtime_resolved?: Map.get(assigns, :dashboard_runtime_resolved?),
      last_runtime_invalidation: Map.get(assigns, :dashboard_last_runtime_invalidation),
      time_mode: Map.get(assigns, :dashboard_time_mode),
      time_axis: Map.get(assigns, :dashboard_time_axis),
      time_from: Map.get(assigns, :dashboard_time_from),
      time_to: Map.get(assigns, :dashboard_time_to),
      replay_run_id: Map.get(assigns, :dashboard_replay_run_id),
      time_validation: Map.get(assigns, :dashboard_time_validation),
      scope_kind: Map.get(assigns, :context_scope_kind),
      scope_id: Map.get(assigns, :context_scope_id),
      scope_ids: Map.get(assigns, :context_scope_ids, []),
      data_realm: Map.get(assigns, :dashboard_data_realm),
      data_view: Map.get(assigns, :dashboard_data_view),
      compare_data_view: Map.get(assigns, :dashboard_compare_data_view),
      data_source_id: Map.get(assigns, :dashboard_data_source_id),
      source_binding_id: Map.get(assigns, :dashboard_source_binding_id),
      limit_mode: Map.get(assigns, :dashboard_limit_mode),
      limit_mode_fallback: Map.get(assigns, :dashboard_limit_mode_fallback),
      selection_state: selection_context.state,
      selection_target: selection_context.target,
      selection_source_binding: selection_context.source_binding,
      selection_data_view: selection_context.data_view,
      selection_series_role: selection_context.series_role,
      selection_compare_of: selection_context.compare_of,
      evidence_state: evidence_context.state,
      evidence_kind: evidence_context.kind,
      evidence_source_request: evidence_context.source_request,
      evidence_logical_source: evidence_context.logical_source,
      evidence_realm: evidence_context.realm,
      evidence_data_source_id: evidence_context.data_source_id,
      evidence_source_binding_id: evidence_context.source_binding_id,
      evidence_time_mode: evidence_context.time_mode,
      evidence_time_axis: evidence_context.time_axis,
      evidence_replay_run_id: evidence_context.replay_run_id,
      evidence_scope_kind: evidence_context.scope_kind,
      evidence_scope_id: evidence_context.scope_id,
      evidence_scope_ids: evidence_context.scope_ids,
      evidence_contact_id: evidence_context.contact_id,
      evidence_source_endpoint_id: evidence_context.source_endpoint_id,
      evidence_source_empty_reason: evidence_context.source_empty_reason,
      evidence_requested_realm: evidence_context.requested_realm,
      evidence_requested_data_view: evidence_context.requested_data_view,
      evidence_requested_data_source_id: evidence_context.requested_data_source_id,
      evidence_requested_source_binding_id: evidence_context.requested_source_binding_id,
      evidence_requested_dataset: evidence_context.requested_dataset,
      evidence_requested_validity_state: evidence_context.requested_validity_state,
      document_mode: Map.get(assigns, :dashboard_document_mode),
      lifecycle_status: Map.get(assigns, :dashboard_lifecycle_status),
      summary: Map.get(assigns, :dashboard_summary),
      versions: Map.get(assigns, :dashboard_versions, [])
    }
  end
end
