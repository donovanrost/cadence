defmodule CadenceWeb.OpsDashboardShowLive.SelectedActivityComponents do
  @moduledoc false
  use CadenceWeb, :html

  alias CadenceWeb.OpsDashboardShowLive.SelectedActivityActionComponents

  attr(:summary, :map, required: true)
  attr(:dashboard_document, :any, required: true)
  attr(:dashboard_current_path, :string, required: true)
  attr(:readiness_return_intent, :string, default: nil)

  def selected_activity_event_summary(assigns) do
    presentation =
      presentation(
        assigns.summary,
        assigns.dashboard_document,
        assigns.dashboard_current_path,
        assigns.readiness_return_intent
      )

    assigns = assign(assigns, :presentation, presentation)

    ~H"""
    <.vue
      :if={@presentation}
      id="dashboard-selected-activity-event-component"
      v-component="SelectedActivityEventSummary"
      presentation={@presentation}
      v-ssr={false}
      class="contents"
    />
    """
  end

  def presentation(
        summary,
        dashboard_document,
        dashboard_current_path,
        readiness_return_intent \\ nil
      )

  def presentation(
        %{render?: false},
        _dashboard_document,
        _dashboard_current_path,
        _readiness_return_intent
      ),
      do: nil

  def presentation(
        summary,
        dashboard_document,
        dashboard_current_path,
        readiness_return_intent
      ) do
    %{
      root: %{
        id: "dashboard-selected-activity-event",
        class: [
          "border border-info/40 bg-info/10 px-2 py-2 text-xs",
          summary.visibility_class
        ],
        attrs:
          raw_attributes(%{
            "data-dashboard-selected-activity-event" => dom_attr_value(summary.event_id),
            "data-dashboard-selected-activity-event-found" => dom_attr_value(summary.found_text),
            "data-dashboard-selected-activity-event-visible" =>
              dom_attr_value(summary.visible_text),
            "data-dashboard-selected-activity-event-filter" =>
              dom_attr_value(summary.filter_value),
            "data-dashboard-selected-activity-event-type" =>
              dom_attr_value(summary.event_type_text),
            "data-dashboard-selected-activity-runtime-impact-state" =>
              dom_attr_value(summary.runtime_impact.state),
            "data-dashboard-selected-activity-runtime-impact-invalidation" =>
              dom_attr_value(summary.runtime_impact.invalidation_id),
            "data-dashboard-selected-activity-runtime-impact-context" =>
              dom_attr_value(summary.runtime_impact.context_match),
            "data-dashboard-selected-activity-runtime-impact-refresh" =>
              dom_attr_value(summary.runtime_impact.refresh_allowed)
          })
      },
      header: %{
        class: "flex flex-wrap items-center gap-1.5",
        title: %{
          class: "font-semibold",
          text: dom_text(summary.title),
          attrs: %{"data-dashboard-selected-activity-title" => ""}
        },
        version: selected_activity_version_presentation(summary),
        filter_state: selected_activity_filter_state_presentation(summary),
        readiness_comparison: readiness_comparison_presentation(summary.readiness_comparison),
        refresh: selected_activity_refresh_presentation(summary)
      },
      readiness_return:
        SelectedActivityActionComponents.readiness_return_presentation(
          summary,
          readiness_return_intent
        ),
      source_actions: SelectedActivityActionComponents.source_actions_presentation(summary),
      recovery:
        SelectedActivityActionComponents.recovery_presentation(
          summary,
          dashboard_current_path
        ),
      fields:
        summary.fields
        |> Enum.with_index()
        |> Enum.map(fn {field, index} ->
          %{
            key: "selected-activity-field-#{index}",
            label: dom_text(field.label),
            value: dom_text(field.value),
            label_class: "hud-label",
            value_class: field.class,
            attrs: %{"data-dashboard-selected-activity-field" => dom_attr_value(field.label)}
          }
        end),
      fields_class: "mt-2 grid grid-cols-[6rem_1fr] gap-x-2 gap-y-1",
      remediation:
        SelectedActivityActionComponents.remediation_presentation(
          summary,
          dashboard_document
        )
    }
  end

  defp selected_activity_version_presentation(summary) do
    %{
      visible: summary.found?,
      class: "badge badge-xs badge-outline",
      text: dom_text(summary.version_text),
      attrs: %{"data-dashboard-selected-activity-version" => ""}
    }
  end

  defp selected_activity_filter_state_presentation(%{filter_state: :hidden}) do
    %{
      visible: true,
      class: "badge badge-warning badge-xs",
      text: "Hidden by filter",
      attrs: %{"data-dashboard-selected-activity-filter-state" => "hidden"}
    }
  end

  defp selected_activity_filter_state_presentation(%{filter_state: :missing}) do
    %{
      visible: true,
      class: "badge badge-error badge-xs",
      text: "Event unavailable",
      attrs: %{"data-dashboard-selected-activity-filter-state" => "missing"}
    }
  end

  defp selected_activity_filter_state_presentation(_summary), do: nil

  defp readiness_comparison_presentation(nil), do: nil

  defp readiness_comparison_presentation(comparison) do
    %{
      class: ["badge badge-xs", readiness_comparison_badge_class(comparison)],
      text: dom_text(comparison.label),
      attrs: %{
        "data-dashboard-selected-activity-readiness-trend" => dom_attr_value(comparison.state),
        "data-dashboard-selected-activity-readiness-previous" =>
          dom_attr_value(comparison.previous_event_id)
      }
    }
  end

  defp selected_activity_refresh_presentation(summary) do
    if selected_activity_readiness_check?(summary) do
      %{
        id: "dashboard-selected-activity-refresh-readiness",
        type: "button",
        class:
          "inline-flex items-center gap-1 text-xs font-semibold text-primary hover:text-primary-focus",
        text: "Re-check",
        icon: %{name: "hero-arrow-path", class: "h-3 w-3"},
        attrs: %{
          "phx-click" => "refresh_publish_readiness",
          "data-dashboard-selected-activity-refresh-readiness" =>
            dom_attr_value(summary.event_id),
          "data-dashboard-selected-activity-refresh-readiness-state" =>
            dom_attr_value(summary.readiness_comparison && summary.readiness_comparison.state)
        }
      }
    end
  end

  defp selected_activity_readiness_check?(%{
         found?: true,
         event_type_text: "publish_readiness_checked"
       }),
       do: true

  defp selected_activity_readiness_check?(_summary), do: false

  defp readiness_comparison_badge_class(%{state: "improved"}), do: "badge-success"
  defp readiness_comparison_badge_class(%{state: "regressed"}), do: "badge-error"
  defp readiness_comparison_badge_class(%{state: "unchanged"}), do: "badge-warning"
  defp readiness_comparison_badge_class(%{state: "first_check"}), do: "badge-outline"
  defp readiness_comparison_badge_class(_comparison), do: "badge-outline"

  defp raw_attributes(attributes) do
    Enum.reduce(attributes, %{}, fn
      {_key, value}, rendered when value in [nil, false] ->
        rendered

      {key, true}, rendered ->
        Map.put(rendered, to_string(key), "")

      {key, value}, rendered ->
        Map.put(rendered, to_string(key), dom_text(value))
    end)
  end

  defp dom_attr_value(nil), do: nil
  defp dom_attr_value(value), do: dom_text(value)

  defp dom_text(nil), do: ""
  defp dom_text(value) when is_binary(value), do: value
  defp dom_text(value) when is_atom(value), do: Atom.to_string(value)
  defp dom_text(value), do: to_string(value)
end
