defmodule CadenceWeb.OpsDashboardShowLive.ContextRailSections do
  @moduledoc """
  Assembles the ops context rail for the dashboard show page: the four
  relocated context strips (dashboard health, source status, source
  selection, comparison rollup) become rail sections, each with a collapsed
  badge (status dot + count) derived from the same props the strips render.
  """

  use CadenceWeb, :html

  import CadenceWeb.OpsDashboardShowLive.Components,
    only: [
      dashboard_health_strip: 1,
      source_health_strip: 1,
      source_selection_strip: 1,
      comparison_rollup_strip: 1
    ]

  attr :render_model, :map, required: true

  def dashboard_context_rail(assigns) do
    ~H"""
    <.ops_context_rail id="ops-context-rail">
      <:section
        key="dashboard_health"
        title="Dashboard health"
        icon="hero-squares-2x2"
        status={health_status(@render_model.dashboard_health)}
        count={health_count(@render_model.dashboard_health)}
        visible={health_visible?(@render_model.dashboard_health)}
      >
        <.dashboard_health_strip health={@render_model.dashboard_health} />
      </:section>

      <:section
        key="source_status"
        title="Source status"
        icon="hero-circle-stack"
        status={source_status(@render_model.source_health_props)}
        count={source_count(@render_model.source_health_props)}
        visible={source_visible?(@render_model.source_health_props)}
      >
        <.source_health_strip {@render_model.source_health_props} />
      </:section>

      <:section
        key="source_selection"
        title="Source selection"
        icon="hero-funnel"
        status={selection_status(@render_model.source_selection_props)}
        count={selection_count(@render_model.source_selection_props)}
        visible={selection_visible?(@render_model.source_selection_props)}
      >
        <.source_selection_strip {@render_model.source_selection_props} />
      </:section>

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

  defp health_visible?(health), do: value(health, :visible?) == true

  defp health_status(health) do
    case value(health, :severity) do
      :error -> :critical
      :warning -> :warning
      :ok -> :nominal
      _other -> nil
    end
  end

  defp health_count(health), do: positive_or_nil(value(health, :affected_count))

  defp source_entries(props), do: (is_map(props) && Map.get(props, :health, [])) || []

  defp source_visible?(props), do: source_entries(props) != []

  defp source_status(props) do
    entries = source_entries(props)

    cond do
      Enum.any?(entries, &(value(&1, :state) == :retention_gap)) -> :critical
      Enum.any?(entries, &(value(&1, :state) in [:stale, :unknown])) -> :warning
      entries != [] -> :nominal
      true -> nil
    end
  end

  defp source_count(props) do
    props
    |> source_entries()
    |> Enum.count(&(value(&1, :state) != :fresh))
    |> positive_or_nil()
  end

  defp selections(props), do: (is_map(props) && Map.get(props, :selections, [])) || []

  defp selection_visible?(props), do: selections(props) != []

  defp selection_status(props) do
    entries = selections(props)

    cond do
      Enum.any?(entries, &(value(&1, :state) == :blocked)) -> :critical
      Enum.any?(entries, &(value(&1, :state) != :selected)) -> :warning
      entries != [] -> :nominal
      true -> nil
    end
  end

  defp selection_count(props), do: positive_or_nil(length(selections(props)))

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
