defmodule CadenceWeb.OpsDashboardShowLive.RenderRuntimeAssigns do
  @moduledoc false

  alias CadenceWeb.OpsDashboardShowLive.RuntimeAssigns

  @spec normalize(Phoenix.LiveView.Socket.t() | map()) :: map()
  def normalize(%{assigns: assigns}) when is_map(assigns), do: assigns
  def normalize(assigns) when is_map(assigns), do: assigns

  @spec runtime_summary_context(Phoenix.LiveView.Socket.t() | map()) :: map()
  def runtime_summary_context(socket_or_assigns) do
    assigns = normalize(socket_or_assigns)

    %{
      current_scope: Map.get(assigns, :current_scope),
      mission: Map.get(assigns, :current_mission),
      document: Map.get(assigns, :dashboard_document)
    }
  end

  @spec runtime_diagnostics_context(Phoenix.LiveView.Socket.t() | map(), map(), [term()]) ::
          map()
  def runtime_diagnostics_context(
        socket_or_assigns,
        runtime_invalidation,
        runtime_invalidation_events
      )
      when is_list(runtime_invalidation_events) do
    assigns = normalize(socket_or_assigns)
    summary_context = runtime_summary_context(assigns)

    %{
      engine_result: Map.get(assigns, :dashboard_engine_result),
      runtime_coordinator: Map.get(assigns, :dashboard_runtime_coordinator),
      decisions: Map.get(assigns, :dashboard_runtime_decisions, []),
      resolved?: Map.get(assigns, :dashboard_runtime_resolved?),
      invalidation: runtime_invalidation,
      last_invalidation: Map.get(assigns, :dashboard_last_runtime_invalidation),
      runtime_invalidation_events: runtime_invalidation_events,
      current_scope: summary_context.current_scope,
      mission: summary_context.mission,
      document: summary_context.document,
      runtime_context: RuntimeAssigns.runtime_invalidation_context(assigns)
    }
  end
end
