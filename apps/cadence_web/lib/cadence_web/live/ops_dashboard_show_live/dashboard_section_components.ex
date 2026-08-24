defmodule CadenceWeb.OpsDashboardShowLive.DashboardSectionComponents do
  @moduledoc false
  use CadenceWeb, :html

  attr :document, :any, required: true
  attr :form, Phoenix.HTML.Form, required: true
  attr :error, :string, default: nil

  def section_manager(assigns) do
    assigns = assign(assigns, :section_list, section_list_dto(assigns.document.sections))

    ~H"""
    <div class="space-y-5">
      <.vue
        id="dashboard-section-list-component"
        v-component="DashboardSectionList"
        presentation={@section_list}
        v-ssr={false}
        class="contents"
      />

      <.form
        for={@form}
        id="dashboard-section-form"
        phx-change="validate_dashboard_section"
        phx-submit="save_dashboard_section"
        class="space-y-3 border-t border-base-300/60 pt-4"
      >
        <input type="hidden" name={@form[:section_id].name} value={@form[:section_id].value} />
        <p class="hud-label">
          {if @form[:section_id].value in [nil, ""], do: "Add section", else: "Edit section"}
        </p>
        <.input field={@form[:title]} type="text" label="Title" required />
        <.input field={@form[:description]} type="textarea" label="Description" />
        <.input
          field={@form[:collapsed_by_default]}
          type="checkbox"
          label="Collapse by default for operators"
        />
        <p :if={@error} class="text-sm text-error">{@error}</p>
        <div class="flex gap-2">
          <.button id="save-dashboard-section" type="submit" size={:sm}>
            {if @form[:section_id].value in [nil, ""], do: "Add section", else: "Save section"}
          </.button>
          <button
            :if={@form[:section_id].value not in [nil, ""]}
            type="button"
            phx-click="open_dashboard_sections"
            class="btn btn-ghost btn-sm"
          >Cancel</button>
        </div>
      </.form>
    </div>
    """
  end

  defp section_list_dto(sections) do
    last_index = length(sections) - 1

    %{
      root: %{
        attrs:
          raw_attributes(%{
            "id" => "dashboard-section-list",
            "class" => "space-y-2"
          })
      },
      empty: %{
        visible: sections == [],
        attrs: raw_attributes(%{"class" => "text-sm text-base-content/60"}),
        text: "No sections yet. Existing widgets remain in the unsectioned canvas."
      },
      sections:
        sections
        |> Enum.with_index()
        |> Enum.map(fn {section, index} -> section_dto(section, index, last_index) end)
    }
  end

  defp section_dto(section, index, last_index) do
    section_id = rendered_body(section.section_id)
    title = rendered_body(section.title)

    %{
      key: "dashboard-section-#{section_id}",
      order: index,
      attrs:
        raw_attributes(%{
          "id" => "dashboard-section-#{section_id}",
          "class" => "rounded border border-base-300/60 bg-base-200/35 p-3",
          "data-dashboard-section" => section.section_id
        }),
      layout: %{attrs: raw_attributes(%{"class" => "flex items-start gap-2"})},
      icon: %{
        attrs:
          raw_attributes(%{
            "class" => class_list(["hero-rectangle-group", "mt-0.5 h-4 w-4 text-primary"])
          })
      },
      content: %{
        attrs: raw_attributes(%{"class" => "min-w-0 flex-1"}),
        title: %{
          attrs: raw_attributes(%{"class" => "font-medium"}),
          text: title
        },
        description: %{
          visible: truthy?(section.description),
          attrs: raw_attributes(%{"class" => "mt-0.5 text-xs text-base-content/55"}),
          text: rendered_body(section.description)
        },
        default_state: %{
          attrs:
            raw_attributes(%{
              "class" => "mt-1 inline-flex font-mono text-[0.65rem] text-base-content/45"
            }),
          text:
            if(truthy?(section.collapsed_by_default?),
              do: "Collapsed by default",
              else: "Open by default"
            )
        }
      },
      actions: %{
        attrs: raw_attributes(%{"class" => "flex gap-1"}),
        buttons: section_action_dtos(section.section_id, title, index, last_index)
      }
    }
  end

  defp section_action_dtos(section_id, title, index, last_index) do
    [
      section_action_dto(
        "move-up",
        "move_dashboard_section",
        section_id,
        "Move #{title} up",
        "hero-arrow-up",
        direction: "up",
        disabled: index == 0
      ),
      section_action_dto(
        "move-down",
        "move_dashboard_section",
        section_id,
        "Move #{title} down",
        "hero-arrow-down",
        direction: "down",
        disabled: index == last_index
      ),
      section_action_dto(
        "edit",
        "edit_dashboard_section",
        section_id,
        "Edit #{title}",
        "hero-pencil-square"
      ),
      section_action_dto(
        "remove",
        "remove_dashboard_section",
        section_id,
        "Remove #{title}",
        "hero-trash",
        class: "btn btn-ghost btn-xs btn-square text-error",
        confirm: "Remove this section? Its widgets will move to the unsectioned canvas."
      )
    ]
  end

  defp section_action_dto(key, event, section_id, aria_label, icon, opts \\ []) do
    %{
      key: key,
      attrs:
        raw_attributes(%{
          "type" => "button",
          "phx-click" => event,
          "phx-value-section-id" => section_id,
          "phx-value-direction" => Keyword.get(opts, :direction),
          "disabled" => Keyword.get(opts, :disabled),
          "class" => Keyword.get(opts, :class, "btn btn-ghost btn-xs btn-square"),
          "data-confirm" => Keyword.get(opts, :confirm),
          "aria-label" => aria_label
        }),
      icon: %{
        attrs: raw_attributes(%{"class" => class_list([icon, "h-3.5 w-3.5"])})
      }
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
