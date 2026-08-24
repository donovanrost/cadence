defmodule CadenceWeb.OpsDashboardShowLive.PublishValidationComponents do
  @moduledoc false
  use CadenceWeb, :html

  alias CadenceWeb.OpsDashboardShowLive.VersionActionNavigation

  attr :publish_readiness, :map, default: nil
  attr :selected_publish_issue_id, :string, default: nil
  attr :dashboard_document, :any, required: true
  attr :dashboard_current_path, :string, required: true

  def publish_validation(%{publish_readiness: nil} = assigns), do: ~H""

  def publish_validation(assigns) do
    presentation =
      publish_validation_presentation(
        assigns.publish_readiness,
        assigns.selected_publish_issue_id,
        assigns.dashboard_document,
        assigns.dashboard_current_path
      )

    assigns = assign(assigns, :presentation, presentation)

    ~H"""
    <.vue
      id="dashboard-publish-validation-component"
      v-component="PublishValidation"
      presentation={@presentation}
      v-ssr={false}
      class="contents"
    />
    """
  end

  def publish_validation_presentation(
        nil,
        _selected_publish_issue_id,
        _dashboard_document,
        _dashboard_current_path
      ),
      do: nil

  def publish_validation_presentation(
        publish_readiness,
        selected_publish_issue_id,
        dashboard_document,
        dashboard_current_path
      ) do
    selected_issue_state =
      selected_publish_issue_state(publish_readiness, selected_publish_issue_id)

    publish_validation_dto(
      publish_readiness,
      selected_publish_issue_id,
      selected_issue_state,
      dashboard_document,
      dashboard_current_path
    )
  end

  defp selected_publish_issue_state(publish_readiness, selected_id) do
    cond do
      is_nil(selected_id) or selected_id == "" ->
        "none"

      Enum.any?(publish_readiness.issues, &(&1.id == selected_id)) ->
        "selected"

      true ->
        "resolved"
    end
  end

  defp publish_validation_dto(
         publish_validation,
         selected_issue_id,
         selected_issue_state,
         dashboard_document,
         dashboard_current_path
       ) do
    %{
      root: %{
        id: "dashboard-publish-validation",
        class: "space-y-2 border border-base-300/70 bg-base-100/40 p-2",
        attrs: %{
          "data-publish-validation-status" => dom_attr_value(publish_validation.status),
          "data-publish-validation-selected-issue" => dom_attr_value(selected_issue_id || ""),
          "data-publish-validation-selected-issue-state" => selected_issue_state
        }
      },
      header: %{
        class: "flex items-center justify-between gap-3",
        heading: %{class: "hud-label", text: "Publish Check"},
        controls: %{class: "flex items-center gap-2"},
        refresh: %{
          id: "refresh-publish-readiness",
          type: "button",
          class:
            "inline-flex items-center gap-1 text-xs font-semibold text-primary hover:text-primary-focus",
          text: "Re-check",
          icon: %{name: "hero-arrow-path", class: "h-3 w-3"},
          attrs: %{"phx-click" => "refresh_publish_readiness"}
        },
        badge: %{
          class: class_names(["badge badge-xs", publish_validation.badge_class]),
          text: dom_text(publish_validation.label)
        }
      },
      message: %{
        class: "text-xs text-base-content/70",
        text: dom_text(publish_validation.message)
      },
      result: result_dto(publish_validation.result),
      freshness: freshness_dto(publish_readiness_freshness(publish_validation)),
      resolved_notice: %{
        visible: selected_issue_state == "resolved",
        class: "rounded border border-success/40 bg-success/10 px-2 py-1 text-xs text-success",
        text: "Selected publish issue is no longer present in this check.",
        attrs: %{"data-publish-validation-selected-issue-resolved" => ""}
      },
      issues: %{
        visible: publish_validation.issues != [],
        class: "space-y-1",
        rows:
          publish_validation.issues
          |> Enum.with_index()
          |> Enum.map(fn {issue, index} ->
            issue_dto(
              issue,
              index,
              selected_issue_id,
              dashboard_document,
              dashboard_current_path
            )
          end)
      }
    }
  end

  defp result_dto(result) do
    %{
      id: "dashboard-publish-validation-result",
      class: "border border-base-300/70 bg-base-100/40 px-2 py-1.5 text-xs",
      attrs: %{
        "data-publish-validation-result-state" => dom_attr_value(result.state),
        "data-publish-validation-result-label" => dom_attr_value(result.label)
      },
      label: %{class: "hud-label", text: dom_text(result.label)},
      message: %{class: "text-base-content/70", text: dom_text(result.message)}
    }
  end

  defp publish_readiness_freshness(%{freshness: freshness}), do: freshness
  defp publish_readiness_freshness(_publish_readiness), do: nil

  defp freshness_dto(freshness) when freshness in [nil, false], do: nil

  defp freshness_dto(freshness) do
    %{
      id: "dashboard-publish-validation-freshness",
      class:
        "grid grid-cols-2 gap-2 border border-base-300/70 bg-base-100/40 px-2 py-1.5 text-xs",
      attrs: %{
        "data-publish-validation-freshness-state" => dom_attr_value(freshness.state),
        "data-publish-validation-freshness-reason" =>
          dom_attr_value(Map.get(freshness, :reason) || ""),
        "data-publish-validation-evaluated-at" => dom_attr_value(freshness.evaluated_at),
        "data-publish-validation-draft-version" => dom_attr_value(freshness.draft_version),
        "data-publish-validation-summary-draft-version" =>
          dom_attr_value(freshness.summary_draft_version),
        "data-publish-validation-latest-version" => dom_attr_value(freshness.latest_version),
        "data-publish-validation-published-version" => dom_attr_value(freshness.published_version)
      },
      evaluated: %{
        label: %{class: "hud-label", text: "evaluated"},
        value: %{
          class: "font-mono text-base-content/70",
          text: dom_text(freshness.evaluated_at)
        }
      },
      draft_state: %{
        label: %{class: "hud-label", text: "draft state"},
        value: %{
          class: "font-mono text-base-content/70",
          text: dom_text(freshness.state_label)
        }
      },
      reason: %{
        visible: truthy?(Map.get(freshness, :reason_label)),
        label: %{class: "hud-label", text: "reason"},
        value: %{
          class: "font-mono text-base-content/70",
          text: dom_text(Map.get(freshness, :reason_label))
        }
      },
      message: %{
        visible: truthy?(Map.get(freshness, :message)),
        class: "col-span-2 text-base-content/70",
        text: dom_text(Map.get(freshness, :message)),
        attrs: %{"data-publish-validation-freshness-message" => ""}
      }
    }
  end

  defp issue_dto(
         issue,
         index,
         selected_issue_id,
         dashboard_document,
         dashboard_current_path
       ) do
    selected? = issue.id == selected_issue_id

    %{
      key: "publish-validation-issue-#{index}",
      id: "dashboard-publish-validation-issue-#{dom_text(issue.id)}",
      class:
        class_names([
          "rounded border px-2 py-1 text-xs",
          if(selected?, do: "border-warning/70 bg-warning/10", else: "border-base-300/70")
        ]),
      attrs: %{
        "data-publish-validation-issue-id" => dom_attr_value(issue.id),
        "data-publish-validation-issue-selected" => if(selected?, do: "true", else: "false"),
        "data-publish-validation-severity" => dom_attr_value(issue.severity_text),
        "data-publish-validation-code" => dom_attr_value(issue.code)
      },
      header: %{
        class: "flex items-center gap-2",
        severity: %{
          class: class_names(["badge badge-xs", issue.badge_class]),
          text: dom_text(issue.severity_text)
        },
        code: %{class: "font-mono text-base-content/80", text: dom_text(issue.code)},
        focus: issue_focus_dto(issue, dashboard_current_path)
      },
      message: %{
        class: "mt-1 text-base-content/80",
        text: dom_text(issue.message),
        attrs: %{"data-publish-validation-message" => dom_attr_value(issue.code)}
      },
      summary: summary_dto(issue),
      action: action_dto(issue, dashboard_document),
      details: details_dto(issue)
    }
  end

  defp issue_focus_dto(issue, dashboard_current_path) do
    href =
      VersionActionNavigation.publish_validation_issue_href(dashboard_current_path, issue.id)

    %{
      href: href,
      navigation_kind: "patch",
      class: "ml-auto text-[11px] font-semibold text-primary hover:text-primary-focus",
      text: "Focus",
      attrs: %{
        "data-publish-validation-issue-focus-link" => dom_attr_value(issue.id),
        "data-phx-link" => "patch",
        "data-phx-link-state" => "push"
      }
    }
  end

  defp summary_dto(issue) do
    summary_rows = Map.get(issue, :summary_rows)

    if truthy?(summary_rows) do
      %{
        class:
          "mt-1 grid grid-cols-[5.5rem_1fr] gap-x-2 gap-y-1 rounded border border-base-300/60 bg-base-100/50 px-2 py-1 text-base-content/70",
        attrs: %{"data-publish-validation-summary" => dom_attr_value(issue.code)},
        rows:
          summary_rows
          |> Enum.with_index()
          |> Enum.map(fn {row, index} ->
            %{
              key: "publish-validation-summary-row-#{index}",
              label: %{class: "hud-label", text: dom_text(row.label)},
              value: %{
                class: "break-all font-mono",
                text: dom_text(row.value),
                attrs: %{"data-publish-validation-summary-row" => dom_attr_value(row.key)}
              }
            }
          end)
      }
    end
  end

  defp action_dto(%{action: action} = issue, dashboard_document)
       when action not in [nil, false] do
    href =
      VersionActionNavigation.publish_validation_action_href(
        action,
        dashboard_document,
        issue.id
      )

    %{
      class: "mt-2 border-l-2 border-info/70 pl-2",
      attrs: %{
        "data-publish-validation-action" => dom_attr_value(issue.code),
        "data-publish-validation-action-target" => dom_attr_value(action.target)
      },
      label: %{class: "hud-label", text: dom_text(action.label)},
      message: %{class: "mt-0.5 text-base-content/70", text: dom_text(action.message)},
      link: action_link_dto(href, action.target, issue.code)
    }
  end

  defp action_dto(_issue, _dashboard_document), do: nil

  defp action_link_dto(href, "data_sources", issue_code) when href not in [nil, false] do
    %{
      href: href,
      navigation_kind: "navigate",
      class:
        "mt-1 inline-flex items-center gap-1 text-xs font-semibold text-primary hover:text-primary-focus",
      text: "Open Data Sources",
      icon: %{name: "hero-arrow-top-right-on-square", class: "h-3 w-3"},
      attrs: %{
        "data-publish-validation-action-link" => dom_attr_value(issue_code),
        "data-publish-validation-action-href" => dom_attr_value(href),
        "data-phx-link" => "redirect",
        "data-phx-link-state" => "push"
      }
    }
  end

  defp action_link_dto(href, "dashboard_editor", issue_code) when href not in [nil, false] do
    %{
      href: href,
      navigation_kind: "patch",
      class:
        "mt-1 inline-flex items-center gap-1 text-xs font-semibold text-primary hover:text-primary-focus",
      text: "Open Widget Editor",
      icon: %{name: "hero-pencil-square", class: "h-3 w-3"},
      attrs: %{
        "data-publish-validation-action-link" => dom_attr_value(issue_code),
        "data-publish-validation-action-href" => dom_attr_value(href),
        "data-phx-link" => "patch",
        "data-phx-link-state" => "push"
      }
    }
  end

  defp action_link_dto(_href, _target, _issue_code), do: nil

  defp details_dto(%{detail_rows: []}), do: nil

  defp details_dto(issue) do
    %{
      class: "mt-1 grid grid-cols-[5.5rem_1fr] gap-x-2 gap-y-1 text-base-content/60",
      rows:
        issue.detail_rows
        |> Enum.with_index()
        |> Enum.map(fn {row, index} ->
          %{
            key: "publish-validation-detail-row-#{index}",
            label: %{class: "hud-label", text: dom_text(row.label)},
            value: %{
              class: "break-all font-mono",
              text: dom_text(row.value),
              attrs: %{"data-publish-validation-detail" => dom_attr_value(row.label)}
            }
          }
        end)
    }
  end

  defp truthy?(value), do: value not in [nil, false]

  defp class_names(values) do
    values
    |> Enum.reject(&(&1 in [nil, false]))
    |> Enum.map(&dom_text/1)
    |> Enum.join(" ")
  end

  defp dom_attr_value(value) when value in [nil, false], do: nil
  defp dom_attr_value(true), do: ""
  defp dom_attr_value(value), do: dom_text(value)

  defp dom_text(nil), do: ""
  defp dom_text(value) when is_binary(value), do: value
  defp dom_text(value) when is_atom(value), do: Atom.to_string(value)
  defp dom_text(value), do: to_string(value)
end
