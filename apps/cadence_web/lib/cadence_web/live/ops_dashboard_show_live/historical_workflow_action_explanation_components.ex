defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowActionExplanationComponents do
  @moduledoc false
  use CadenceWeb, :html

  alias CadenceWeb.OpsDashboardShowLive.DataLinkInspectorPanelPresentation

  attr :blocked_action_explanations, :list, default: []

  def action_explanations(%{blocked_action_explanations: [_explanation | _rest]} = assigns) do
    assigns =
      assign(
        assigns,
        :presentation,
        presentation(assigns.blocked_action_explanations)
      )

    ~H"""
    <.vue
      id="dashboard-historical-workflow-action-explanations-component"
      v-component="HistoricalWorkflowActionExplanations"
      presentation={@presentation}
      v-ssr={false}
      class="contents"
    />
    """
  end

  def action_explanations(assigns), do: ~H""

  def presentation([_explanation | _rest] = explanations) do
    action_explanations_dto(explanations)
  end

  def presentation(_explanations), do: nil

  defp action_explanations_dto(explanations) do
    %{
      root: %{
        id: "dashboard-historical-workflow-action-explanations",
        class: "space-y-1 rounded border border-base-300/70 bg-base-100/60 p-2 text-xs"
      },
      header: %{
        class: "flex items-center justify-between gap-2",
        heading: %{class: "hud-label", text: "Unavailable Actions"},
        count: %{
          class: "badge badge-xs badge-outline",
          text: Integer.to_string(length(explanations))
        }
      },
      items_container: %{class: "space-y-1"},
      items:
        explanations
        |> Enum.with_index()
        |> Enum.map(fn {explanation, index} -> action_explanation_dto(explanation, index) end)
    }
  end

  defp action_explanation_dto(explanation, index) do
    state_summary = Map.get(explanation, :state_summary)
    available_when = Map.get(explanation, :available_when)

    %{
      key: "historical-workflow-action-explanation-#{index}",
      class: "rounded border border-base-300/60 bg-base-200/40 px-2 py-1",
      attrs: action_explanation_attrs(explanation),
      header: %{class: "flex items-center justify-between gap-2"},
      label: %{
        class: "font-mono text-base-content",
        text: dom_text(Map.get(explanation, :label))
      },
      reason: %{
        class: "font-mono text-base-content/60",
        text: dom_text(Map.get(explanation, :reason))
      },
      explanation: %{
        class: "mt-1 text-base-content/75",
        text: dom_text(Map.get(explanation, :explanation))
      },
      state: %{
        visible: DataLinkInspectorPanelPresentation.present_text?(state_summary),
        class: "mt-1 font-mono text-base-content/65",
        text: dom_text(state_summary)
      },
      available_when: %{
        visible: DataLinkInspectorPanelPresentation.present_text?(available_when),
        class: "mt-1 text-base-content/60",
        text: dom_text(available_when)
      }
    }
  end

  defp action_explanation_attrs(explanation) do
    %{
      "data-workflow-action-explanation-id" => Map.get(explanation, :id),
      "data-workflow-action-explanation-kind" => Map.get(explanation, :kind),
      "data-workflow-action-explanation-reason" => Map.get(explanation, :reason),
      "data-workflow-action-explanation-state" => Map.get(explanation, :state_summary)
    }
    |> Enum.reduce(%{}, fn
      {_name, value}, attrs when value in [nil, false] ->
        attrs

      {name, true}, attrs ->
        Map.put(attrs, name, "")

      {name, value}, attrs ->
        Map.put(attrs, name, dom_text(value))
    end)
  end

  defp dom_text(nil), do: ""
  defp dom_text(value) when is_binary(value), do: value
  defp dom_text(value) when is_atom(value), do: Atom.to_string(value)
  defp dom_text(value) when is_number(value), do: to_string(value)
  defp dom_text(value), do: to_string(value)
end
