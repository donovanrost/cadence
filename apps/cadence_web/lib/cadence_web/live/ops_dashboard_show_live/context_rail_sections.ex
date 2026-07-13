defmodule CadenceWeb.OpsDashboardShowLive.ContextRailSections do
  @moduledoc """
  Assembles the ops context rail for the dashboard show page. The rail is
  permanent infrastructure for contextual widgets; dashboard-wide health
  remains in the toolbar instead of being duplicated here.
  """

  use CadenceWeb, :html

  import CadenceWeb.OpsDashboardShowLive.Components,
    only: [
      comparison_rollup_strip: 1
    ]

  attr :render_model, :map, required: true

  def dashboard_context_rail(assigns) do
    ~H"""
    <.ops_context_rail id="ops-context-rail">
      <:section
        key="comparison"
        title="Compare"
        icon="hero-scale"
        status={rollup_status(@render_model.comparison_rollup)}
        count={rollup_count(@render_model.comparison_rollup)}
        visible={rollup_visible?(@render_model)}
      >
        <.comparison_rollup_strip
          rollup={@render_model.comparison_rollup}
          preset={@render_model.comparison_preset}
          open_review_summary={@render_model.open_review_summary}
          saved_presets={@render_model.comparison_presets}
        />
      </:section>
    </.ops_context_rail>
    """
  end

  defp rollup_visible?(render_model) do
    value(render_model.comparison_rollup, :visible?) == true or
      render_model.comparison_presets != []
  end

  defp rollup_status(rollup) do
    open = value(rollup, :open_count) || 0

    cond do
      open > 0 -> :warning
      value(rollup, :visible?) == true -> :info
      true -> nil
    end
  end

  defp rollup_count(rollup), do: positive_or_nil(value(rollup, :open_count))

  defp positive_or_nil(count) when is_integer(count) and count > 0, do: count
  defp positive_or_nil(_count), do: nil

  defp value(map, key) when is_map(map), do: Map.get(map, key)
  defp value(_map, _key), do: nil
end
