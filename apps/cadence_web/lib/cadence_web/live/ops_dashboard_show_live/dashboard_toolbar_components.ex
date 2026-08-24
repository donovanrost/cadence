defmodule CadenceWeb.OpsDashboardShowLive.DashboardToolbarComponents do
  @moduledoc false
  use CadenceWeb, :html

  alias Cadence.Dashboards.{ComparisonReviewQueue, Document, TimeRange}
  alias CadenceWeb.OpsDashboardShowLive.DashboardRuntimeContextComponents
  alias CadenceWeb.OpsDashboardShowLive.DashboardRuntimeControlsComponents
  alias CadenceWeb.OpsDashboardShowLive.DashboardTimePickerComponents
  alias CadenceWeb.OpsDashboardShowLive.DashboardToolbarWarningPresentation
  alias Phoenix.LiveView.JS

  @data_source_issue_codes [
    :missing_source_binding,
    :partial_data,
    :retention_gap,
    :source_binding_segment_merge_unsupported,
    :source_connection_failed,
    :source_degraded,
    :source_execution_failed,
    :source_health_degraded,
    :source_unavailable,
    :stale_data,
    :unsupported_observable_scope,
    :unsupported_source_adapter,
    :unsupported_source_capability,
    :watermark_unknown
  ]

  attr(:dashboard_document, :any, required: true)
  attr(:dashboard_lifecycle_status, :any, required: true)
  attr(:dashboard_lifecycle_events, :list, default: [])
  attr(:dashboard_comparison_review_queue, :map, default: nil)
  attr(:dashboard_publish_readiness, :map, default: nil)
  attr(:edit_mode?, :boolean, required: true)
  attr(:editor_route?, :boolean, default: false)
  attr(:editor_dirty?, :boolean, default: false)
  attr(:editor_conflict, :map, default: nil)
  attr(:dashboard_author?, :boolean, default: false)
  attr(:show_context?, :boolean, required: true)
  attr(:current_mission, :any, default: nil)
  attr(:spacecraft, :list, required: true)
  attr(:source_endpoints, :list, default: [])
  attr(:transports, :list, default: [])
  attr(:ground_stations, :list, default: [])
  attr(:link_assignments, :list, default: [])
  attr(:scheduled_contacts, :list, default: [])
  attr(:realized_contacts, :list, default: [])
  attr(:context_spacecraft_id, :string, required: true)
  attr(:context_scope_kind, :string, default: nil)
  attr(:context_scope_id, :string, default: nil)
  attr(:context_scope_ids, :list, default: [])
  attr(:time_mode, :string, required: true)
  attr(:time_axis, :string, default: "generation_time")
  attr(:time_from, :string, default: nil)
  attr(:time_to, :string, default: nil)
  attr(:replay_run_id, :string, default: nil)
  attr(:time_validation, :string, default: "ok")
  attr(:data_realm, :string, required: true)
  attr(:data_realms, :list, required: true)
  attr(:data_view, :string, required: true)
  attr(:compare_data_view, :string, default: nil)
  attr(:data_source_id, :string, default: nil)
  attr(:source_binding_id, :string, default: nil)
  attr(:data_bindings, :list, required: true)
  attr(:replay_runs, :list, default: [])
  attr(:selected_replay_run, :any, default: nil)
  attr(:limit_mode, :string, required: true)
  attr(:limit_mode_fallback, :map, default: nil)
  attr(:hidden_marker_categories, :list, default: [])
  attr(:selected_data_ref, :any, default: nil)
  attr(:time_quick_query, :string, default: "")
  attr(:time_recent_ranges, :list, default: [])
  attr(:query, :string, required: true)
  attr(:dashboard_warnings, :list, default: [])
  attr(:dashboard_degraded?, :boolean, default: false)
  attr(:dashboard_health, :map, default: %{})
  attr(:comparison_available?, :boolean, default: false)
  attr(:comparison_open?, :boolean, default: false)
  attr(:comparison_open_count, :integer, default: 0)

  def dashboard_toolbar(assigns) do
    assigns = assign(assigns, :presentation, dashboard_toolbar_presentation(assigns))

    ~H"""
    <.vue
      id="dashboard-toolbar-component"
      v-component="DashboardToolbar"
      presentation={@presentation}
      v-on:recents-loaded={JS.push("time_recents_loaded")}
      v-on:select-range={JS.push("set_chart_time_range")}
      v-ssr={false}
      class="contents"
    />
    """
  end

  def dashboard_toolbar_presentation(assigns) do
    assigns =
      assigns
      |> assign(:data_issue_count, data_issue_count(assigns))
      |> assign(:data_issue_status, data_issue_status(assigns))
      |> assign(:mission_id, map_value(assigns.current_mission, :mission_id))
      |> assign(:dashboard_id, map_value(assigns.dashboard_document, :dashboard_id))
      |> assign(:historical_request_path, historical_request_path(assigns))
      |> assign(:dashboard_edit_path, dashboard_path(assigns, :edit))
      |> assign(:dashboard_activity_path, dashboard_path(assigns, :activity))
      |> assign(:dashboard_diagnostics_path, dashboard_path(assigns, :diagnostics))
      |> assign(:dashboard_settings_path, dashboard_path(assigns, :settings))
      |> assign(:dashboard_share_path, dashboard_share_path(assigns))
      |> assign(:data_query_label, data_query_label(assigns))
      |> assign(:data_query_overrides?, data_query_overrides?(assigns))
      |> then(&assign(&1, :data_issue_action, data_issue_action(&1)))

    %{
      root: %{
        attrs: %{
          id: "dashboard-telemetry-toolbar",
          class:
            "min-h-10 shrink-0 flex items-center gap-2 border-b border-base-300/50 bg-base-200/35 px-3 py-1",
          "data-dashboard-viewer-toolbar": to_string(not assigns.edit_mode?)
        }
      },
      title: %{
        wrapper_class: "min-w-0 flex-1",
        attrs: %{
          class: "break-words text-sm font-semibold leading-tight tracking-tight",
          title: map_value(assigns.dashboard_document, :description)
        },
        text: map_value(assigns.dashboard_document, :name)
      },
      viewer: dashboard_viewer_dto(assigns),
      comparison_toggle: dashboard_comparison_toggle_dto(assigns),
      data_health: dashboard_data_health_dto(assigns),
      editor_actions: dashboard_editor_actions_dto(assigns),
      menu: dashboard_menu_dto(assigns)
    }
  end

  defp dashboard_viewer_dto(%{edit_mode?: true}), do: nil

  defp dashboard_viewer_dto(assigns) do
    time_picker_assigns =
      assigns
      |> Map.put(:quick_query, assigns.time_quick_query)
      |> Map.put(:recent_ranges, assigns.time_recent_ranges)

    %{
      root: %{attrs: %{id: "runtime-context-controls", class: "cadence-dashboard-query-strip"}},
      operational_scope: operational_scope_dto(assigns),
      time_picker_host: component_host("dashboard-time-picker-component"),
      time_picker: DashboardTimePickerComponents.time_toolbar_presentation(time_picker_assigns)
    }
  end

  defp operational_scope_dto(assigns) do
    %{
      root: %{
        attrs: %{
          id: "dashboard-data-controls",
          "data-overlay-kind": "popover",
          "data-overlay-placement": "bottom-start",
          "data-dashboard-primary-control": "scope",
          "data-query-overrides": to_string(assigns.data_query_overrides?),
          class: "cadence-overlay"
        }
      },
      trigger: %{
        attrs: %{
          id: "dashboard-data-controls-toggle",
          type: "button",
          "data-overlay-trigger": "",
          "aria-haspopup": "dialog",
          "aria-expanded": "false",
          "aria-controls": "dashboard-data-controls-panel",
          "aria-label": "Dashboard operational scope",
          class: "cadence-overlay-trigger cadence-dashboard-query-trigger"
        },
        label: %{class: "cadence-dashboard-query-trigger-label", text: "Scope"},
        value: %{
          class: "cadence-dashboard-query-trigger-value hidden max-w-36 sm:inline",
          text:
            runtime_scope_label(
              assigns.current_mission,
              assigns.spacecraft,
              assigns.context_scope_kind,
              assigns.context_scope_id,
              assigns.context_scope_ids
            )
        },
        override:
          if(assigns.data_query_overrides?,
            do: %{
              attrs: %{
                class: "cadence-dashboard-context-override hidden max-w-40 md:inline-flex",
                "data-dashboard-data-override": ""
              },
              text: assigns.data_query_label
            }
          ),
        icon_class: "hero-chevron-down h-3 w-3 shrink-0 text-base-content/40"
      },
      panel: %{
        attrs: %{
          id: "dashboard-data-controls-panel",
          "data-overlay-panel": "",
          "data-overlay-width": "lg",
          "aria-label": "Dashboard operational scope",
          class: "cadence-overlay-panel cadence-popover-panel",
          hidden: true
        },
        header: %{
          class: "cadence-dashboard-query-panel-header",
          icon_class: "hero-viewfinder-circle mt-0.5 h-4 w-4 text-primary",
          title: %{class: "text-xs font-semibold text-base-content/85", text: "Operational scope"},
          description: %{
            class: "mt-0.5 text-[0.68rem] text-base-content/50",
            text: "Focus every widget without leaving the dashboard."
          }
        },
        body: %{
          class: "cadence-dashboard-query-panel-body",
          context_host: component_host("dashboard-runtime-context-selector-component"),
          context:
            if(assigns.show_context?,
              do: DashboardRuntimeContextComponents.context_selector_presentation(assigns)
            ),
          query_options: dashboard_query_options_dto(assigns)
        }
      }
    }
  end

  defp dashboard_query_options_dto(assigns) do
    %{
      attrs: %{
        id: "dashboard-query-options",
        open: assigns.data_query_overrides?,
        class: "cadence-dashboard-context-advanced",
        "data-query-overrides": to_string(assigns.data_query_overrides?)
      },
      summary: %{
        attrs: %{
          id: "dashboard-query-options-toggle",
          class: "cadence-dashboard-context-advanced-summary",
          "aria-label": "Dashboard data options"
        },
        leading_class: "flex min-w-0 items-center gap-2",
        icon_class: "hero-circle-stack h-4 w-4 shrink-0 text-primary",
        copy_class: "min-w-0",
        title: %{
          class: "block text-xs font-semibold text-base-content/85",
          text: "Data provenance & semantics"
        },
        description: %{
          class: "block truncate text-[0.68rem] text-base-content/50",
          text:
            if(assigns.data_query_overrides?,
              do: assigns.data_query_label,
              else: "Flight · Canonical · Observed limits"
            )
        },
        chevron_class:
          "hero-chevron-right h-3.5 w-3.5 shrink-0 text-base-content/45 transition-transform"
      },
      panel: %{
        attrs: %{id: "dashboard-query-options-panel", class: "pt-3"},
        runtime_controls_host: component_host("dashboard-runtime-controls-component"),
        runtime_controls:
          assigns
          |> Map.put(:section, :data)
          |> DashboardRuntimeControlsComponents.runtime_controls_presentation()
      }
    }
  end

  defp dashboard_data_health_dto(%{data_issue_count: 0}), do: nil

  defp dashboard_data_health_dto(assigns) do
    warnings =
      assigns.dashboard_warnings
      |> Enum.with_index()
      |> Enum.map(fn {warning, index} ->
        DashboardToolbarWarningPresentation.build(
          "dashboard-data-issue-warning-#{index}",
          warning
        )
      end)

    %{
      root: %{
        attrs: %{
          id: "dashboard-data-issues",
          "data-overlay-kind": "popover",
          "data-overlay-placement": "bottom-end",
          "data-dashboard-data-issue-count": Integer.to_string(assigns.data_issue_count),
          "data-dashboard-data-issue-status": to_string(assigns.data_issue_status),
          "data-dashboard-data-issue-codes": data_issue_codes(assigns.dashboard_warnings),
          class: "cadence-overlay"
        }
      },
      trigger: %{
        attrs: %{
          id: "dashboard-data-issues-trigger",
          type: "button",
          "data-overlay-trigger": "",
          "aria-haspopup": "dialog",
          "aria-expanded": "false",
          "aria-controls": "dashboard-data-issues-panel",
          "aria-label": "Dashboard data health",
          class: "cadence-overlay-trigger"
        },
        badge: %{
          attrs: %{
            class:
              "inline-flex h-7 cursor-pointer items-center gap-1.5 rounded border px-2 text-[0.68rem] font-semibold #{data_issue_class(assigns.data_issue_status)}",
            title: "Open data health summary",
            "data-dashboard-data-issues-toggle": ""
          },
          icon_class: "hero-exclamation-triangle h-3.5 w-3.5",
          count: Integer.to_string(assigns.data_issue_count),
          label: "data #{if assigns.data_issue_count == 1, do: "issue", else: "issues"}"
        }
      },
      panel: %{
        attrs: %{
          id: "dashboard-data-issues-panel",
          "data-overlay-panel": "",
          "data-overlay-width": "md",
          "aria-label": "Dashboard data health",
          class: "cadence-overlay-panel cadence-popover-panel",
          hidden: true
        },
        body: %{
          class: "p-3 text-xs",
          header: %{
            class: "flex items-start gap-2 border-b border-base-300/60 pb-2",
            icon_class: "hero-signal mt-0.5 h-4 w-4 text-warning",
            copy_class: "min-w-0",
            title: %{class: "font-semibold text-base-content", text: "Data health"},
            summary: %{
              class: "mt-0.5 text-base-content/60",
              text: data_issue_summary(assigns.dashboard_health)
            }
          },
          warnings_class: "mt-2 flex flex-wrap gap-1",
          warnings: warnings,
          degraded_message:
            if(assigns.dashboard_degraded? and warnings == [],
              do: %{
                class: "mt-2 text-base-content/65",
                text: "One or more sources returned degraded data."
              }
            ),
          action: data_issue_link_dto(assigns.data_issue_action),
          diagnostics_action:
            if(assigns.data_issue_action.kind == "data_sources",
              do: %{
                attrs:
                  live_link_attrs(
                    "dashboard-data-issues-diagnostics",
                    assigns.dashboard_diagnostics_path,
                    %{class: "btn btn-ghost btn-xs mt-1 w-full justify-start"}
                  ),
                icon_class: "hero-wrench-screwdriver h-3.5 w-3.5",
                text: "Dashboard diagnostics"
              }
            )
        }
      }
    }
  end

  defp data_issue_link_dto(action) do
    %{
      attrs:
        live_link_attrs("dashboard-data-issues-open", action.path, %{
          class: "btn btn-outline btn-xs mt-3 w-full justify-start",
          "data-dashboard-data-issue-action": action.kind
        }),
      icon_class: "#{action.icon} h-3.5 w-3.5",
      text: action.label
    }
  end

  defp dashboard_menu_dto(assigns) do
    open_summary = comparison_review_open_summary(assigns.dashboard_comparison_review_queue)

    items =
      [
        if(
          not assigns.edit_mode? and not is_nil(assigns.mission_id) and
            not is_nil(assigns.dashboard_id),
          do:
            menu_item(
              "dashboard-investigate-telemetry",
              telemetry_explore_path(assigns),
              "hero-chart-bar-square",
              "Explore telemetry"
            )
        ),
        if(
          not assigns.edit_mode? and not is_nil(assigns.mission_id) and
            not is_nil(assigns.dashboard_id),
          do:
            menu_item(
              "dashboard-investigate-sources",
              ~p"/missions/#{assigns.mission_id}/ops/data-sources?source_dashboard_id=#{assigns.dashboard_id}",
              "hero-circle-stack",
              "Data Sources"
            )
        ),
        if(not assigns.edit_mode? and not is_nil(assigns.mission_id),
          do:
            menu_item(
              "dashboard-investigate-contacts",
              ~p"/missions/#{assigns.mission_id}/ops/contacts",
              "hero-signal",
              "Contacts"
            )
        ),
        if(not assigns.edit_mode? and assigns.dashboard_author?,
          do:
            menu_item(
              "dashboard-edit-link",
              assigns.dashboard_edit_path,
              "hero-pencil-square",
              "Edit Dashboard"
            )
        ),
        menu_item(
          "dashboard-versions-button",
          assigns.dashboard_activity_path,
          "hero-clock",
          "Versions & activity",
          %{
            "data-dashboard-comparison-review-open-count": open_summary.count_text,
            "data-dashboard-comparison-review-open-requests": open_summary.request_ids_attr,
            "data-dashboard-comparison-review-open-placements": open_summary.placements_attr
          },
          if(open_summary.count_text != "0",
            do: %{
              class: "badge badge-warning badge-xs",
              attrs: %{"data-dashboard-comparison-review-open-toolbar-badge": ""},
              text: open_summary.count_text
            }
          )
        ),
        menu_item(
          "dashboard-historical-workflow-request-button",
          assigns.historical_request_path,
          "hero-document-plus",
          "Request historical data"
        ),
        menu_item(
          "dashboard-diagnostics-button",
          assigns.dashboard_diagnostics_path,
          "hero-chart-bar-square",
          "Diagnostics"
        ),
        if(assigns.dashboard_author?,
          do:
            menu_item(
              "dashboard-share-button",
              assigns.dashboard_share_path,
              "hero-share",
              "Share current context"
            )
        ),
        if(assigns.dashboard_author?,
          do:
            menu_item(
              "dashboard-settings-button",
              assigns.dashboard_settings_path,
              "hero-cog-6-tooth",
              "Settings"
            )
        )
      ]
      |> Enum.reject(&is_nil/1)

    %{
      root: %{
        attrs: %{
          id: "dashboard-menu",
          "data-overlay-kind": "menu",
          "data-overlay-placement": "bottom-end",
          class: "cadence-overlay"
        }
      },
      trigger: %{
        attrs: %{
          id: "dashboard-menu-trigger",
          type: "button",
          "data-overlay-trigger": "",
          "aria-haspopup": "menu",
          "aria-expanded": "false",
          "aria-controls": "dashboard-menu-menu",
          "aria-label": "Actions",
          class: "cadence-overlay-trigger btn btn-ghost btn-xs"
        },
        icon_class: "hero-ellipsis-vertical h-5 w-5"
      },
      panel: %{
        attrs: %{
          id: "dashboard-menu-menu",
          role: "menu",
          "data-overlay-panel": "",
          class: "cadence-overlay-panel cadence-menu-panel",
          hidden: true
        },
        items: items
      }
    }
  end

  defp menu_item(id, path, icon, text, extra_attrs \\ %{}, badge \\ nil) do
    %{
      key: id,
      wrapper: %{attrs: %{role: "none", class: "cadence-menu-item"}},
      link: %{
        attrs: live_link_attrs(id, path, extra_attrs),
        icon_class: "#{icon} h-4 w-4",
        text: text,
        badge: badge
      }
    }
  end

  defp live_link_attrs(id, path, extra_attrs) do
    Map.merge(
      %{
        id: id,
        href: path,
        "data-phx-link": "redirect",
        "data-phx-link-state": "push"
      },
      extra_attrs
    )
  end

  defp component_host(id), do: %{attrs: %{id: id, class: "contents"}}

  defp runtime_scope_label(_mission, _spacecraft, scope_kind, _scope_id, scope_ids)
       when is_list(scope_ids) and length(scope_ids) > 1 do
    "#{length(scope_ids)} #{scope_kind_label(scope_kind)}"
  end

  defp runtime_scope_label(current_mission, _spacecraft, "mission", _scope_id, _scope_ids) do
    map_value(current_mission, :display_name) || "Mission"
  end

  defp runtime_scope_label(_mission, spacecraft, "spacecraft", scope_id, _scope_ids) do
    spacecraft
    |> Enum.find(&(map_value(&1, :spacecraft_id) == scope_id))
    |> map_value(:display_name)
    |> then(&(&1 || scope_id || "Spacecraft"))
  end

  defp runtime_scope_label(current_mission, _spacecraft, scope_kind, scope_id, _scope_ids) do
    if present_text?(scope_id) do
      "#{scope_kind_label(scope_kind)} · #{scope_id}"
    else
      map_value(current_mission, :display_name) || "Mission"
    end
  end

  defp scope_kind_label(value) when is_binary(value) do
    value
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp scope_kind_label(_value), do: "contexts"

  defp data_query_label(assigns) do
    base = "#{query_value_label(assigns.data_realm)} · #{query_value_label(assigns.data_view)}"

    case assigns.compare_data_view do
      value when is_binary(value) and value != "" ->
        "#{base} ↔ #{query_value_label(value)}"

      _none ->
        base
    end
  end

  defp data_query_overrides?(assigns) do
    assigns.data_realm != "flight" or
      assigns.data_view != "canonical" or
      present_text?(assigns.compare_data_view) or
      assigns.limit_mode != "observed" or
      assigns.time_axis != "generation_time"
  end

  defp comparison_toolbar_visible?(assigns) do
    assigns.comparison_available? and
      (assigns.comparison_open? or assigns.comparison_open_count > 0 or
         present_text?(assigns.compare_data_view))
  end

  defp dashboard_comparison_toggle_dto(assigns) do
    if not assigns.edit_mode? and comparison_toolbar_visible?(assigns) do
      %{
        root: %{
          tag: "button",
          class:
            Enum.join(
              [
                "btn btn-ghost btn-xs h-7 gap-1.5 border px-2 font-normal",
                if(assigns.comparison_open?,
                  do: "border-info/45 bg-info/10 text-info",
                  else: "border-base-300/70 bg-base-100/50"
                )
              ],
              " "
            ),
          attrs: %{
            "id" => "dashboard-comparison-toggle",
            "type" => "button",
            "phx-click" => "toggle_comparison_inspector",
            "aria-expanded" => to_string(assigns.comparison_open?),
            "aria-controls" => "dashboard-comparison-inspector",
            "data-dashboard-comparison-toggle" => ""
          }
        },
        children:
          [
            %{
              key: "icon",
              tag: "span",
              class: "hero-scale h-3.5 w-3.5",
              attrs: %{},
              text: ""
            },
            %{
              key: "label",
              tag: "span",
              class: "hidden sm:inline",
              attrs: %{},
              text: "Compare"
            }
          ] ++ dashboard_comparison_toggle_badge_dto(assigns.comparison_open_count)
      }
    end
  end

  defp dashboard_comparison_toggle_badge_dto(count) when count > 0 do
    count_text = Integer.to_string(count)

    [
      %{
        key: "open-count",
        tag: "span",
        class: "badge badge-warning badge-xs",
        attrs: %{"data-dashboard-comparison-open-count" => count_text},
        text: count_text
      }
    ]
  end

  defp dashboard_comparison_toggle_badge_dto(_count), do: []

  defp dashboard_editor_actions_dto(assigns) do
    if assigns.edit_mode? or assigns.editor_route? do
      %{
        elements:
          [
            dashboard_publish_readiness_dto(assigns),
            if(assigns.edit_mode?, do: edit_paused_note_dto()),
            if(assigns.edit_mode? and not assigns.editor_route?, do: edit_layout_toggle_dto()),
            if(assigns.editor_route?, do: editor_save_state_dto(assigns.editor_dirty?)),
            if(assigns.editor_route?, do: editor_discard_dto()),
            if(assigns.editor_route?, do: editor_save_dto(assigns)),
            if(assigns.editor_route?, do: editor_review_dto(assigns.editor_conflict)),
            if(assigns.edit_mode?, do: add_widget_dto()),
            if(assigns.edit_mode?, do: manage_dashboard_sections_dto())
          ]
          |> Enum.reject(&is_nil/1)
      }
    end
  end

  defp dashboard_publish_readiness_dto(%{
         edit_mode?: true,
         dashboard_publish_readiness: readiness
       })
       when is_map(readiness) do
    status = readiness.status
    issue_count = publish_readiness_issue_count(readiness)

    editor_element(
      "dashboard-publish-readiness-summary",
      "button",
      %{
        "id" => "dashboard-publish-readiness-summary",
        "type" => "button",
        "phx-click" => "open_versions",
        "class" =>
          editor_class_list([
            "inline-flex h-6 items-center gap-1 rounded border px-2 text-[11px] font-medium",
            publish_readiness_class(status)
          ]),
        "data-dashboard-publish-readiness-status" => status,
        "data-dashboard-publish-readiness-issue-count" => issue_count
      },
      "",
      [
        editor_child(
          "icon",
          "span",
          %{"class" => editor_class_list([publish_readiness_icon(status), "h-3 w-3"])},
          ""
        ),
        editor_child("label", "span", %{}, publish_readiness_label(status)),
        if(issue_count != "0",
          do:
            editor_child(
              "issue-count",
              "span",
              %{"class" => "font-mono opacity-80"},
              issue_count
            )
        )
      ]
      |> Enum.reject(&is_nil/1)
    )
  end

  defp dashboard_publish_readiness_dto(_assigns), do: nil

  defp edit_paused_note_dto do
    editor_element(
      "edit-paused-note",
      "span",
      %{"id" => "edit-paused-note", "class" => "text-xs text-warning"},
      "Live updates paused while editing"
    )
  end

  defp edit_layout_toggle_dto do
    editor_button(
      "edit-layout-toggle",
      "toggle_edit",
      "btn-primary",
      "Done",
      "hero-arrows-pointing-out"
    )
  end

  defp editor_save_state_dto(editor_dirty?) do
    editor_element(
      "dashboard-editor-save-state",
      "span",
      %{
        "id" => "dashboard-editor-save-state",
        "class" =>
          editor_class_list([
            "font-mono text-[0.65rem] uppercase tracking-wider",
            if(editor_dirty?, do: "text-warning", else: "text-success")
          ]),
        "data-editor-dirty" => to_string(editor_dirty?)
      },
      if(editor_dirty?, do: "Unsaved changes", else: "Saved")
    )
  end

  defp editor_discard_dto do
    editor_button(
      "dashboard-editor-discard",
      "discard_editor",
      "btn-ghost",
      "Discard",
      nil,
      %{"data-editor-discard" => true}
    )
  end

  defp editor_save_dto(assigns) do
    editor_button(
      "dashboard-editor-save",
      "save_editor",
      "btn-primary",
      "Save",
      "hero-check",
      %{"disabled" => not assigns.editor_dirty? or not is_nil(assigns.editor_conflict)}
    )
  end

  defp editor_review_dto(editor_conflict) do
    editor_button(
      "dashboard-editor-review",
      "review_editor",
      "btn-ghost",
      "Review & Publish",
      nil,
      %{"disabled" => not is_nil(editor_conflict)}
    )
  end

  defp add_widget_dto do
    editor_button(
      "add-widget-button",
      "open_add_widget",
      "btn-ghost",
      "Widget",
      "hero-plus"
    )
  end

  defp manage_dashboard_sections_dto do
    editor_button(
      "manage-dashboard-sections",
      "open_dashboard_sections",
      "btn-ghost",
      "Sections",
      "hero-rectangle-group"
    )
  end

  defp editor_button(id, event, variant_class, text, icon, extra_attrs \\ %{}) do
    editor_element(
      id,
      "button",
      Map.merge(
        %{
          "id" => id,
          "type" => "button",
          "class" => editor_class_list(["btn", variant_class, "btn-xs"]),
          "phx-click" => event
        },
        extra_attrs
      ),
      text,
      if(icon,
        do: [
          editor_child(
            "icon",
            "span",
            %{"class" => editor_class_list([icon, "h-3.5 w-3.5"])},
            ""
          )
        ],
        else: []
      )
    )
  end

  defp editor_element(key, tag, attrs, text, children \\ []) do
    %{
      key: key,
      tag: tag,
      attrs: editor_raw_attributes(attrs),
      text: text,
      children: children
    }
  end

  defp editor_child(key, tag, attrs, text) do
    %{key: key, tag: tag, attrs: editor_raw_attributes(attrs), text: text}
  end

  defp editor_raw_attributes(attributes) do
    Enum.reduce(attributes, %{}, fn
      {_key, value}, rendered when value in [nil, false] ->
        rendered

      {key, true}, rendered ->
        Map.put(rendered, to_string(key), "")

      {key, value}, rendered ->
        Map.put(rendered, to_string(key), to_string(value))
    end)
  end

  defp editor_class_list(classes) do
    classes
    |> Enum.reject(&(&1 in [nil, false]))
    |> Enum.map(&to_string/1)
    |> Enum.join(" ")
  end

  defp query_value_label(value) when is_binary(value) do
    value
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp query_value_label(_value), do: "Default"

  defp telemetry_explore_path(assigns) do
    {from_value, to_value} =
      TimeRange.frozen_bounds(assigns.time_from, assigns.time_to, DateTime.utc_now())

    query =
      %{
        "source_dashboard_id" => assigns.dashboard_id,
        "spacecraft_id" => assigns.context_spacecraft_id,
        "scope_kind" => assigns.context_scope_kind,
        "scope_id" => assigns.context_scope_id,
        "time_mode" => explore_time_mode(assigns.time_mode),
        "from" => from_value,
        "to" => to_value,
        "time_axis" => assigns.time_axis,
        "replay_run_id" => assigns.replay_run_id,
        "realm" => assigns.data_realm,
        "selection_view" => assigns.data_view,
        "data_source_id" => assigns.data_source_id,
        "source_binding_id" => assigns.source_binding_id,
        "limit_mode" => assigns.limit_mode
      }
      |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
      |> Map.new()

    ~p"/missions/#{assigns.mission_id}/ops/explore?#{query}"
  end

  defp explore_time_mode("live"), do: "latest"
  defp explore_time_mode(mode), do: mode

  defp data_issue_count(assigns) do
    warning_count = length(assigns.dashboard_warnings)
    affected_count = map_value(assigns.dashboard_health, :affected_count) || 0
    degraded_count = if assigns.dashboard_degraded?, do: 1, else: 0

    Enum.max([warning_count, affected_count, degraded_count])
  end

  defp data_issue_action(assigns) do
    if data_source_issue?(assigns.dashboard_warnings) and
         dashboard_identity?(assigns.mission_id, assigns.dashboard_id) do
      %{
        kind: "data_sources",
        label: "Open Data Sources",
        icon: "hero-circle-stack",
        path:
          ~p"/missions/#{assigns.mission_id}/ops/data-sources?source_dashboard_id=#{assigns.dashboard_id}"
      }
    else
      %{
        kind: "diagnostics",
        label: "Open diagnostics",
        icon: "hero-wrench-screwdriver",
        path: assigns.dashboard_diagnostics_path
      }
    end
  end

  defp data_source_issue?(warnings) when is_list(warnings) do
    Enum.any?(warnings, fn warning ->
      warning
      |> map_value(:code)
      |> normalize_issue_code()
      |> then(&(&1 in @data_source_issue_codes))
    end)
  end

  defp normalize_issue_code(code) when is_atom(code), do: code

  defp normalize_issue_code(code) when is_binary(code) do
    Enum.find(@data_source_issue_codes, &(Atom.to_string(&1) == code))
  end

  defp normalize_issue_code(_code), do: nil

  defp historical_request_query(assigns) do
    point_id =
      map_value(assigns.selected_data_ref, :point_id) ||
        map_value(assigns.selected_data_ref, :observable_id)

    {source_from, source_to} =
      TimeRange.frozen_bounds(assigns.time_from, assigns.time_to, DateTime.utc_now())

    %{
      "realm" => assigns.data_realm,
      "data_source_id" => assigns.data_source_id,
      "source_binding_id" => assigns.source_binding_id,
      "observable_id" => point_id,
      "point_id" => point_id,
      "point_ids" => point_id,
      "source_from" => source_from,
      "source_to" => source_to,
      "dashboard_id" => map_value(assigns.dashboard_document, :dashboard_id),
      "dashboard_version" => dashboard_version(assigns.dashboard_document),
      "dashboard_time_mode" => assigns.time_mode,
      "dashboard_replay_run_id" => assigns.replay_run_id,
      "dashboard_data_view" => assigns.data_view,
      "dashboard_limit_mode" => assigns.limit_mode,
      "reason" => "dashboard_historical_data_gap"
    }
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Map.new()
  end

  defp historical_request_path(assigns) do
    case map_value(assigns.current_mission, :mission_id) do
      mission_id when is_binary(mission_id) and mission_id != "" ->
        ~p"/missions/#{mission_id}/ops/data-operations?#{historical_request_query(assigns)}"

      _missing_mission ->
        "#"
    end
  end

  defp dashboard_path(assigns, page) do
    mission_id = map_value(assigns.current_mission, :mission_id)
    dashboard_id = map_value(assigns.dashboard_document, :dashboard_id)

    if dashboard_identity?(mission_id, dashboard_id),
      do: dashboard_page_path(page, mission_id, dashboard_id, assigns),
      else: "#"
  end

  defp dashboard_page_path(:edit, mission_id, dashboard_id, _assigns),
    do: ~p"/missions/#{mission_id}/ops/dashboards/#{dashboard_id}/edit"

  defp dashboard_page_path(:activity, mission_id, dashboard_id, _assigns),
    do: ~p"/missions/#{mission_id}/ops/dashboards/#{dashboard_id}/activity"

  defp dashboard_page_path(:diagnostics, mission_id, dashboard_id, assigns),
    do:
      ~p"/missions/#{mission_id}/ops/dashboards/#{dashboard_id}/diagnostics?#{runtime_context_query(assigns)}"

  defp dashboard_page_path(:settings, mission_id, dashboard_id, assigns),
    do:
      ~p"/missions/#{mission_id}/ops/dashboards/#{dashboard_id}/settings?#{runtime_context_query(assigns)}"

  defp dashboard_page_path(_page, _mission_id, _dashboard_id, _assigns), do: "#"

  defp dashboard_identity?(mission_id, dashboard_id),
    do: present_text?(mission_id) and present_text?(dashboard_id)

  defp runtime_context_query(assigns) do
    selected_id =
      map_value(assigns.selected_data_ref, :sample_id) ||
        map_value(assigns.selected_data_ref, :point_id) ||
        map_value(assigns.selected_data_ref, :observable_id)

    %{
      "spacecraft_id" => assigns.context_spacecraft_id,
      "scope_kind" => assigns.context_scope_kind,
      "scope_id" => assigns.context_scope_id,
      "time_mode" => assigns.time_mode,
      "time_axis" => assigns.time_axis,
      "from" => assigns.time_from,
      "to" => assigns.time_to,
      "replay_run_id" => assigns.replay_run_id,
      "realm" => assigns.data_realm,
      "data_view" => assigns.data_view,
      "data_source_id" => assigns.data_source_id,
      "source_binding_id" => assigns.source_binding_id,
      "limit_mode" => assigns.limit_mode,
      "selected_id" => selected_id
    }
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Map.new()
  end

  defp dashboard_share_path(assigns) do
    case dashboard_path(assigns, :settings) do
      "#" -> "#"
      path -> path <> "#dashboard-sharing"
    end
  end

  defp dashboard_version(%Document{} = document), do: Document.version(document)
  defp dashboard_version(_document), do: nil

  defp data_issue_status(assigns) do
    health_state = map_value(assigns.dashboard_health, :state)

    cond do
      health_state == :blocked -> :critical
      Enum.any?(assigns.dashboard_warnings, &(map_value(&1, :severity) == :error)) -> :critical
      data_issue_count(assigns) > 0 -> :warning
      true -> :nominal
    end
  end

  defp data_issue_codes(warnings) do
    warnings
    |> Enum.map(&(map_value(&1, :code_text) || map_value(&1, :code)))
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&to_string/1)
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.join(",")
  end

  defp data_issue_summary(health) do
    case {map_value(health, :label), map_value(health, :affected_count)} do
      {label, count} when is_binary(label) and is_integer(count) ->
        "#{label}; #{count} affected #{if count == 1, do: "widget", else: "widgets"}."

      {_label, count} when is_integer(count) and count > 0 ->
        "#{count} affected #{if count == 1, do: "widget", else: "widgets"}."

      _other ->
        "Inspect the affected sources and widget evidence."
    end
  end

  defp data_issue_class(:critical), do: "border-error/40 bg-error/10 text-error"
  defp data_issue_class(:warning), do: "border-warning/40 bg-warning/10 text-warning"
  defp data_issue_class(_status), do: "border-base-300 bg-base-100 text-base-content/70"

  defp map_value(nil, _key), do: nil

  defp map_value(map, key) when is_map(map) do
    Map.get(map, key, Map.get(map, Atom.to_string(key)))
  end

  defp map_value(_value, _key), do: nil

  defp present_text?(value), do: is_binary(value) and String.trim(value) != ""

  defp publish_readiness_label("blocked"), do: "Publish blocked"
  defp publish_readiness_label("stale"), do: "Re-check publish"
  defp publish_readiness_label("warnings"), do: "Publish warnings"
  defp publish_readiness_label("clean"), do: "Publish ready"
  defp publish_readiness_label(_status), do: "Publish status"

  defp publish_readiness_icon("blocked"), do: "hero-exclamation-triangle"
  defp publish_readiness_icon("stale"), do: "hero-arrow-path"
  defp publish_readiness_icon("warnings"), do: "hero-exclamation-circle"
  defp publish_readiness_icon("clean"), do: "hero-check-circle"
  defp publish_readiness_icon(_status), do: "hero-information-circle"

  defp publish_readiness_class("blocked"), do: "border-error/40 bg-error/10 text-error"
  defp publish_readiness_class("stale"), do: "border-warning/40 bg-warning/10 text-warning"
  defp publish_readiness_class("warnings"), do: "border-warning/40 bg-warning/10 text-warning"
  defp publish_readiness_class("clean"), do: "border-success/40 bg-success/10 text-success"
  defp publish_readiness_class(_status), do: "border-base-300 bg-base-100 text-base-content/70"

  defp publish_readiness_issue_count(%{issues: issues}) when is_list(issues) do
    issues |> length() |> Integer.to_string()
  end

  defp publish_readiness_issue_count(_validation), do: "0"

  defp comparison_review_open_request_count(open_summary) do
    open_summary
    |> comparison_review_open_summary()
    |> Map.fetch!(:count_text)
  end

  defp comparison_review_open_request_ids_attr(open_summary) do
    open_summary
    |> comparison_review_open_summary()
    |> Map.fetch!(:request_ids_attr)
  end

  defp comparison_review_open_placements_attr(open_summary) do
    open_summary
    |> comparison_review_open_summary()
    |> Map.fetch!(:placements_attr)
  end

  defp comparison_review_open_summary(%{count: count, requests: requests} = open_summary)
       when is_integer(count) and is_list(requests) do
    open_summary
  end

  defp comparison_review_open_summary(_open_summary), do: ComparisonReviewQueue.open_summary([])
end
