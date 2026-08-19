defmodule CadenceWeb.OpsDashboardShowLive.RuntimeInvalidations do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]

  alias Cadence.Projections.DashboardRuntimeInvalidations, as: DashboardRuntimeInvalidations

  alias Cadence.Telemetry.RuntimeHealth, as: RuntimeHealth

  alias Cadence.Dashboards.{
    Document,
    ResolutionContext,
    RuntimeCache,
    RuntimeInvalidation,
    RuntimeInvalidationRelevance
  }

  alias Cadence.Dashboards.RuntimeInvalidation.Event
  alias CadenceWeb.OpsDashboardShowLive.Runtime
  alias CadenceWeb.OpsDashboardShowLive.RuntimeAssigns
  alias CadenceWeb.OpsDashboardShowLive.RuntimeCacheDiagnostics
  alias CadenceWeb.OpsDashboardShowLive.RuntimeInvalidationDiagnostics
  alias CadenceWeb.OpsDashboardShowLive.RuntimeSourceExecutionDiagnostics
  alias CadenceWeb.OpsDashboardShowLive.SelectedDataRef
  alias CadenceWeb.OpsDashboardShowLive.SourceExecutionRuntimeSummary

  def handle_invalidation(socket, invalidation, opts \\ []) do
    %{current_scope: scope, current_mission: mission, dashboard_document: document} =
      socket.assigns

    runtime_context = context(socket)

    event_relevance =
      RuntimeInvalidationRelevance.event_relevance(
        invalidation,
        scope,
        mission,
        document,
        runtime_context
      )

    refresh_relevance =
      RuntimeInvalidationRelevance.refresh_relevance(invalidation, runtime_context)

    emit_decision(invalidation, socket, event_relevance, refresh_relevance, opts)

    # Edit mode pauses all data-driven assigns (see DashboardGrid hook): even
    # the notice strip must not patch the DOM while GridStack owns it. The
    # exit-edit resolve re-syncs everything that happened meanwhile.
    if event_relevance.matches? and not editing?(socket) do
      socket =
        assign(
          socket,
          :dashboard_last_runtime_invalidation,
          RuntimeInvalidationRelevance.notice(invalidation)
        )

      if refresh_relevance.allowed? do
        resolve_engine(socket, invalidation, opts)
      else
        socket
      end
    else
      socket
    end
  end

  def subscribe(current_scope, mission, %Document{} = document) do
    RuntimeInvalidation.subscribe(%{
      organization_id: current_scope.organization_id,
      mission_id: mission.mission_id,
      dashboard_id: document.dashboard_id
    })
  end

  def summary(events, current_scope, mission, %Document{} = document) do
    RuntimeInvalidationDiagnostics.summary(events, current_scope, mission, document)
  end

  def recent_events do
    RuntimeHealth.snapshot().recent_events
  rescue
    _error -> []
  catch
    :exit, _reason -> []
  end

  def context(socket), do: context_from_assigns(socket.assigns)

  defp editing?(socket), do: Map.get(socket.assigns, :edit_mode?, false)

  def context_from_assigns(assigns) do
    RuntimeAssigns.runtime_invalidation_context(assigns)
  end

  def boundary_summary(summary), do: RuntimeInvalidationRelevance.boundary_summary(summary)

  def notice_boundary(notice), do: RuntimeInvalidationRelevance.notice_boundary(notice)

  def notice_refresh_reason(notice),
    do: RuntimeInvalidationRelevance.notice_refresh_reason(notice)

  def notice_refresh_action(notice),
    do: RuntimeInvalidationRelevance.notice_refresh_action(notice)

  def decision(invalidation, socket, event_relevance, refresh_relevance) do
    affected_placements =
      RuntimeInvalidationRelevance.affected_placements(
        invalidation,
        socket.assigns.dashboard_document
      )

    affected_placement_summary =
      RuntimeInvalidationRelevance.affected_placement_summary(affected_placements)

    %{
      dashboard_id: socket.assigns.dashboard_document.dashboard_id,
      organization_id: socket.assigns.current_scope.organization_id,
      mission_id: socket.assigns.current_mission.mission_id,
      affected_placement_count: affected_placement_summary.count,
      affected_placement_ids: affected_placement_summary.placement_ids,
      affected_widget_type_ids: affected_placement_summary.widget_type_ids,
      affected_impact_reasons: affected_placement_summary.impact_reasons,
      matches?: event_relevance.matches?,
      dashboard_matches?: event_relevance.dashboard_matches?,
      context_matches?: event_relevance.context_matches?,
      context_reason: event_relevance.reason,
      refresh_allowed?: refresh_relevance.allowed?,
      refresh_reason: refresh_relevance.reason,
      decision_status:
        RuntimeInvalidationDiagnostics.decision_status(event_relevance, refresh_relevance)
    }
    |> Map.merge(selection_decision(socket, event_relevance, affected_placement_summary))
    |> Map.merge(
      RuntimeCacheDiagnostics.source_cache_evidence_audit(
        socket.assigns[:dashboard_engine_result]
      )
    )
    |> Map.merge(
      socket.assigns[:dashboard_engine_result]
      |> SourceExecutionRuntimeSummary.build()
      |> RuntimeSourceExecutionDiagnostics.decision_audit_from_summary()
    )
  end

  defp selection_decision(socket, event_relevance, affected_placement_summary) do
    selected_ref = socket.assigns[:dashboard_selected_data_ref]
    selection_state = socket.assigns[:dashboard_selection_state]

    %{
      selection_state: selection_state,
      selected_link_id: selected_value(selected_ref, "link_id"),
      selected_target: selected_value(selected_ref, "target"),
      selected_target_id: selected_value(selected_ref, "target_id"),
      selected_placement_id: selected_placement_id(selected_ref),
      selected_observable_id: SelectedDataRef.observable_id(selected_ref),
      selected_data_view: selected_value(selected_ref, "data_view"),
      selection_affected?:
        selection_affected?(selected_ref, event_relevance, affected_placement_summary),
      selection_impact_reason:
        selection_impact_reason(selected_ref, event_relevance, affected_placement_summary)
    }
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Map.new()
  end

  defp selected_placement_id(selected_ref) do
    SelectedDataRef.value(selected_ref, "placement_id") ||
      comparison_finding_placement_id(selected_ref)
  end

  defp comparison_finding_placement_id(selected_ref) do
    if SelectedDataRef.value(selected_ref, "target") == "comparison_finding" do
      SelectedDataRef.value(selected_ref, "target_id")
    end
  end

  defp selected_value(selected_ref, key), do: SelectedDataRef.value(selected_ref, key)

  defp selection_affected?(selected_ref, event_relevance, affected_placement_summary) do
    case selection_impact_reason(selected_ref, event_relevance, affected_placement_summary) do
      :affected_placement -> true
      :affected_dashboard -> true
      :matched_without_placement -> true
      _reason -> false
    end
  end

  defp selection_impact_reason(nil, _event_relevance, _affected_placement_summary),
    do: :no_selection

  defp selection_impact_reason(selected_ref, %{matches?: false}, _affected_placement_summary)
       when is_map(selected_ref),
       do: :filtered

  defp selection_impact_reason(selected_ref, _event_relevance, %{
         placement_ids: placement_ids,
         count: count
       })
       when is_map(selected_ref) do
    selected_placement_id = selected_placement_id(selected_ref)

    cond do
      selected_placement_id in List.wrap(placement_ids) ->
        :affected_placement

      count == 0 and is_nil(selected_placement_id) ->
        :matched_without_placement

      count == 0 ->
        :affected_dashboard

      true ->
        :unaffected_placement
    end
  end

  defp selection_impact_reason(_selected_ref, _event_relevance, _affected_placement_summary),
    do: :no_selection

  defp resolve_engine(socket, invalidation, opts) do
    remount_charts_after_resolve? = RuntimeInvalidationRelevance.remounts_charts?(invalidation)

    resolve_opts = [
      reason: :runtime_invalidation,
      remount_charts_after_resolve?: remount_charts_after_resolve?
    ]

    case Keyword.get(opts, :resolve_engine) do
      callback when is_function(callback, 3) ->
        callback.(socket, :context_change, resolve_opts)

      _missing ->
        Runtime.resolve_engine(socket, :context_change, resolve_opts)
    end
  end

  defp emit_decision(%Event{} = invalidation, socket, event_relevance, refresh_relevance, opts) do
    decision = decision(invalidation, socket, event_relevance, refresh_relevance)

    emit_opts = [
      invalidation_event_id: RuntimeInvalidationDiagnostics.event_id(invalidation),
      runtime_cache: runtime_cache_server(socket)
    ]

    case Keyword.get(opts, :emit_decision) do
      callback when is_function(callback, 3) ->
        callback.(invalidation, decision, emit_opts)

      _missing ->
        RuntimeInvalidation.emit_decision(invalidation, decision, emit_opts)

        DashboardRuntimeInvalidations.record(
          invalidation,
          decision,
          emit_opts
        )
    end
  rescue
    _error -> :ok
  catch
    :exit, _reason -> :ok
  end

  defp emit_decision(_invalidation, _socket, _event_relevance, _refresh_relevance, _opts), do: :ok

  defp runtime_cache_server(%{assigns: assigns}) do
    case Map.get(assigns, :dashboard_resolution_context) do
      %ResolutionContext{runtime_cache: %RuntimeCache{} = cache} -> RuntimeCache.server(cache)
      _missing -> nil
    end
  end
end
