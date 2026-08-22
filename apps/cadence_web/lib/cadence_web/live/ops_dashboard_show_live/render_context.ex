defmodule CadenceWeb.OpsDashboardShowLive.RenderContext do
  @moduledoc false

  alias CadenceWeb.OpsDashboardShowLive.RenderPageModel
  alias CadenceWeb.OpsDashboardShowLive.RenderRuntimeAssigns
  alias CadenceWeb.OpsDashboardShowLive.RuntimeDiagnostics
  alias CadenceWeb.OpsDashboardShowLive.RuntimeInvalidations

  def model(assigns, opts \\ []) when is_map(assigns) do
    assigns
    |> build(opts)
    |> Map.fetch!(:model)
  end

  def build(assigns, opts \\ []) when is_map(assigns) do
    runtime_invalidation_events =
      Keyword.get_lazy(opts, :runtime_invalidation_events, &RuntimeInvalidations.recent_events/0)

    runtime_summary_context = RenderRuntimeAssigns.runtime_summary_context(assigns)

    runtime_invalidation =
      RuntimeInvalidations.summary(
        runtime_invalidation_events,
        runtime_summary_context.current_scope,
        runtime_summary_context.mission,
        runtime_summary_context.document
      )

    runtime_diagnostics =
      assigns
      |> RenderRuntimeAssigns.runtime_diagnostics_context(
        runtime_invalidation,
        runtime_invalidation_events
      )
      |> RuntimeDiagnostics.build()

    %{
      runtime_invalidation_events: runtime_invalidation_events,
      runtime_invalidation: runtime_invalidation,
      runtime_diagnostics: runtime_diagnostics,
      model: RenderPageModel.build(assigns, runtime_diagnostics, runtime_invalidation)
    }
  end
end
