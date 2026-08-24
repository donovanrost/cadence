defmodule CadenceWeb.OpsDashboardShowLive.VersionHistoryPanelComponents do
  @moduledoc false
  use CadenceWeb, :html

  alias CadenceWeb.OpsDashboardShowLive.ActivityTimelineComponents
  alias CadenceWeb.OpsDashboardShowLive.PublishValidationComponents
  alias CadenceWeb.OpsDashboardShowLive.VersionHistoryPresentation
  alias CadenceWeb.OpsDashboardShowLive.VersionListComponents

  attr(:dashboard_document, :any, required: true)
  attr(:dashboard_summary, :any, required: true)
  attr(:dashboard_versions, :list, required: true)
  attr(:dashboard_lifecycle_events, :list, required: true)
  attr(:dashboard_comparison_review_queue, :map, default: nil)
  attr(:dashboard_source_action_events, :list, default: [])
  attr(:dashboard_recent_invalidations, :list, default: [])
  attr(:dashboard_activity_filter, :atom, default: nil)
  attr(:dashboard_activity_event_id, :string, default: nil)
  attr(:dashboard_review_placement_id, :string, default: nil)
  attr(:dashboard_readiness_return_intent, :string, default: nil)
  attr(:dashboard_selected_publish_issue_id, :string, default: nil)
  attr(:dashboard_comparison_review_action_outcome, :map, default: nil)
  attr(:dashboard_publish_readiness, :map, default: nil)
  attr(:dashboard_current_path, :string, required: true)

  def versions_panel(assigns) do
    assigns = assign(assigns, :presentation, presentation(assigns))

    ~H"""
    <.vue
      id="dashboard-version-history-panel-component"
      v-component="VersionHistoryPanel"
      presentation={@presentation}
      v-ssr={false}
      class="contents"
    />
    """
  end

  def presentation(assigns) do
    version_history =
      VersionHistoryPresentation.build(assigns.dashboard_summary, assigns.dashboard_versions)

    %{
      root: %{
        attrs: %{
          "id" => "dashboard-versions-panel",
          "class" => "space-y-5"
        }
      },
      version_history_summary: %{
        root: %{
          attrs: %{
            "id" => "dashboard-version-history-summary-component",
            "class" => "contents"
          }
        },
        presentation: version_history_summary_presentation(assigns, version_history)
      },
      activity_timeline: %{
        root: %{
          attrs: %{
            "id" => "dashboard-activity-timeline-component",
            "class" => "contents"
          }
        },
        presentation: ActivityTimelineComponents.presentation(assigns)
      }
    }
  end

  defp version_history_summary_presentation(assigns, version_history) do
    %{
      version_list: VersionListComponents.version_overview_presentation(version_history),
      publish_validation:
        PublishValidationComponents.publish_validation_presentation(
          assigns.dashboard_publish_readiness,
          assigns.dashboard_selected_publish_issue_id,
          assigns.dashboard_document,
          assigns.dashboard_current_path
        ),
      publish_impact:
        publish_impact_presentation(version_history.runtime_defaults.publish_impact),
      runtime_defaults: runtime_defaults_presentation(version_history.runtime_defaults)
    }
  end

  defp publish_impact_presentation(%{present?: false}), do: nil

  defp publish_impact_presentation(impact) do
    %{
      root: %{
        attrs: %{
          "id" => "dashboard-publish-impact",
          "data-dashboard-publish-impact-state" => impact.state,
          "data-dashboard-publish-impact-severity" => impact.severity,
          "data-dashboard-publish-impact-from-version" => impact.from.version_text,
          "data-dashboard-publish-impact-to-version" => impact.to.version_text,
          "data-dashboard-publish-impact-from-realm" => impact.from.realm,
          "data-dashboard-publish-impact-to-realm" => impact.to.realm,
          "data-dashboard-publish-impact-from-source-binding" => impact.from.source_binding_attr,
          "data-dashboard-publish-impact-to-source-binding" => impact.to.source_binding_attr,
          "data-dashboard-publish-impact-from-data-view" => impact.from.data_view,
          "data-dashboard-publish-impact-to-data-view" => impact.to.data_view,
          "class" => "space-y-2 border border-base-300/70 bg-base-100/40 p-2"
        }
      },
      header: %{
        attrs: %{"class" => "flex items-center justify-between gap-3"},
        heading: %{attrs: %{"class" => "hud-label"}, text: "Publish Impact"},
        badge: %{
          attrs: %{
            "class" => "badge badge-xs #{publish_impact_badge_class(impact.severity)}",
            "data-dashboard-publish-impact-label" => impact.label
          },
          text: impact.label
        }
      },
      message: %{
        attrs: %{
          "class" => "text-xs text-base-content/70",
          "data-dashboard-publish-impact-message" => ""
        },
        text: impact.message
      }
    }
  end

  defp publish_impact_badge_class("warning"), do: "badge-warning"
  defp publish_impact_badge_class("success"), do: "badge-success"
  defp publish_impact_badge_class("info"), do: "badge-info"
  defp publish_impact_badge_class(_severity), do: "badge-ghost"

  defp runtime_defaults_presentation(%{present?: false}), do: nil

  defp runtime_defaults_presentation(summary) do
    %{
      root: %{
        attrs: %{
          "id" => "dashboard-runtime-defaults-summary",
          "data-dashboard-runtime-defaults-differ" => summary.differ_text,
          "data-dashboard-runtime-defaults-published-version" => summary.published.version_text,
          "data-dashboard-runtime-defaults-draft-version" => summary.draft.version_text,
          "data-dashboard-runtime-defaults-published-realm" => summary.published.realm,
          "data-dashboard-runtime-defaults-draft-realm" => summary.draft.realm,
          "data-dashboard-runtime-defaults-published-source-binding" =>
            summary.published.source_binding_attr,
          "data-dashboard-runtime-defaults-draft-source-binding" =>
            summary.draft.source_binding_attr,
          "data-dashboard-runtime-defaults-published-data-source" =>
            summary.published.data_source_attr,
          "data-dashboard-runtime-defaults-draft-data-source" => summary.draft.data_source_attr,
          "data-dashboard-runtime-defaults-published-data-view" => summary.published.data_view,
          "data-dashboard-runtime-defaults-draft-data-view" => summary.draft.data_view,
          "class" => "space-y-2 border border-base-300/70 bg-base-100/40 p-2"
        }
      },
      header: %{
        attrs: %{"class" => "flex items-center justify-between gap-3"},
        heading: %{attrs: %{"class" => "hud-label"}, text: "Runtime Defaults"},
        badge: %{
          attrs: %{
            "class" =>
              "badge badge-xs #{if(summary.differ?, do: "badge-warning", else: "badge-success")}",
            "data-dashboard-runtime-defaults-status" => summary.status_label
          },
          text: summary.status_label
        }
      },
      contexts: %{
        attrs: %{"class" => "grid gap-2 md:grid-cols-2"},
        items: [
          runtime_default_context_presentation("Published", summary.published, 0),
          runtime_default_context_presentation("Draft", summary.draft, 1)
        ]
      }
    }
  end

  defp runtime_default_context_presentation(label, context, order) do
    %{
      key: String.downcase(label),
      order: order,
      attrs: %{
        "class" => "grid grid-cols-[5.5rem_1fr] gap-x-2 gap-y-1 text-xs",
        "data-dashboard-runtime-default-context" => label
      },
      rows: [
        runtime_default_row("version", 0, label, "Version", context.version_text),
        runtime_default_row("realm", 1, "Realm", "Realm", context.realm),
        runtime_default_row(
          "source",
          2,
          "Source",
          "Source",
          context.source_binding_text,
          "truncate font-mono text-base-content/70"
        ),
        runtime_default_row("view", 3, "View", "View", context.data_view)
      ]
    }
  end

  defp runtime_default_row(
         key,
         order,
         label,
         field,
         value,
         value_class \\ "font-mono text-base-content/70"
       ) do
    %{
      key: key,
      order: order,
      label: %{attrs: %{"class" => "hud-label"}, text: label},
      value: %{
        attrs: %{"data-runtime-default-field" => field, "class" => value_class},
        text: value
      }
    }
  end
end
