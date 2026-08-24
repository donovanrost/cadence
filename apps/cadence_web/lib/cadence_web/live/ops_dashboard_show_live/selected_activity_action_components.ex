defmodule CadenceWeb.OpsDashboardShowLive.SelectedActivityActionComponents do
  @moduledoc false
  use CadenceWeb, :html

  alias CadenceWeb.OpsDashboardShowLive.ActivityNavigation
  alias CadenceWeb.OpsDashboardShowLive.VersionActionNavigation

  attr :summary, :map, required: true
  attr :readiness_return_intent, :string, default: nil

  def readiness_return_prompt(assigns) do
    presentation =
      if selected_activity_readiness_return?(
           assigns.summary,
           assigns.readiness_return_intent
         ) do
        readiness_return_presentation(assigns.summary, assigns.readiness_return_intent)
      end

    assigns = assign(assigns, :presentation, presentation)

    ~H"""
    <.vue
      :if={@presentation}
      id="dashboard-selected-activity-readiness-return-component"
      v-component="SelectedActivityActions"
      presentation={@presentation}
      v-ssr={false}
      class="contents"
    />
    """
  end

  attr :summary, :map, required: true

  def source_actions(assigns) do
    presentation =
      if selected_activity_source_actions?(assigns.summary) do
        source_actions_presentation(assigns.summary)
      end

    assigns = assign(assigns, :presentation, presentation)

    ~H"""
    <.vue
      :if={@presentation}
      id="dashboard-selected-activity-source-actions-component"
      v-component="SelectedActivityActions"
      presentation={@presentation}
      v-ssr={false}
      class="contents"
    />
    """
  end

  attr :summary, :map, required: true
  attr :dashboard_current_path, :string, required: true

  def recovery_banner(assigns) do
    recovery_href =
      selected_activity_recovery_href(assigns.summary, assigns.dashboard_current_path)

    presentation =
      if recovery_href do
        recovery_presentation(assigns.summary, recovery_href)
      end

    assigns = assign(assigns, :presentation, presentation)

    ~H"""
    <.vue
      :if={@presentation}
      id="dashboard-selected-activity-recovery-component"
      v-component="SelectedActivityActions"
      presentation={@presentation}
      v-ssr={false}
      class="contents"
    />
    """
  end

  attr :summary, :map, required: true
  attr :dashboard_document, :any, required: true

  def remediation_actions(assigns) do
    presentation =
      if assigns.summary.remediation_actions != [] do
        remediation_presentation(assigns.summary, assigns.dashboard_document)
      end

    assigns = assign(assigns, :presentation, presentation)

    ~H"""
    <.vue
      :if={@presentation}
      id="dashboard-selected-activity-remediation-component"
      v-component="SelectedActivityActions"
      presentation={@presentation}
      v-ssr={false}
      class="contents"
    />
    """
  end

  defp readiness_return_presentation(summary, readiness_return_intent) do
    %{
      kind: "readiness_return",
      visible: true,
      root: %{
        id: "dashboard-selected-activity-readiness-return",
        class:
          "mt-2 flex flex-wrap items-center gap-2 border-l-2 border-primary/70 pl-2 text-base-content/70",
        attrs: %{
          "data-dashboard-selected-activity-readiness-return" =>
            dom_attr_value(readiness_return_intent),
          "data-dashboard-selected-activity-readiness-return-event" =>
            dom_attr_value(summary.event_id)
        }
      },
      message: %{
        class: "min-w-0 flex-1",
        text:
          "Source evidence changed or was reviewed. Re-check publish readiness before publishing this draft."
      },
      action: %{
        type: "button",
        class:
          "inline-flex items-center gap-1 text-xs font-semibold text-primary hover:text-primary-focus",
        text: "Re-check readiness",
        icon: %{name: "hero-arrow-path", class: "h-3 w-3"},
        attrs: %{
          "phx-click" => "refresh_publish_readiness",
          "data-dashboard-selected-activity-readiness-return-refresh" =>
            dom_attr_value(summary.event_id)
        }
      }
    }
  end

  defp source_actions_presentation(summary) do
    %{
      kind: "source_actions",
      visible: true,
      root: %{
        id: "dashboard-selected-activity-source-actions",
        class: "mt-2 space-y-1 border-l-2 border-success/70 pl-2 text-base-content/70",
        attrs: %{
          "data-dashboard-selected-activity-source-actions" =>
            dom_attr_value(summary.source_actions.count_text),
          "data-dashboard-selected-activity-source-action-latest-kind" =>
            dom_attr_value(summary.source_actions.latest.kind),
          "data-dashboard-selected-activity-source-action-latest-at" =>
            dom_attr_value(summary.source_actions.latest.occurred_at)
        }
      },
      latest: %{
        class: "font-semibold",
        text: dom_text(summary.source_actions.latest.message)
      },
      rows:
        summary.source_actions.rows
        |> Enum.with_index()
        |> Enum.map(fn {source_action, index} -> source_action_row(source_action, index) end)
    }
  end

  defp source_action_row(source_action, index) do
    source_value = source_action.source
    source_text = dom_text(source_value)

    %{
      key: "source-action-#{index}",
      class: "flex flex-wrap items-center gap-x-2 gap-y-0.5",
      attrs: %{
        "data-dashboard-selected-activity-source-action" => dom_attr_value(source_action.kind),
        "data-dashboard-selected-activity-source-action-at" =>
          dom_attr_value(source_action.occurred_at),
        "data-dashboard-selected-activity-source-action-source" => dom_attr_value(source_value)
      },
      message: %{text: dom_text(source_action.message)},
      occurred_at: %{
        class: "font-mono text-base-content/60",
        text: dom_text(source_action.occurred_at)
      },
      source: %{
        visible: source_value != "",
        class: "font-mono text-base-content/60",
        text: source_text
      }
    }
  end

  defp recovery_presentation(summary, recovery_href) do
    %{
      kind: "recovery",
      visible: true,
      root: %{
        id: "dashboard-selected-activity-recovery",
        class:
          "mt-2 flex flex-wrap items-center gap-2 border-l-2 border-warning/70 pl-2 text-base-content/70",
        attrs: %{
          "data-dashboard-selected-activity-recovery" =>
            dom_attr_value(summary.filter_state_text),
          "data-dashboard-selected-activity-recovery-href" => dom_attr_value(recovery_href)
        }
      },
      message: %{
        class: "min-w-0 flex-1",
        text: selected_activity_recovery_message(summary)
      },
      action: %{
        id: "dashboard-selected-activity-recovery-link",
        href: recovery_href,
        navigation_kind: "navigate",
        class:
          "inline-flex items-center gap-1 font-semibold text-primary hover:text-primary-focus",
        text: selected_activity_recovery_label(summary),
        icon: %{name: selected_activity_recovery_icon(summary), class: "h-3 w-3"},
        attrs: %{
          "data-phx-link" => "redirect",
          "data-phx-link-state" => "push"
        }
      }
    }
  end

  defp remediation_presentation(summary, dashboard_document) do
    %{
      kind: "remediation",
      visible: true,
      root: %{class: "mt-3 space-y-2"},
      heading: %{class: "hud-label", text: "Remediation"},
      rows:
        summary.remediation_actions
        |> Enum.with_index()
        |> Enum.map(fn {action, index} ->
          remediation_row(action, dashboard_document, summary, index)
        end)
    }
  end

  defp remediation_row(action, dashboard_document, summary, index) do
    label = dom_text(Map.get(action, :label))
    target = dom_text(Map.get(action, :target))
    message = Map.get(action, :message)

    %{
      key: "remediation-action-#{index}",
      class: "border-l-2 border-info/70 pl-2",
      attrs: %{
        "data-dashboard-selected-activity-remediation" => label,
        "data-dashboard-selected-activity-remediation-target" => target,
        "data-dashboard-selected-activity-remediation-issue" =>
          dom_attr_value(Map.get(action, :issue_id) || "")
      },
      label: %{class: "font-semibold", text: label},
      message: %{
        visible: message not in [nil, false],
        class: "mt-0.5 text-base-content/70",
        text: dom_text(message)
      },
      action: remediation_link(action, dashboard_document, summary)
    }
  end

  defp remediation_link(action, dashboard_document, summary) do
    href = selected_activity_action_href(action, dashboard_document, summary)
    label = dom_text(Map.get(action, :label))

    case {Map.get(action, :target), href} do
      {"data_sources", href} when href not in [nil, false] ->
        %{
          href: href,
          navigation_kind: "navigate",
          class:
            "mt-1 inline-flex items-center gap-1 font-semibold text-primary hover:text-primary-focus",
          text: "Open Data Sources",
          icon: %{name: "hero-arrow-top-right-on-square", class: "h-3 w-3"},
          attrs: %{
            "data-dashboard-selected-activity-remediation-link" => label,
            "data-dashboard-selected-activity-remediation-href" => dom_attr_value(href),
            "data-phx-link" => "redirect",
            "data-phx-link-state" => "push"
          }
        }

      {"dashboard_editor", href} when href not in [nil, false] ->
        %{
          href: href,
          navigation_kind: "patch",
          class:
            "mt-1 inline-flex items-center gap-1 font-semibold text-primary hover:text-primary-focus",
          text: "Open Widget Editor",
          icon: %{name: "hero-pencil-square", class: "h-3 w-3"},
          attrs: %{
            "data-dashboard-selected-activity-remediation-link" => label,
            "data-dashboard-selected-activity-remediation-href" => dom_attr_value(href),
            "data-phx-link" => "patch",
            "data-phx-link-state" => "push"
          }
        }

      _other ->
        nil
    end
  end

  defp selected_activity_action_href(action, dashboard_document, summary) do
    VersionActionNavigation.selected_activity_action_href(
      action,
      dashboard_document,
      summary
    )
  end

  defp selected_activity_recovery_href(%{filter_state: :hidden, event_id: event_id}, current_path)
       when is_binary(event_id) and event_id != "" and is_binary(current_path) do
    ActivityNavigation.link(current_path, :all, event_id)
  end

  defp selected_activity_recovery_href(%{filter_state: :missing}, current_path)
       when is_binary(current_path) do
    ActivityNavigation.link(current_path, :all, nil)
  end

  defp selected_activity_recovery_href(_summary, _current_path), do: nil

  defp selected_activity_recovery_message(%{filter_state: :hidden}),
    do: "This event exists but is hidden by the current activity filter."

  defp selected_activity_recovery_message(%{filter_state: :missing}),
    do: "This event is no longer available in the dashboard activity log."

  defp selected_activity_recovery_message(_summary), do: nil

  defp selected_activity_recovery_label(%{filter_state: :hidden}), do: "Show all activity"
  defp selected_activity_recovery_label(%{filter_state: :missing}), do: "Clear selection"
  defp selected_activity_recovery_label(_summary), do: nil

  defp selected_activity_recovery_icon(%{filter_state: :hidden}), do: "hero-list-bullet"
  defp selected_activity_recovery_icon(%{filter_state: :missing}), do: "hero-x-mark"
  defp selected_activity_recovery_icon(_summary), do: "hero-arrow-top-right-on-square"

  defp selected_activity_readiness_return?(
         %{found?: true, event_type_text: "publish_readiness_checked"},
         "source_return"
       ),
       do: true

  defp selected_activity_readiness_return?(_summary, _intent), do: false

  defp selected_activity_source_actions?(%{source_actions: %{present?: true}}), do: true
  defp selected_activity_source_actions?(_summary), do: false

  defp dom_attr_value(nil), do: nil
  defp dom_attr_value(value), do: dom_text(value)

  defp dom_text(nil), do: ""
  defp dom_text(value) when is_binary(value), do: value
  defp dom_text(value) when is_atom(value), do: Atom.to_string(value)
  defp dom_text(value), do: to_string(value)
end
