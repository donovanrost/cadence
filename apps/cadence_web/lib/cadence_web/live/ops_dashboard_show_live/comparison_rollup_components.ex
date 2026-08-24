defmodule CadenceWeb.OpsDashboardShowLive.ComparisonRollupComponents do
  @moduledoc false
  use CadenceWeb, :html

  alias CadenceWeb.OpsDashboardShowLive.ComparisonInvestigationPreset
  alias CadenceWeb.OpsDashboardShowLive.DataLinkAttrs

  attr(:rollup, :map, required: true)
  attr(:preset, :map, default: nil)
  attr(:open_review_summary, :map, default: %{})
  attr(:saved_presets, :list, default: [])

  attr(:inspector, :map, default: nil)

  def comparison_rollup_strip(assigns) do
    if comparison_rollup_available?(assigns.rollup, assigns.saved_presets) do
      host_id =
        if assigns.inspector,
          do: "dashboard-comparison-inspector-component",
          else: "dashboard-comparison-rollup-component"

      assigns =
        assigns
        |> assign(:host_id, host_id)
        |> assign(:presentation, comparison_rollup_presentation(assigns))

      ~H"""
      <.vue
        id={@host_id}
        v-component="DashboardComparisonInspector"
        presentation={@presentation}
        v-ssr={false}
        class="contents"
      />
      """
    else
      ~H""
    end
  end

  defp comparison_rollup_available?(rollup, saved_presets) do
    Map.get(rollup, :visible?) == true or saved_presets != []
  end

  defp comparison_rollup_presentation(assigns) do
    groups = comparison_rollup_groups(assigns.rollup)
    workflow_groups = comparison_rollup_workflow_groups(assigns.rollup)
    preset_json = comparison_rollup_preset_json(assigns.preset)
    preset_path = comparison_rollup_preset_path(assigns.preset)
    open_findings_json = comparison_rollup_open_findings_json(assigns.preset)

    review_requested? =
      comparison_rollup_review_requested?(assigns.preset, assigns.open_review_summary)

    %{
      inspector: assigns.inspector,
      rollup: %{
        root: %{
          attrs:
            element_attrs(%{
              "id" => "dashboard-comparison-rollup",
              "data-dashboard-comparison-rollup" => "",
              "data-dashboard-comparison-widgets" =>
                comparison_rollup_count(assigns.rollup, :widget_count),
              "data-dashboard-comparison-deltas" =>
                comparison_rollup_count(assigns.rollup, :delta_count),
              "data-dashboard-comparison-unchanged" =>
                comparison_rollup_count(assigns.rollup, :unchanged_count),
              "data-dashboard-comparison-coverage" =>
                comparison_rollup_count(assigns.rollup, :coverage_count),
              "data-dashboard-comparison-missing" =>
                comparison_rollup_count(assigns.rollup, :missing_count),
              "data-dashboard-comparison-handled" =>
                comparison_rollup_count(assigns.rollup, :handled_count),
              "data-dashboard-comparison-open" =>
                comparison_rollup_count(assigns.rollup, :open_count),
              "data-dashboard-comparison-unhandled" =>
                comparison_rollup_count(assigns.rollup, :unhandled_count),
              "data-dashboard-comparison-states" => Map.get(assigns.rollup, :states, ""),
              "data-dashboard-comparison-delta-placements" =>
                comparison_rollup_group_placements(groups, "deltas"),
              "data-dashboard-comparison-missing-placements" =>
                comparison_rollup_group_placements(groups, "missing"),
              "data-dashboard-comparison-coverage-placements" =>
                comparison_rollup_group_placements(groups, "coverage"),
              "data-dashboard-comparison-unchanged-placements" =>
                comparison_rollup_group_placements(groups, "unchanged"),
              "data-dashboard-comparison-open-placements" =>
                comparison_rollup_group_placements(workflow_groups, "open"),
              "data-dashboard-comparison-handled-placements" =>
                comparison_rollup_group_placements(workflow_groups, "handled"),
              "data-dashboard-comparison-preset" => preset_json,
              "data-dashboard-comparison-preset-path" => preset_path,
              "data-dashboard-comparison-open-findings" => open_findings_json,
              "data-dashboard-comparison-open-findings-review-state" =>
                comparison_rollup_review_state(review_requested?),
              "data-dashboard-comparison-open-findings-review-request-ids" =>
                comparison_rollup_open_review_request_ids(assigns.open_review_summary),
              "data-dashboard-comparison-saved-presets" => length(assigns.saved_presets),
              "class" =>
                "shrink-0 flex flex-wrap items-center gap-2 px-2 py-1 border-b border-info/30 bg-info/10 text-xs"
            })
        },
        label: text_presentation("Compare", "hud-label"),
        summary:
          text_presentation(
            "#{comparison_rollup_count(assigns.rollup, :widget_count)} widgets",
            "text-base-content/70"
          ),
        badges: comparison_rollup_badges(assigns.rollup, groups, workflow_groups),
        open_findings_copy:
          clipboard_presentation(
            open_findings_json,
            "dashboard-comparison-open-findings-copy-component",
            "dashboard-comparison-open-findings-copy",
            "btn btn-ghost btn-xs gap-1",
            "hero-clipboard-document-list",
            "Open",
            "Copy open comparison findings",
            %{"data-dashboard-comparison-open-findings-copy" => ""}
          ),
        review_form: comparison_rollup_review_form(open_findings_json, review_requested?),
        preset_copy:
          clipboard_presentation(
            preset_path,
            "dashboard-comparison-preset-copy-component",
            "dashboard-comparison-preset-copy",
            "btn btn-ghost btn-xs gap-1",
            "hero-bookmark-square",
            "Preset",
            "Copy comparison investigation preset link",
            %{"data-dashboard-comparison-preset-copy" => ""}
          ),
        preset_form: comparison_rollup_preset_form(assigns.preset),
        saved_presets: comparison_rollup_saved_presets(assigns.saved_presets),
        details: comparison_rollup_details(groups, workflow_groups)
      }
    }
  end

  defp comparison_rollup_badges(rollup, groups, workflow_groups) do
    [
      summary_badge(
        comparison_rollup_count(rollup, :open_count),
        "open",
        "open",
        "badge badge-warning badge-xs",
        "data-dashboard-comparison-workflow-badge",
        comparison_rollup_group_placements(workflow_groups, "open")
      ),
      summary_badge(
        comparison_rollup_count(rollup, :handled_count),
        "handled",
        "handled",
        "badge badge-success badge-outline badge-xs",
        "data-dashboard-comparison-workflow-badge",
        comparison_rollup_group_placements(workflow_groups, "handled")
      ),
      summary_badge(
        comparison_rollup_count(rollup, :delta_count),
        "deltas",
        "deltas",
        "badge badge-info badge-xs",
        "data-dashboard-comparison-rollup-badge",
        comparison_rollup_group_placements(groups, "deltas")
      ),
      summary_badge(
        comparison_rollup_count(rollup, :unchanged_count),
        "unchanged",
        "unchanged",
        "badge badge-success badge-outline badge-xs",
        "data-dashboard-comparison-rollup-badge",
        comparison_rollup_group_placements(groups, "unchanged")
      ),
      summary_badge(
        comparison_rollup_count(rollup, :coverage_count),
        "coverage",
        "coverage",
        "badge badge-info badge-outline badge-xs",
        "data-dashboard-comparison-rollup-badge",
        comparison_rollup_group_placements(groups, "coverage")
      ),
      summary_badge(
        comparison_rollup_count(rollup, :missing_count),
        "missing",
        "missing",
        "badge badge-warning badge-outline badge-xs",
        "data-dashboard-comparison-rollup-badge",
        comparison_rollup_group_placements(groups, "missing")
      )
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp summary_badge(count, _key, _label, _class, _data_attr, _placements)
       when not is_number(count) or count <= 0,
       do: nil

  defp summary_badge(count, key, label, class, data_attr, placements) do
    %{
      key: key,
      attrs:
        element_attrs(%{
          "class" => class,
          data_attr => key,
          "data-dashboard-comparison-rollup-placements" => placements
        }),
      text: "#{count} #{label}"
    }
  end

  defp clipboard_presentation(nil, _host_id, _button_id, _class, _icon, _label, _title, _attrs),
    do: nil

  defp clipboard_presentation(text, host_id, button_id, class, icon, label, title, attrs) do
    %{
      host: %{attrs: element_attrs(%{"id" => host_id, "class" => "contents"})},
      props: %{
        button_id: button_id,
        clipboard_text: text,
        button_class: class,
        icon: icon,
        icon_class: "h-3.5 w-3.5",
        label: label,
        title: title,
        data_attrs: attrs
      }
    }
  end

  defp comparison_rollup_review_form(nil, _review_requested?), do: nil

  defp comparison_rollup_review_form(open_findings_json, review_requested?) do
    %{
      root: %{
        attrs:
          element_attrs(%{
            "id" => "dashboard-comparison-open-findings-review-form",
            "phx-submit" => "request_comparison_review",
            "class" => "inline-flex items-center"
          })
      },
      payload: %{
        attrs:
          element_attrs(%{
            "id" => "dashboard-comparison-open-findings-review-payload",
            "type" => "hidden",
            "name" => "review[open_findings]",
            "value" => open_findings_json
          })
      },
      button: %{
        attrs:
          element_attrs(%{
            "id" => "dashboard-comparison-open-findings-review",
            "type" => "submit",
            "class" => "btn btn-ghost btn-xs gap-1",
            "title" => comparison_rollup_review_title(review_requested?),
            "disabled" => review_requested?,
            "data-dashboard-comparison-open-findings-review" => "",
            "data-dashboard-comparison-open-findings-review-state" =>
              comparison_rollup_review_state(review_requested?)
          }),
        icon: icon_presentation("hero-flag", "h-3.5 w-3.5"),
        text: "Review"
      }
    }
  end

  defp comparison_rollup_preset_form(nil), do: nil

  defp comparison_rollup_preset_form(_preset) do
    %{
      root: %{
        attrs:
          element_attrs(%{
            "id" => "dashboard-comparison-preset-form",
            "phx-submit" => "save_comparison_preset",
            "class" => "join items-center"
          })
      },
      field: %{
        wrapper: %{attrs: element_attrs(%{"class" => "fieldset"})},
        label: %{attrs: %{}},
        input: %{
          attrs:
            element_attrs(%{
              "id" => "dashboard-comparison-preset-name",
              "name" => "preset[name]",
              "type" => "text",
              "value" => "",
              "placeholder" => "Preset name",
              "maxlength" => "120",
              "class" => "w-full input input-xs join-item w-40"
            })
        }
      },
      button: %{
        attrs:
          element_attrs(%{
            "id" => "dashboard-comparison-preset-save",
            "type" => "submit",
            "class" => "btn btn-xs btn-outline join-item gap-1",
            "title" => "Save comparison investigation preset"
          }),
        icon: icon_presentation("hero-bookmark", "h-3.5 w-3.5"),
        text: "Save"
      }
    }
  end

  defp comparison_rollup_saved_presets([]), do: nil

  defp comparison_rollup_saved_presets(saved_presets) do
    count = length(saved_presets)

    comparison_rollup_overlay(
      "dashboard-comparison-saved-presets",
      "Saved comparison presets",
      %{"data-dashboard-comparison-saved-presets" => count},
      %{
        class: "btn btn-ghost btn-xs gap-1",
        icon: icon_presentation("hero-book-open", "h-3.5 w-3.5"),
        text: "Saved",
        count: %{class: "badge badge-xs", text: rendered_text(count)}
      },
      %{
        kind: "saved_presets",
        attrs: element_attrs(%{"class" => "p-2 text-xs"}),
        items:
          saved_presets
          |> Enum.with_index()
          |> Enum.map(fn {preset, index} -> saved_preset_presentation(preset, index) end)
      }
    )
  end

  defp saved_preset_presentation(preset, index) do
    id = saved_preset_id(preset)
    affected_count = saved_preset_affected_count(preset)

    %{
      key: "saved-comparison-preset-#{index}-#{id}",
      root: %{
        attrs:
          element_attrs(%{
            "class" => "border-b border-base-300/60 py-2 last:border-b-0",
            "data-dashboard-comparison-saved-preset" => id,
            "data-dashboard-comparison-saved-preset-name" => saved_preset_name(preset),
            "data-dashboard-comparison-saved-preset-primary-view" =>
              saved_preset_primary_view(preset),
            "data-dashboard-comparison-saved-preset-compare-view" =>
              saved_preset_compare_view(preset),
            "data-dashboard-comparison-saved-preset-affected" => affected_count
          })
      },
      row: %{attrs: element_attrs(%{"class" => "flex items-start justify-between gap-2"})},
      copy: %{
        root: %{attrs: element_attrs(%{"class" => "min-w-0"})},
        name:
          text_presentation(
            saved_preset_name(preset),
            "truncate font-semibold text-base-content"
          ),
        summary:
          text_presentation(
            "#{saved_preset_view_pair(preset)} - #{affected_count} affected",
            "mt-0.5 font-mono text-[0.68rem] text-base-content/60"
          )
      },
      actions: %{
        attrs: element_attrs(%{"class" => "join shrink-0"}),
        apply: %{
          attrs:
            element_attrs(%{
              "type" => "button",
              "class" => "btn btn-xs btn-ghost join-item",
              "phx-click" => "apply_comparison_preset",
              "phx-value-preset-id" => id,
              "title" => "Load comparison preset",
              "data-dashboard-comparison-saved-preset-apply" => id
            }),
          icon: icon_presentation("hero-arrow-path", "h-3.5 w-3.5"),
          text: "Load"
        },
        delete: %{
          attrs:
            element_attrs(%{
              "type" => "button",
              "class" => "btn btn-xs btn-ghost join-item text-error",
              "phx-click" => "delete_comparison_preset",
              "phx-value-preset-id" => id,
              "data-confirm" => "Delete this comparison preset?",
              "title" => "Delete comparison preset",
              "data-dashboard-comparison-saved-preset-delete" => id
            }),
          icon: icon_presentation("hero-trash", "h-3.5 w-3.5"),
          text: ""
        }
      }
    }
  end

  defp comparison_rollup_overlay(id, label, root_attrs, trigger_content, body) do
    %{
      root: %{
        open_attr: "",
        attrs:
          root_attrs
          |> Map.merge(%{
            "id" => id,
            "data-overlay-kind" => "popover",
            "data-overlay-placement" => "bottom-end",
            "class" => "cadence-overlay"
          })
          |> element_attrs()
      },
      trigger: %{
        aria_expanded: %{open: "true", closed: "false"},
        attrs:
          element_attrs(%{
            "id" => "#{id}-trigger",
            "type" => "button",
            "data-overlay-trigger" => "",
            "aria-haspopup" => "dialog",
            "aria-expanded" => "false",
            "aria-controls" => "#{id}-panel",
            "aria-label" => label,
            "class" => "cadence-overlay-trigger"
          }),
        content: trigger_content
      },
      panel: %{
        attrs:
          element_attrs(%{
            "id" => "#{id}-panel",
            "data-overlay-panel" => "",
            "data-overlay-width" => "lg",
            "aria-label" => label,
            "class" => "cadence-overlay-panel cadence-popover-panel",
            "hidden" => true
          })
      },
      body: body
    }
  end

  defp comparison_rollup_details([], _workflow_groups), do: nil

  defp comparison_rollup_details(groups, workflow_groups) do
    comparison_rollup_overlay(
      "dashboard-comparison-rollup-detail",
      "Comparison details",
      %{"data-dashboard-comparison-rollup-detail" => ""},
      %{
        class: "btn btn-ghost btn-xs gap-1",
        icon: icon_presentation("hero-list-bullet", "h-3.5 w-3.5"),
        text: "Details",
        count: nil
      },
      %{
        kind: "details",
        attrs: element_attrs(%{"class" => "p-2 text-xs"}),
        workflow_groups:
          workflow_groups
          |> Enum.with_index()
          |> Enum.map(fn {group, index} -> workflow_group_presentation(group, index) end),
        groups:
          groups
          |> Enum.with_index()
          |> Enum.map(fn {group, index} -> comparison_group_presentation(group, index) end)
      }
    )
  end

  defp workflow_group_presentation(group, index) do
    key = Map.get(group, :key)

    %{
      key: "comparison-workflow-group-#{index}-#{rendered_text(key)}",
      root: %{
        attrs:
          element_attrs(%{
            "class" => "border-b border-base-300/60 py-2 last:border-b-0",
            "data-dashboard-comparison-rollup-workflow-group" => key,
            "data-dashboard-comparison-rollup-workflow-group-count" => Map.get(group, :count),
            "data-dashboard-comparison-rollup-placements" => Map.get(group, :placement_ids)
          })
      },
      heading: %{
        root: %{attrs: element_attrs(%{"class" => "flex items-center justify-between gap-2"})},
        label: text_presentation(rendered_text(Map.get(group, :label)), "hud-label"),
        count:
          text_presentation(
            rendered_text(Map.get(group, :count)),
            "font-mono text-base-content/60"
          )
      },
      items_root: %{attrs: element_attrs(%{"class" => "mt-1 space-y-1"})},
      items:
        group
        |> Map.get(:items, [])
        |> Enum.with_index()
        |> Enum.map(fn {item, item_index} ->
          workflow_item_presentation(item, key, item_index)
        end)
    }
  end

  defp workflow_item_presentation(item, group_key, index) do
    decision_status = comparison_rollup_item_value(item, :decision_status)

    %{
      key:
        "comparison-workflow-item-#{rendered_text(group_key)}-#{index}-#{rendered_text(Map.get(item, :placement_id))}",
      root: %{
        attrs:
          element_attrs(%{
            "data-dashboard-comparison-rollup-workflow-item" => Map.get(item, :placement_id),
            "data-dashboard-comparison-rollup-workflow-state" => Map.get(item, :state),
            "data-dashboard-comparison-rollup-workflow-decision-status" => decision_status,
            "class" =>
              "flex items-center justify-between gap-2 rounded px-1 py-0.5 hover:bg-base-200"
          })
      },
      link: %{
        attrs:
          element_attrs(%{
            "href" => comparison_rollup_item_href(item),
            "class" => "min-w-0 flex-1 truncate"
          }),
        text: rendered_text(Map.get(item, :title))
      },
      handled:
        if(decision_status == "applied",
          do: text_presentation("Handled", "badge badge-success badge-outline badge-xs"),
          else: nil
        ),
      label:
        text_presentation(
          rendered_text(Map.get(item, :label)),
          "font-mono text-base-content/60"
        )
    }
  end

  defp comparison_group_presentation(group, index) do
    key = Map.get(group, :key)

    %{
      key: "comparison-group-#{index}-#{rendered_text(key)}",
      root: %{
        attrs:
          element_attrs(%{
            "class" => "border-b border-base-300/60 py-2 last:border-b-0",
            "data-dashboard-comparison-rollup-group" => key,
            "data-dashboard-comparison-rollup-group-count" => Map.get(group, :count),
            "data-dashboard-comparison-rollup-group-handled" =>
              comparison_rollup_count(group, :handled_count),
            "data-dashboard-comparison-rollup-group-unhandled" =>
              comparison_rollup_count(group, :unhandled_count),
            "data-dashboard-comparison-rollup-placements" => Map.get(group, :placement_ids)
          })
      },
      heading: %{
        root: %{attrs: element_attrs(%{"class" => "flex items-center justify-between gap-2"})},
        label: text_presentation(rendered_text(Map.get(group, :label)), "hud-label"),
        count:
          text_presentation(
            rendered_text(Map.get(group, :count)),
            "font-mono text-base-content/60"
          )
      },
      items_root: %{attrs: element_attrs(%{"class" => "mt-1 space-y-1"})},
      items:
        group
        |> Map.get(:items, [])
        |> Enum.with_index()
        |> Enum.map(fn {item, item_index} ->
          comparison_item_presentation(item, key, item_index)
        end)
    }
  end

  defp comparison_item_presentation(item, group_key, index) do
    placement_id = Map.get(item, :placement_id)
    decision_status = comparison_rollup_item_value(item, :decision_status)

    %{
      key: "comparison-item-#{rendered_text(group_key)}-#{index}-#{rendered_text(placement_id)}",
      root: %{attrs: comparison_item_attrs(item)},
      row: %{
        attrs:
          element_attrs(%{
            "class" =>
              "flex items-center justify-between gap-2 rounded px-1 py-0.5 hover:bg-base-200"
          })
      },
      link: %{
        attrs:
          element_attrs(%{
            "href" => comparison_rollup_item_href(item),
            "class" => "min-w-0 flex-1 truncate"
          }),
        text: rendered_text(Map.get(item, :title))
      },
      handled:
        if(decision_status == "applied",
          do: %{
            attrs:
              element_attrs(%{
                "class" => "badge badge-success badge-outline badge-xs",
                "title" => "Comparison finding has an applied revision decision",
                "data-dashboard-comparison-rollup-handled" => placement_id
              }),
            text: "Handled"
          },
          else: nil
        ),
      label:
        text_presentation(
          rendered_text(Map.get(item, :label)),
          "font-mono text-base-content/60"
        ),
      actions: comparison_item_actions(item)
    }
  end

  defp comparison_item_attrs(item) do
    element_attrs(%{
      "data-dashboard-comparison-rollup-item" => Map.get(item, :placement_id),
      "data-dashboard-comparison-rollup-item-state" => Map.get(item, :state),
      "data-dashboard-comparison-rollup-item-widget" => Map.get(item, :widget_id),
      "data-dashboard-comparison-rollup-widget-type" =>
        comparison_rollup_item_value(item, :widget_type),
      "data-dashboard-comparison-rollup-widget-source" =>
        comparison_rollup_item_value(item, :widget_source),
      "data-dashboard-comparison-rollup-primary-kind" =>
        comparison_rollup_item_value(item, :primary_kind),
      "data-dashboard-comparison-rollup-compare-kind" =>
        comparison_rollup_item_value(item, :compare_kind),
      "data-dashboard-comparison-rollup-primary-observables" =>
        comparison_rollup_item_list_text(item, :primary_observable_ids),
      "data-dashboard-comparison-rollup-compare-observables" =>
        comparison_rollup_item_list_text(item, :compare_observable_ids),
      "data-dashboard-comparison-rollup-primary-count" =>
        comparison_rollup_item_value(item, :primary_count),
      "data-dashboard-comparison-rollup-compare-count" =>
        comparison_rollup_item_value(item, :compare_count),
      "data-dashboard-comparison-rollup-delta" => comparison_rollup_item_value(item, :delta),
      "data-dashboard-comparison-rollup-primary-sample" =>
        comparison_rollup_item_value(item, :primary_sample_id),
      "data-dashboard-comparison-rollup-compare-sample" =>
        comparison_rollup_item_value(item, :compare_sample_id),
      "data-dashboard-comparison-rollup-decision-status" =>
        comparison_rollup_item_value(item, :decision_status),
      "data-dashboard-comparison-rollup-decision-event" =>
        comparison_rollup_item_value(item, :decision_event_id),
      "data-dashboard-comparison-rollup-decision" =>
        comparison_rollup_item_value(item, :decision),
      "data-dashboard-comparison-rollup-decision-reason" =>
        comparison_rollup_item_value(item, :decision_reason),
      "data-dashboard-comparison-rollup-primary-data-management" =>
        comparison_rollup_item_data_management_codes(item, :primary_data_management),
      "data-dashboard-comparison-rollup-compare-data-management" =>
        comparison_rollup_item_data_management_codes(item, :compare_data_management),
      "data-dashboard-comparison-rollup-primary-link" =>
        item |> comparison_rollup_item_link(:primary_data_link) |> comparison_rollup_link_id(),
      "data-dashboard-comparison-rollup-compare-link" =>
        item |> comparison_rollup_item_link(:compare_data_link) |> comparison_rollup_link_id(),
      "data-dashboard-comparison-rollup-primary-link-target" =>
        item
        |> comparison_rollup_item_link(:primary_data_link)
        |> comparison_rollup_link_target(),
      "data-dashboard-comparison-rollup-compare-link-target" =>
        item
        |> comparison_rollup_item_link(:compare_data_link)
        |> comparison_rollup_link_target(),
      "data-dashboard-comparison-rollup-scope-kind" =>
        comparison_rollup_item_value(item, :scope_kind),
      "data-dashboard-comparison-rollup-scope-id" =>
        comparison_rollup_item_value(item, :scope_id),
      "data-dashboard-comparison-rollup-scope-ids" =>
        comparison_rollup_item_list_text(item, :scope_ids),
      "data-dashboard-comparison-rollup-resource-id" =>
        comparison_rollup_item_value(item, :resource_id),
      "data-dashboard-comparison-rollup-spacecraft-id" =>
        comparison_rollup_item_value(item, :spacecraft_id),
      "data-dashboard-comparison-rollup-contact-id" =>
        comparison_rollup_item_value(item, :contact_id),
      "data-dashboard-comparison-rollup-contact-ids" =>
        comparison_rollup_item_list_text(item, :contact_ids),
      "data-dashboard-comparison-rollup-transport-id" =>
        comparison_rollup_item_value(item, :transport_id),
      "data-dashboard-comparison-rollup-source-endpoint-id" =>
        comparison_rollup_item_value(item, :source_endpoint_id),
      "data-dashboard-comparison-rollup-ground-station-id" =>
        comparison_rollup_item_value(item, :ground_station_id),
      "data-dashboard-comparison-rollup-scope-link-id" =>
        comparison_rollup_item_value(item, :scope_link_id)
    })
  end

  defp comparison_item_actions(item) do
    [
      comparison_decision_action(item),
      comparison_handoff_action(item),
      comparison_sample_action(item, :primary_data_link, "primary"),
      comparison_sample_action(item, :compare_data_link, "compare")
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp comparison_decision_action(item) do
    case comparison_rollup_item_value(item, :decision_event_id) do
      value when value in [nil, false] ->
        nil

      decision_event_id ->
        attrs =
          DataLinkAttrs.open(comparison_rollup_handoff_link(item),
            link_id: "comparison-decision:#{decision_event_id}",
            target: "telemetry_revision_decision_event",
            target_id: decision_event_id,
            scope_kind: comparison_rollup_item_value(item, :scope_kind),
            scope_id: comparison_rollup_item_value(item, :scope_id),
            scope_ids: comparison_rollup_item_list_text(item, :scope_ids),
            resource_id: comparison_rollup_item_value(item, :resource_id),
            spacecraft_id: comparison_rollup_item_value(item, :spacecraft_id),
            contact_id: comparison_rollup_item_value(item, :contact_id),
            contact_ids: comparison_rollup_item_list_text(item, :contact_ids),
            transport_id: comparison_rollup_item_value(item, :transport_id),
            source_endpoint_id: comparison_rollup_item_value(item, :source_endpoint_id),
            ground_station_id: comparison_rollup_item_value(item, :ground_station_id),
            scope_link_id: comparison_rollup_item_value(item, :scope_link_id),
            data_view: comparison_rollup_item_value(item, :primary_view)
          )

        action_presentation(
          "comparison-decision-#{rendered_text(Map.get(item, :placement_id))}",
          attrs,
          %{
            "data-dashboard-comparison-rollup-decision-link" => Map.get(item, :placement_id),
            "title" => "Inspect applied decision",
            "aria-label" => "Inspect applied decision"
          },
          "hero-clipboard-document-check"
        )
    end
  end

  defp comparison_handoff_action(item) do
    if comparison_rollup_handoff?(item) do
      attrs =
        DataLinkAttrs.open(comparison_rollup_handoff_link(item),
          link_id: comparison_rollup_handoff_link_id(item),
          target: "comparison_finding",
          target_id: Map.get(item, :placement_id),
          placement_id: Map.get(item, :placement_id),
          widget_id: Map.get(item, :widget_id),
          widget_title: Map.get(item, :title),
          widget_type: comparison_rollup_item_value(item, :widget_type),
          widget_source: comparison_rollup_item_value(item, :widget_source),
          primary_kind: comparison_rollup_item_value(item, :primary_kind),
          compare_kind: comparison_rollup_item_value(item, :compare_kind),
          primary_observables: comparison_rollup_item_list_text(item, :primary_observable_ids),
          compare_observables: comparison_rollup_item_list_text(item, :compare_observable_ids),
          comparison_state: Map.get(item, :state),
          comparison_delta: comparison_rollup_item_value(item, :delta),
          primary_count: comparison_rollup_item_value(item, :primary_count),
          compare_count: comparison_rollup_item_value(item, :compare_count),
          primary_sample_id: comparison_rollup_item_value(item, :primary_sample_id),
          compare_sample_id: comparison_rollup_item_value(item, :compare_sample_id),
          primary_data_view: comparison_rollup_item_value(item, :primary_view),
          compare_data_view: comparison_rollup_item_value(item, :compare_view),
          primary_data_management:
            comparison_rollup_item_data_management_codes(item, :primary_data_management),
          compare_data_management:
            comparison_rollup_item_data_management_codes(item, :compare_data_management),
          scope_kind: comparison_rollup_item_value(item, :scope_kind),
          scope_id: comparison_rollup_item_value(item, :scope_id),
          scope_ids: comparison_rollup_item_list_text(item, :scope_ids),
          resource_id: comparison_rollup_item_value(item, :resource_id),
          spacecraft_id: comparison_rollup_item_value(item, :spacecraft_id),
          contact_id: comparison_rollup_item_value(item, :contact_id),
          contact_ids: comparison_rollup_item_list_text(item, :contact_ids),
          transport_id: comparison_rollup_item_value(item, :transport_id),
          source_endpoint_id: comparison_rollup_item_value(item, :source_endpoint_id),
          ground_station_id: comparison_rollup_item_value(item, :ground_station_id),
          scope_link_id: comparison_rollup_item_value(item, :scope_link_id),
          data_view: comparison_rollup_item_value(item, :primary_view)
        )

      action_presentation(
        "comparison-handoff-#{rendered_text(Map.get(item, :placement_id))}",
        attrs,
        %{
          "data-dashboard-comparison-rollup-handoff" => Map.get(item, :placement_id),
          "title" => "Open comparison finding",
          "aria-label" => "Open comparison finding"
        },
        "hero-arrow-turn-down-right"
      )
    end
  end

  defp comparison_sample_action(item, link_key, kind) do
    link = comparison_rollup_item_link(item, link_key)

    case comparison_rollup_link_id(link) do
      value when value in [nil, false] ->
        nil

      _link_id ->
        attrs = DataLinkAttrs.open(link, placement_id: Map.get(item, :placement_id))
        label = if kind == "primary", do: "primary", else: "compare"

        action_presentation(
          "comparison-#{kind}-sample-#{rendered_text(Map.get(item, :placement_id))}",
          attrs,
          %{
            "data-dashboard-comparison-rollup-link" => kind,
            "title" => "Inspect #{label} data",
            "aria-label" => "Inspect #{label} data"
          },
          "hero-magnifying-glass"
        )
    end
  end

  defp action_presentation(key, event_attrs, attrs, icon) do
    %{
      key: key,
      attrs:
        event_attrs
        |> Map.merge(%{
          "type" => "button",
          "phx-click" => "open_data_link",
          "class" => "btn btn-ghost btn-xs btn-square"
        })
        |> Map.merge(attrs)
        |> element_attrs(),
      icon: icon_presentation(icon, "h-3.5 w-3.5")
    }
  end

  defp text_presentation(text, class),
    do: %{attrs: element_attrs(%{"class" => class}), text: text}

  defp icon_presentation(name, class), do: %{name: name, class: class}

  defp element_attrs(attrs) do
    Enum.reduce(attrs, %{}, fn
      {_key, value}, result when value in [nil, false] ->
        result

      {key, true}, result ->
        Map.put(result, to_string(key), true)

      {key, value}, result ->
        Map.put(result, to_string(key), rendered_text(value))
    end)
  end

  defp rendered_text(nil), do: ""
  defp rendered_text(value) when is_binary(value), do: value
  defp rendered_text(value) when is_atom(value), do: Atom.to_string(value)
  defp rendered_text(value) when is_number(value), do: to_string(value)
  defp rendered_text(value), do: to_string(value)

  defp comparison_rollup_groups(rollup) when is_map(rollup), do: Map.get(rollup, :groups, [])
  defp comparison_rollup_groups(_rollup), do: []

  defp comparison_rollup_workflow_groups(rollup) when is_map(rollup),
    do: Map.get(rollup, :workflow_groups, [])

  defp comparison_rollup_workflow_groups(_rollup), do: []

  defp comparison_rollup_group_placements(groups, key) do
    groups
    |> Enum.find_value("", fn group ->
      if Map.get(group, :key) == key, do: Map.get(group, :placement_ids, "")
    end)
  end

  defp comparison_rollup_count(item, key) when is_map(item), do: Map.get(item, key, 0)
  defp comparison_rollup_count(_item, _key), do: 0

  defp comparison_rollup_item_href(%{placement_id: placement_id})
       when is_binary(placement_id) and placement_id != "",
       do: "#widget-#{placement_id}"

  defp comparison_rollup_item_href(_item), do: "#"

  defp comparison_rollup_preset_json(preset),
    do: ComparisonInvestigationPreset.encode(preset)

  defp comparison_rollup_open_findings_json(preset),
    do: ComparisonInvestigationPreset.encode_open_findings(preset)

  defp comparison_rollup_review_requested?(preset, open_review_summary) do
    preset_placement_ids =
      preset
      |> ComparisonInvestigationPreset.open_findings_export()
      |> open_findings_placement_ids()

    open_placement_ids =
      open_review_summary
      |> Map.get(:placement_ids, [])
      |> placement_ids()

    preset_placement_ids != [] and Enum.any?(preset_placement_ids, &(&1 in open_placement_ids))
  end

  defp comparison_rollup_review_state(true), do: "requested"
  defp comparison_rollup_review_state(false), do: "available"

  defp comparison_rollup_review_title(true), do: "Comparison review already requested"
  defp comparison_rollup_review_title(false), do: "Request review for open comparison findings"

  defp comparison_rollup_open_review_request_ids(open_review_summary)
       when is_map(open_review_summary) do
    open_review_summary
    |> Map.get(:request_ids, [])
    |> placement_ids()
    |> Enum.join(",")
  end

  defp comparison_rollup_open_review_request_ids(_open_review_summary), do: ""

  defp open_findings_placement_ids(%{} = open_findings) do
    placement_ids =
      open_findings
      |> get_in(["comparison", "open_placement_ids"])
      |> placement_ids()

    if placement_ids == [] do
      open_findings
      |> Map.get("findings")
      |> case do
        findings when is_list(findings) ->
          findings
          |> Enum.map(&Map.get(&1, "placement_id"))
          |> placement_ids()

        _value ->
          []
      end
    else
      placement_ids
    end
  end

  defp open_findings_placement_ids(_open_findings), do: []

  defp placement_ids(values) when is_list(values) do
    values
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp placement_ids(_values), do: []

  defp comparison_rollup_preset_path(preset),
    do: ComparisonInvestigationPreset.path(preset)

  defp comparison_rollup_handoff?(item) when is_map(item) do
    Map.get(item, :state) in ["increased", "decreased", "missing", "available"] and
      present_text(Map.get(item, :placement_id))
  end

  defp comparison_rollup_handoff?(_item), do: false

  defp comparison_rollup_handoff_link_id(item) when is_map(item),
    do: "comparison:#{Map.get(item, :placement_id)}"

  defp comparison_rollup_handoff_link(item) do
    if is_map(item) do
      comparison_rollup_item_link(item, :primary_data_link) ||
        comparison_rollup_item_link(item, :compare_data_link)
    end
  end

  defp saved_preset_id(preset), do: map_value(preset, :dashboard_investigation_preset_id, "")

  defp saved_preset_name(preset), do: map_value(preset, :name, "Untitled preset")

  defp saved_preset_primary_view(preset), do: map_value(preset, :primary_data_view, "canonical")

  defp saved_preset_compare_view(preset), do: map_value(preset, :compare_data_view, "compare")

  defp saved_preset_affected_count(preset) do
    preset
    |> map_value(:affected_placement_ids, [])
    |> case do
      values when is_list(values) -> length(values)
      _value -> 0
    end
  end

  defp saved_preset_view_pair(preset) do
    "#{data_view_label(saved_preset_primary_view(preset))} vs #{data_view_label(saved_preset_compare_view(preset))}"
  end

  defp map_value(map, key, default) when is_map(map) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end

  defp map_value(_map, _key, default), do: default

  defp comparison_rollup_item_value(item, key) when is_map(item), do: Map.get(item, key)
  defp comparison_rollup_item_value(_item, _key), do: nil

  defp comparison_rollup_item_list_text(item, key) when is_map(item) do
    item
    |> Map.get(key)
    |> list_text()
  end

  defp comparison_rollup_item_list_text(_item, _key), do: nil

  defp comparison_rollup_item_data_management_codes(item, key) when is_map(item) do
    item
    |> Map.get(key)
    |> data_management_codes()
  end

  defp comparison_rollup_item_data_management_codes(_item, _key), do: nil

  defp data_management_codes(%{badges: badges}) when is_list(badges) do
    badges
    |> Enum.map(&data_management_badge_value/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.join(",")
    |> present_text()
  end

  defp data_management_codes(%{"badges" => badges}) when is_list(badges) do
    data_management_codes(%{badges: badges})
  end

  defp data_management_codes(_summary), do: nil

  defp data_management_badge_value(%{value: value}), do: present_text(value)
  defp data_management_badge_value(%{"value" => value}), do: present_text(value)
  defp data_management_badge_value(_badge), do: nil

  defp list_text(values) when is_list(values) do
    values
    |> Enum.map(&present_text/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.join(",")
    |> present_text()
  end

  defp list_text(value), do: present_text(value)

  defp comparison_rollup_item_link(item, key) when is_map(item), do: Map.get(item, key)
  defp comparison_rollup_item_link(_item, _key), do: nil

  defp comparison_rollup_link_id(link) when is_map(link),
    do: Map.get(link, :link_id, Map.get(link, "link_id"))

  defp comparison_rollup_link_id(_link), do: nil

  defp comparison_rollup_link_target(link) when is_map(link) do
    Map.get(link, :target_text, Map.get(link, "target_text")) ||
      Map.get(link, :target, Map.get(link, "target"))
  end

  defp comparison_rollup_link_target(_link), do: nil

  defp data_view_options do
    [
      {"Canonical", "canonical"},
      {"As recorded", "as_recorded"},
      {"All revisions", "all_revisions"},
      {"Recomputed", "recomputed"}
    ]
  end

  defp data_view_label(value) do
    value = present_text(value)

    data_view_options()
    |> Enum.find_value(value || "Canonical", fn {label, option_value} ->
      if option_value == value, do: label
    end)
  end

  defp present_text(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" -> nil
      value -> value
    end
  end

  defp present_text(_value), do: nil
end
