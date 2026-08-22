defmodule CadenceWeb.OpsDashboardShowLive.RenderRootAttrs do
  @moduledoc false

  alias CadenceWeb.OpsDashboardShowLive.DocumentLifecycle
  alias CadenceWeb.OpsDashboardShowLive.RenderRootAssigns
  alias CadenceWeb.OpsDashboardShowLive.RuntimeEngineDiagnostics
  alias CadenceWeb.OpsDashboardShowLive.RuntimeRefreshState

  def page_attrs(root_attrs) when is_map(root_attrs) do
    %{
      id: "ops-dashboard-show-page",
      class: "flex flex-col flex-1 min-h-0"
    }
    |> Map.merge(root_attrs)
  end

  def root_attrs(assigns, runtime_diagnostics, runtime_invalidation) when is_map(assigns) do
    context = RenderRootAssigns.root_context(assigns)

    runtime_refresh_state =
      RuntimeRefreshState.build(context, runtime_diagnostics, runtime_invalidation)

    context
    |> engine_root_attrs()
    |> Map.merge(RuntimeRefreshState.runtime_root_attrs(runtime_refresh_state))
    |> Map.merge(RuntimeRefreshState.invalidation_root_attrs(runtime_refresh_state))
    |> Map.merge(dashboard_root_attrs(context))
  end

  def engine_root_attrs(context) when is_map(context) do
    %{
      "data-engine-resolve-mode" => RuntimeEngineDiagnostics.resolve_mode(context.engine_result),
      "data-engine-source-requests" =>
        RuntimeEngineDiagnostics.metadata(context.engine_result, :source_request_count),
      "data-engine-executed-source-requests" =>
        RuntimeEngineDiagnostics.metadata(context.engine_result, :executed_source_request_count),
      "data-engine-skipped-source-requests" =>
        RuntimeEngineDiagnostics.metadata(context.engine_result, :skipped_source_request_count),
      "data-engine-plan-cache" =>
        RuntimeEngineDiagnostics.cache_status(context.engine_result, :plan_cache),
      "data-engine-source-cache-statuses" =>
        RuntimeEngineDiagnostics.source_cache_statuses(context.engine_result),
      "data-engine-frame-cache-statuses" =>
        RuntimeEngineDiagnostics.frame_cache_statuses(context.engine_result),
      "data-engine-source-dependencies" =>
        RuntimeEngineDiagnostics.source_dependency_summary(context.engine_result),
      "data-engine-source-dependency-count" =>
        RuntimeEngineDiagnostics.source_dependency_count(context.engine_result),
      "data-engine-source-dependency-evidence" =>
        RuntimeEngineDiagnostics.source_dependency_evidence_summary(context.engine_result),
      "data-engine-source-dependency-degraded-count" =>
        RuntimeEngineDiagnostics.source_dependency_degraded_count(context.engine_result),
      "data-engine-snapshot" =>
        RuntimeEngineDiagnostics.boolean_metadata(context.engine_result, :snapshot?),
      "data-engine-live-append-eligible" =>
        RuntimeEngineDiagnostics.boolean_metadata(context.engine_result, :live_append_eligible?),
      "data-engine-time-mode" =>
        RuntimeEngineDiagnostics.context(context.engine_result, :time, :mode),
      "data-engine-time-axis" =>
        RuntimeEngineDiagnostics.context(context.engine_result, :time, :axis),
      "data-engine-replay-run-id" =>
        RuntimeEngineDiagnostics.context(context.engine_result, :time, :replay_run_id),
      "data-engine-data-realm" =>
        RuntimeEngineDiagnostics.context(context.engine_result, :data, :realm),
      "data-engine-data-source-id" =>
        RuntimeEngineDiagnostics.context(context.engine_result, :data, :data_source_id),
      "data-engine-source-binding-id" =>
        RuntimeEngineDiagnostics.context(context.engine_result, :data, :source_binding_id),
      "data-engine-data-view" =>
        RuntimeEngineDiagnostics.context(context.engine_result, :data, :view),
      "data-engine-limit-mode" =>
        RuntimeEngineDiagnostics.context(context.engine_result, :limit, :semantics_mode),
      "data-compare-engine-resolve-mode" =>
        RuntimeEngineDiagnostics.resolve_mode(context.compare_engine_result),
      "data-compare-engine-source-requests" =>
        RuntimeEngineDiagnostics.metadata(context.compare_engine_result, :source_request_count),
      "data-compare-engine-data-view" =>
        RuntimeEngineDiagnostics.context(context.compare_engine_result, :data, :view)
    }
  end

  def runtime_root_attrs(context, runtime_diagnostics)
      when is_map(context) and is_map(runtime_diagnostics) do
    context
    |> RuntimeRefreshState.build(runtime_diagnostics, %{})
    |> RuntimeRefreshState.runtime_root_attrs()
  end

  def runtime_invalidation_root_attrs(context, runtime_diagnostics, runtime_invalidation)
      when is_map(context) and is_map(runtime_diagnostics) do
    context
    |> RuntimeRefreshState.build(runtime_diagnostics, runtime_invalidation)
    |> RuntimeRefreshState.invalidation_root_attrs()
  end

  def dashboard_root_attrs(context) when is_map(context) do
    %{
      "data-dashboard-time-mode" => context.time_mode,
      "data-dashboard-time-axis" => context.time_axis,
      "data-dashboard-time-from" => context.time_from,
      "data-dashboard-time-to" => context.time_to,
      "data-dashboard-replay-run-id" => context.replay_run_id,
      "data-dashboard-time-validation" => context.time_validation,
      "data-dashboard-scope-kind" => context.scope_kind,
      "data-dashboard-scope-id" => context.scope_id,
      "data-dashboard-scope-ids" => scope_ids_attr(context.scope_ids),
      "data-dashboard-data-realm" => context.data_realm,
      "data-dashboard-data-view" => context.data_view,
      "data-dashboard-compare-data-view" => context.compare_data_view,
      "data-dashboard-data-source-id" => context.data_source_id,
      "data-dashboard-source-binding-id" => context.source_binding_id,
      "data-dashboard-limit-mode" => context.limit_mode,
      "data-dashboard-limit-mode-requested" =>
        fallback_value(context.limit_mode_fallback, "requested_mode"),
      "data-dashboard-limit-mode-fallback-reason" =>
        fallback_value(context.limit_mode_fallback, "reason"),
      "data-dashboard-selection-state" => context.selection_state,
      "data-dashboard-selection-target" => context.selection_target,
      "data-dashboard-selection-source-binding" => context.selection_source_binding,
      "data-dashboard-selection-data-view" => context.selection_data_view,
      "data-dashboard-selection-series-role" => context.selection_series_role,
      "data-dashboard-selection-compare-of" => context.selection_compare_of,
      "data-dashboard-evidence-state" => context.evidence_state,
      "data-dashboard-evidence-kind" => context.evidence_kind,
      "data-dashboard-evidence-source-request" => context.evidence_source_request,
      "data-dashboard-evidence-logical-source" => context.evidence_logical_source,
      "data-dashboard-evidence-realm" => context.evidence_realm,
      "data-dashboard-evidence-data-source-id" => context.evidence_data_source_id,
      "data-dashboard-evidence-source-binding-id" => context.evidence_source_binding_id,
      "data-dashboard-evidence-time-mode" => context.evidence_time_mode,
      "data-dashboard-evidence-time-axis" => context.evidence_time_axis,
      "data-dashboard-evidence-replay-run-id" => context.evidence_replay_run_id,
      "data-dashboard-evidence-scope-kind" => context.evidence_scope_kind,
      "data-dashboard-evidence-scope-id" => context.evidence_scope_id,
      "data-dashboard-evidence-scope-ids" => scope_ids_attr(context.evidence_scope_ids),
      "data-dashboard-evidence-contact-id" => context.evidence_contact_id,
      "data-dashboard-evidence-source-endpoint-id" => context.evidence_source_endpoint_id,
      "data-dashboard-evidence-source-empty-reason" => context.evidence_source_empty_reason,
      "data-dashboard-evidence-requested-realm" => context.evidence_requested_realm,
      "data-dashboard-evidence-requested-data-view" => context.evidence_requested_data_view,
      "data-dashboard-evidence-requested-data-source-id" =>
        context.evidence_requested_data_source_id,
      "data-dashboard-evidence-requested-source-binding-id" =>
        context.evidence_requested_source_binding_id,
      "data-dashboard-evidence-requested-dataset" => context.evidence_requested_dataset,
      "data-dashboard-evidence-requested-validity-state" =>
        context.evidence_requested_validity_state,
      "data-dashboard-document-mode" => context.document_mode,
      "data-dashboard-publication-state" =>
        DocumentLifecycle.publication_state(context.lifecycle_status),
      "data-dashboard-publishable-version" =>
        DocumentLifecycle.publishable_version(context.lifecycle_status),
      "data-dashboard-published-current" =>
        DocumentLifecycle.lifecycle_flag(
          context.lifecycle_status,
          :published_current?
        ),
      "data-dashboard-draft-ahead" =>
        DocumentLifecycle.lifecycle_flag(context.lifecycle_status, :draft_ahead?),
      "data-dashboard-publish-available" =>
        DocumentLifecycle.lifecycle_flag(
          context.lifecycle_status,
          :publish_available?
        ),
      "data-dashboard-draft-defaults-differ" =>
        if(
          DocumentLifecycle.draft_runtime_defaults_differ?(
            context.summary,
            context.versions
          ),
          do: "true",
          else: "false"
        )
    }
  end

  defp fallback_value(fallback, key) when is_map(fallback), do: Map.get(fallback, key)
  defp fallback_value(_fallback, _key), do: nil

  defp scope_ids_attr(scope_ids) when is_list(scope_ids), do: Enum.join(scope_ids, ",")
  defp scope_ids_attr(scope_ids) when is_binary(scope_ids), do: scope_ids
  defp scope_ids_attr(_scope_ids), do: ""
end
