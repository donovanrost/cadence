defmodule CadenceWeb.OpsDashboardShowLive.RenderSourceAssigns do
  @moduledoc false

  alias CadenceWeb.OpsDashboardShowLive.SourcePresentation

  @spec normalize(Phoenix.LiveView.Socket.t() | map()) :: map()
  def normalize(%{assigns: assigns}) when is_map(assigns), do: assigns
  def normalize(assigns) when is_map(assigns), do: assigns

  @spec dashboard_warning_context(Phoenix.LiveView.Socket.t() | map()) :: map()
  def dashboard_warning_context(socket_or_assigns) do
    context = source_context(socket_or_assigns)

    %{
      warnings: context.dashboard_warnings,
      degraded?: context.dashboard_degraded?
    }
  end

  @spec source_health_context(Phoenix.LiveView.Socket.t() | map()) :: map()
  def source_health_context(socket_or_assigns) do
    context = source_context(socket_or_assigns)

    %{health: context.source_health}
  end

  @spec source_selection_context(Phoenix.LiveView.Socket.t() | map()) :: map()
  def source_selection_context(socket_or_assigns) do
    context = source_context(socket_or_assigns)

    %{selections: context.source_selections}
  end

  @spec source_context(Phoenix.LiveView.Socket.t() | map()) :: map()
  def source_context(socket_or_assigns) do
    assigns = normalize(socket_or_assigns)
    engine_result = Map.get(assigns, :dashboard_engine_result)

    %{
      dashboard_warnings:
        list_or_default(
          Map.get(assigns, :dashboard_warning_summaries),
          fn -> SourcePresentation.dashboard_warning_summaries(engine_result) end
        ),
      dashboard_degraded?:
        boolean_or_default(
          Map.get(assigns, :dashboard_degraded?),
          fn -> SourcePresentation.dashboard_degraded?(engine_result) end
        ),
      source_health:
        list_or_default(
          Map.get(assigns, :dashboard_source_health_summaries),
          fn -> SourcePresentation.source_health_summaries(engine_result) end
        ),
      source_selections:
        list_or_default(
          Map.get(assigns, :dashboard_source_selection_summaries),
          fn -> SourcePresentation.source_selection_summaries(engine_result) end
        )
    }
  end

  defp list_or_default(value, _fallback) when is_list(value), do: value
  defp list_or_default(_value, fallback) when is_function(fallback, 0), do: fallback.()

  defp boolean_or_default(value, _fallback) when is_boolean(value), do: value
  defp boolean_or_default(_value, fallback) when is_function(fallback, 0), do: fallback.()
end
