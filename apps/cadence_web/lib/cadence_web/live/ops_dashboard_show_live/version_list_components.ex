defmodule CadenceWeb.OpsDashboardShowLive.VersionListComponents do
  @moduledoc false
  use CadenceWeb, :html

  attr :version_history, :map, required: true

  def version_overview(assigns) do
    assigns =
      assign(assigns, :presentation, version_overview_presentation(assigns.version_history))

    ~H"""
    <.vue
      id="dashboard-version-overview-component"
      v-component="VersionList"
      presentation={@presentation}
      v-ssr={false}
      class="contents"
    />
    """
  end

  def version_overview_presentation(version_history) do
    %{
      root: %{
        attrs: raw_attributes(%{"class" => "space-y-5"})
      },
      pointers: %{
        attrs: raw_attributes(%{"class" => "grid grid-cols-3 gap-2 text-xs"}),
        items:
          version_history.pointers
          |> Enum.with_index()
          |> Enum.map(fn {pointer, order} -> pointer_metric_dto(pointer, order) end)
      },
      versions: %{
        section: %{
          attrs: raw_attributes(%{"class" => "space-y-2"})
        },
        header: %{
          attrs: raw_attributes(%{"class" => "flex items-center justify-between"}),
          heading: %{
            attrs: raw_attributes(%{"class" => "hud-label"}),
            text: "Versions"
          },
          count: %{
            attrs: raw_attributes(%{"class" => "font-mono text-xs text-base-content/50"}),
            text: rendered_body(version_history.count)
          }
        },
        list: %{
          attrs:
            raw_attributes(%{
              "id" => "dashboard-version-list",
              "class" => "space-y-2"
            }),
          rows:
            version_history.versions
            |> Enum.with_index()
            |> Enum.map(fn {version, order} -> version_row_dto(version, order) end)
        },
        empty: %{
          visible: truthy?(version_history.empty),
          attrs: raw_attributes(%{"class" => "text-sm text-base-content/60"}),
          text: "No saved versions."
        }
      }
    }
  end

  defp pointer_metric_dto(pointer, order) do
    %{
      key: "pointer-#{order}",
      order: order,
      attrs:
        raw_attributes(%{
          "class" => "border border-base-300/70 bg-base-100/40 px-2 py-1.5"
        }),
      label: %{
        attrs: raw_attributes(%{"class" => "hud-label"}),
        text: rendered_body(pointer.label)
      },
      value: %{
        attrs: raw_attributes(%{"class" => "font-mono text-sm"}),
        text: rendered_body(pointer.value)
      }
    }
  end

  defp version_row_dto(version, order) do
    %{
      key: rendered_body(version.dom_id),
      order: order,
      attrs:
        raw_attributes(%{
          "id" => version.dom_id,
          "data-version-restore-available" => version.restore_action.available_text,
          "data-version-restore-reason" => version.restore_action.reason_text,
          "data-version-publish-available" => version.publish_action.available_text,
          "data-version-publish-reason" => version.publish_action.reason_text,
          "data-version-lineage-kind" => version.lineage.kind,
          "data-version-lineage-source-version" => version.lineage.source_version_text,
          "class" => "border border-base-300/70 bg-base-100/40 p-2"
        }),
      layout: %{
        attrs: raw_attributes(%{"class" => "flex items-start justify-between gap-3"})
      },
      content: %{
        attrs: raw_attributes(%{"class" => "min-w-0"})
      },
      identity: %{
        attrs: raw_attributes(%{"class" => "flex flex-wrap items-center gap-1.5"}),
        version: %{
          attrs: raw_attributes(%{"class" => "font-mono text-sm font-semibold"}),
          text: "v" <> rendered_body(version.version)
        },
        snapshot: %{
          attrs: raw_attributes(%{"class" => "badge badge-xs badge-outline"}),
          text: rendered_body(version.snapshot_label)
        },
        pointers:
          version.pointer_labels
          |> Enum.with_index()
          |> Enum.map(fn {pointer, pointer_order} ->
            version_pointer_dto(pointer, pointer_order)
          end)
      },
      details: %{
        attrs:
          raw_attributes(%{
            "class" => "mt-2 grid grid-cols-[5.5rem_1fr] gap-x-2 gap-y-1 text-xs"
          }),
        rows: [
          detail_row_dto("saved", 0, "Saved", version.saved_at),
          detail_row_dto("author", 1, "Author", version.created_by,
            value_class: "truncate text-base-content/70",
            data_field: "Author"
          ),
          detail_row_dto("origin", 2, "Origin", version.lineage.label, data_field: "Origin"),
          detail_row_dto("parent", 3, "Parent", version.parent_version),
          detail_row_dto("based-on", 4, "Based on", version.based_on_version)
        ]
      },
      summary: %{
        visible: truthy?(version.change_summary),
        attrs:
          raw_attributes(%{
            "data-version-field" => "Summary",
            "class" => "mt-2 text-xs text-base-content/70"
          }),
        text: rendered_body(version.change_summary)
      },
      actions: %{
        attrs: raw_attributes(%{"class" => "flex shrink-0 flex-col gap-1"}),
        buttons: [
          version_action_dto(version, :publish),
          version_action_dto(version, :restore)
        ]
      }
    }
  end

  defp version_pointer_dto(pointer, order) do
    %{
      key: "version-pointer-#{order}",
      order: order,
      attrs:
        raw_attributes(%{
          "data-version-pointer" => pointer.label,
          "class" => class_list(["badge badge-xs", pointer.badge_class])
        }),
      text: rendered_body(pointer.label)
    }
  end

  defp detail_row_dto(key, order, label, value, opts \\ []) do
    %{
      key: key,
      order: order,
      label: %{
        attrs: raw_attributes(%{"class" => "hud-label"}),
        text: rendered_body(label)
      },
      value: %{
        attrs:
          raw_attributes(%{
            "data-version-field" => Keyword.get(opts, :data_field),
            "class" => Keyword.get(opts, :value_class, "font-mono text-base-content/70")
          }),
        text: rendered_body(value)
      }
    }
  end

  defp version_action_dto(version, :publish) do
    action_button_dto(
      version.publish_button_id,
      "publish_dashboard_version",
      version.version,
      version.publish_action,
      version.publish_confirm,
      "publish",
      "hero-arrow-up-tray",
      "Publish"
    )
  end

  defp version_action_dto(version, :restore) do
    action_button_dto(
      version.restore_button_id,
      "restore_version_as_draft",
      version.version,
      version.restore_action,
      version.restore_confirm,
      "restore",
      "hero-arrow-uturn-left",
      "Restore"
    )
  end

  defp action_button_dto(id, event, version, action, confirm, action_name, icon, text) do
    %{
      key: action_name,
      attrs:
        raw_attributes(%{
          "id" => id,
          "type" => "button",
          "class" => "btn btn-ghost btn-xs",
          "phx-click" => event,
          "phx-value-version" => version,
          "disabled" => not action.available,
          "data-version-action" => action_name,
          "data-version-action-available" => action.available_text,
          "data-version-action-reason" => action.reason_text,
          "data-confirm" => confirm
        }),
      icon: %{
        attrs: raw_attributes(%{"class" => class_list([icon, "h-3.5 w-3.5"])})
      },
      text: text
    }
  end

  defp raw_attributes(attributes) do
    Enum.reduce(attributes, %{}, fn
      {_key, value}, rendered when value in [nil, false] ->
        rendered

      {key, true}, rendered ->
        Map.put(rendered, to_string(key), "")

      {key, value}, rendered ->
        Map.put(rendered, to_string(key), rendered_body(value))
    end)
  end

  defp class_list(classes) do
    classes
    |> Enum.reject(&(&1 in [nil, false]))
    |> Enum.map(&rendered_body/1)
    |> Enum.join(" ")
  end

  defp truthy?(value), do: value not in [nil, false]

  defp rendered_body(nil), do: ""
  defp rendered_body(value), do: to_string(value)
end
