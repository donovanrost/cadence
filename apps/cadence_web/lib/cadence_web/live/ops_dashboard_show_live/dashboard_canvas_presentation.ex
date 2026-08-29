defmodule CadenceWeb.OpsDashboardShowLive.DashboardCanvasPresentation do
  @moduledoc false

  alias CadenceWeb.OpsDashboardShowLive.ComparisonInspectorComponents
  alias CadenceWeb.OpsDashboardShowLive.Components

  def build(render_model, context, opts \\ []) when is_map(render_model) and is_map(context) do
    widget_presentation =
      Keyword.get(opts, :widget_presentation, &Components.widget_presentation/1)

    comparison_presentation =
      Keyword.get(
        opts,
        :comparison_presentation,
        &ComparisonInspectorComponents.presentation/5
      )

    editor_route? = Map.get(context, :editor_route?, false)

    comparison_inspector =
      comparison_presentation.(
        render_model.comparison_inspector_open?,
        render_model.comparison_rollup,
        render_model.comparison_preset,
        render_model.open_review_summary,
        render_model.comparison_presets
      )

    %{
      root: %{attrs: raw_attributes(%{"class" => "flex flex-1 min-h-0"})},
      content: %{attrs: raw_attributes(render_model.content_attrs)},
      groups:
        Enum.map(render_model.widget_groups, fn group ->
          group_presentation(group, editor_route?, widget_presentation)
        end),
      empty_state: empty_state_presentation(render_model.empty_state, context),
      comparison_inspector: comparison_inspector_presentation(comparison_inspector)
    }
  end

  defp group_presentation(group, editor_route?, widget_presentation) do
    group_id = rendered_string(group.id)
    widget_count = length(group.widget_items)

    %{
      key: group_id,
      root: %{
        attrs:
          raw_attributes(%{
            "id" => "dashboard-widget-group-#{group_id}",
            "class" =>
              class_list([
                editor_route? && "border-b border-base-300/45 last:border-b-0",
                not editor_route? && "pt-1"
              ]),
            "data-dashboard-widget-group" => group_id
          })
      },
      section: section_presentation(group, group_id, widget_count, editor_route?),
      header: unsectioned_header_presentation(group, widget_count, editor_route?),
      grid: grid_presentation(group, widget_presentation)
    }
  end

  defp section_presentation(%{section: nil}, _group_id, _widget_count, _editor_route?),
    do: nil

  defp section_presentation(group, group_id, widget_count, editor_route?) do
    section = group.section
    description = Map.get(section, :description, Map.get(section, "description"))

    %{
      root: %{
        attrs:
          raw_attributes(%{
            "id" => "dashboard-section-group-#{group_id}",
            "open" => group.open?,
            "class" => "group/dashboard-section",
            "data-dashboard-section" => group_id
          })
      },
      summary: %{
        attrs:
          raw_attributes(%{
            "class" =>
              class_list([
                "flex cursor-pointer list-none items-center gap-2 marker:hidden",
                if(editor_route?,
                  do:
                    "sticky top-0 z-10 border-b border-base-300/50 bg-base-200/90 px-3 py-2 backdrop-blur",
                  else: "mx-2 rounded px-1 py-1.5 text-base-content/65 hover:text-base-content"
                )
              ])
          }),
        icon: %{
          attrs:
            raw_attributes(%{
              "class" =>
                "hero-chevron-right h-3.5 w-3.5 text-base-content/45 transition-transform group-data-[state=open]/dashboard-section:rotate-90"
            })
        },
        copy: %{
          attrs: raw_attributes(%{"class" => "min-w-0 flex-1"}),
          title: %{
            attrs: raw_attributes(%{"class" => "text-xs font-semibold uppercase tracking-wide"}),
            text: rendered_body(Map.get(section, :title, Map.get(section, "title")))
          },
          description:
            if(editor_route? and description not in [nil, false],
              do: %{
                attrs:
                  raw_attributes(%{
                    "class" => "truncate text-[0.65rem] text-base-content/50"
                  }),
                text: rendered_body(description)
              }
            )
        },
        count:
          if(editor_route?,
            do: %{
              attrs:
                raw_attributes(%{
                  "class" => "font-mono text-[0.65rem] text-base-content/45"
                }),
              text: widget_count_text(widget_count)
            }
          )
      }
    }
  end

  defp unsectioned_header_presentation(%{section: section}, _widget_count, _editor_route?)
       when not is_nil(section),
       do: nil

  defp unsectioned_header_presentation(%{show_header?: false}, _widget_count, _editor_route?),
    do: nil

  defp unsectioned_header_presentation(_group, widget_count, editor_route?) do
    %{
      attrs:
        raw_attributes(%{
          "class" =>
            class_list([
              "flex items-center gap-2 px-3",
              if(editor_route?,
                do: "border-b border-base-300/50 bg-base-200/65 py-2",
                else: "py-1.5 text-base-content/65"
              )
            ])
        }),
      icon: %{
        attrs:
          raw_attributes(%{
            "class" => "hero-square-3-stack-3d h-3.5 w-3.5 text-base-content/45"
          })
      },
      title: %{
        attrs: raw_attributes(%{"class" => "text-xs font-semibold uppercase tracking-wide"}),
        text: "Unsectioned canvas"
      },
      count:
        if(editor_route?,
          do: %{
            attrs:
              raw_attributes(%{
                "class" => "ml-auto font-mono text-[0.65rem] text-base-content/45"
              }),
            text: widget_count_text(widget_count)
          }
        )
    }
  end

  defp grid_presentation(group, widget_presentation) do
    %{
      root: %{attrs: raw_attributes(group.grid_props)},
      widgets:
        Enum.map(group.widget_items, fn widget_item ->
          presentation = widget_presentation.(widget_item.component_props)
          shell_attrs = raw_attributes(widget_item.shell_attrs)

          %{
            key: Map.get(shell_attrs, "gs-id") || presentation.component_id,
            shell: %{attrs: shell_attrs},
            content: %{attrs: raw_attributes(%{"class" => widget_item.content_class})},
            host: %{
              attrs:
                raw_attributes(%{
                  "id" => presentation.component_id,
                  "class" => "contents"
                })
            },
            presentation: presentation
          }
        end),
      controller: %{
        host: %{
          attrs:
            raw_attributes(%{
              "id" => group.grid_controller_props.id,
              "class" => "hidden"
            })
        },
        props: %{
          target_id: group.grid_controller_props.target_id,
          edit_mode: group.grid_controller_props.edit_mode,
          item_ids: group.grid_controller_props.item_ids
        }
      }
    }
  end

  defp empty_state_presentation(%{visible?: true} = empty_state, context) do
    editor_route? = Map.get(context, :editor_route?, false)

    %{
      wrapper: %{attrs: raw_attributes(%{"class" => empty_state.wrapper_class})},
      card: %{attrs: raw_attributes(%{"class" => empty_state.card_class})},
      icon: %{attrs: raw_attributes(%{"class" => empty_state.icon_class})},
      title: %{
        attrs: raw_attributes(%{"class" => "hud-label mt-3"}),
        text: rendered_body(empty_state.title)
      },
      message: %{
        attrs: raw_attributes(%{"class" => "mt-2 max-w-md mx-auto text-sm text-base-content/70"}),
        text: rendered_body(empty_state.message)
      },
      actions: %{
        attrs: raw_attributes(%{"class" => "mt-5"}),
        action: empty_state_action(empty_state, context, editor_route?)
      }
    }
  end

  defp empty_state_presentation(_empty_state, _context), do: nil

  defp comparison_inspector_presentation(nil), do: nil

  defp comparison_inspector_presentation(presentation) do
    %{
      host: %{
        attrs:
          raw_attributes(%{
            "id" => "dashboard-comparison-inspector-component",
            "class" => "contents"
          })
      },
      presentation: presentation
    }
  end

  defp empty_state_action(empty_state, _context, true) do
    %{
      kind: "button",
      attrs:
        raw_attributes(%{
          "id" => "dashboard-editor-empty-add-widget",
          "type" => "button",
          "class" => "btn btn-primary btn-sm",
          "phx-click" => empty_state.action_event
        }),
      icon: %{
        attrs:
          raw_attributes(%{
            "class" => "#{empty_state.action_icon} -ml-0.5 mr-1 h-4 w-4"
          })
      },
      text: rendered_body(empty_state.action_label)
    }
  end

  defp empty_state_action(_empty_state, context, false) do
    if Map.get(context, :dashboard_author?, false) do
      %{
        kind: "link",
        attrs:
          raw_attributes(%{
            "id" => "dashboard-viewer-empty-edit",
            "href" => Map.fetch!(context, :empty_edit_path),
            "data-phx-link" => "redirect",
            "data-phx-link-state" => "push",
            "class" => "btn btn-primary btn-sm"
          }),
        icon: %{
          attrs: raw_attributes(%{"class" => "hero-pencil-square h-4 w-4"})
        },
        text: "Open Dashboard Editor"
      }
    end
  end

  defp widget_count_text(1), do: "1 widget"
  defp widget_count_text(count), do: "#{count} widgets"

  defp class_list(values) do
    values
    |> Enum.reject(&(&1 in [nil, false]))
    |> Enum.map_join(" ", &rendered_string/1)
  end

  defp raw_attributes(attributes) do
    Enum.reduce(attributes, %{}, fn
      {_key, value}, rendered when value in [nil, false] ->
        rendered

      {key, true}, rendered ->
        Map.put(rendered, to_string(key), "")

      {key, value}, rendered ->
        Map.put(rendered, to_string(key), rendered_string(value))
    end)
  end

  defp rendered_string(value) when is_binary(value), do: value
  defp rendered_string(value), do: to_string(value)

  defp rendered_body(nil), do: ""
  defp rendered_body(value) when is_binary(value), do: value
  defp rendered_body(value), do: to_string(value)
end
