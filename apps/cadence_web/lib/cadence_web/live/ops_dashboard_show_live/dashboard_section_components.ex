defmodule CadenceWeb.OpsDashboardShowLive.DashboardSectionComponents do
  @moduledoc false
  use CadenceWeb, :html

  attr :document, :any, required: true
  attr :form, Phoenix.HTML.Form, required: true
  attr :error, :string, default: nil

  def section_manager(assigns) do
    assigns = assign(assigns, :presentation, section_manager_presentation(assigns))

    ~H"""
    <.vue
      id="dashboard-section-manager-component"
      v-component="DashboardSectionManager"
      presentation={@presentation}
      v-ssr={false}
      class="contents"
    />
    """
  end

  defp section_manager_presentation(assigns) do
    editing? = assigns.form[:section_id].value not in [nil, ""]

    %{
      root: %{attrs: raw_attributes(%{"class" => "space-y-5"})},
      section_list: section_list_presentation(assigns.document.sections),
      form: section_form_presentation(assigns.form, assigns.error, editing?)
    }
  end

  def section_list_presentation(sections) do
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

  defp section_form_presentation(form, error, editing?) do
    %{
      root: %{
        attrs:
          raw_attributes(%{
            "id" => "dashboard-section-form",
            "phx-change" => "validate_dashboard_section",
            "phx-submit" => "save_dashboard_section",
            "class" => "space-y-3 border-t border-base-300/60 pt-4"
          }),
        param: rendered_body(form.name),
        params: active_form_params(form)
      },
      section_id: %{
        attrs:
          raw_attributes(%{
            "type" => "hidden",
            "name" => form[:section_id].name,
            "value" => form[:section_id].value
          })
      },
      heading: %{
        attrs: raw_attributes(%{"class" => "hud-label"}),
        text: if(editing?, do: "Edit section", else: "Add section")
      },
      title: standard_field_presentation(form, :title, "text", "Title", required: true),
      description: textarea_field_presentation(form, :description, "Description"),
      collapsed_by_default:
        checkbox_field_presentation(
          form,
          :collapsed_by_default,
          "Collapse by default for operators"
        ),
      error: optional_text_presentation(error, "text-sm text-error"),
      actions: %{
        attrs: raw_attributes(%{"class" => "flex gap-2"}),
        save: %{
          attrs:
            raw_attributes(%{
              "id" => "save-dashboard-section",
              "type" => "submit",
              "class" => "btn btn-primary btn-sm"
            }),
          text: if(editing?, do: "Save section", else: "Add section")
        },
        cancel: %{
          visible: editing?,
          attrs:
            raw_attributes(%{
              "type" => "button",
              "phx-click" => "open_dashboard_sections",
              "class" => "btn btn-ghost btn-sm"
            }),
          text: "Cancel"
        }
      }
    }
  end

  defp standard_field_presentation(form, field, type, label, options) do
    form_field = form[field]
    errors = form_field_errors(form_field)

    %{
      wrapper: %{attrs: raw_attributes(%{"class" => "fieldset mb-3"})},
      label: %{
        attrs: raw_attributes(%{"class" => "hud-label block mb-1.5"}),
        text: label
      },
      control: %{
        attrs:
          raw_attributes(%{
            "id" => form_field.id,
            "name" => form_field.name,
            "type" => type,
            "value" => form_field.value,
            "required" => Keyword.get(options, :required, false),
            "class" => class_list(["w-full input", errors != [] && "input-error"])
          })
      },
      errors: Enum.map(errors, &field_error_presentation/1)
    }
  end

  defp textarea_field_presentation(form, field, label) do
    form_field = form[field]
    errors = form_field_errors(form_field)

    %{
      wrapper: %{attrs: raw_attributes(%{"class" => "fieldset mb-3"})},
      label: %{
        attrs: raw_attributes(%{"class" => "hud-label block mb-1.5"}),
        text: label
      },
      control: %{
        attrs:
          raw_attributes(%{
            "id" => form_field.id,
            "name" => form_field.name,
            "class" => class_list(["w-full textarea", errors != [] && "textarea-error"])
          }),
        text: rendered_body(form_field.value)
      },
      errors: Enum.map(errors, &field_error_presentation/1)
    }
  end

  defp checkbox_field_presentation(form, field, label) do
    form_field = form[field]

    %{
      wrapper: %{attrs: raw_attributes(%{"class" => "fieldset mb-3"})},
      label: %{
        attrs: raw_attributes(%{"class" => "flex cursor-pointer items-start gap-3"})
      },
      hidden_control: %{
        attrs:
          raw_attributes(%{
            "type" => "hidden",
            "name" => form_field.name,
            "value" => "false"
          })
      },
      control: %{
        attrs:
          raw_attributes(%{
            "type" => "checkbox",
            "id" => form_field.id,
            "name" => form_field.name,
            "value" => "true",
            "checked" => to_string(form_field.value) == "true",
            "class" => "checkbox checkbox-sm mt-0.5"
          })
      },
      text: %{
        wrapper: %{attrs: %{}},
        label: %{
          attrs: raw_attributes(%{"class" => "block text-sm font-medium"}),
          text: label
        }
      }
    }
  end

  defp active_form_params(form) do
    Map.new([:section_id, :title, :description, :collapsed_by_default], fn field ->
      value = form[field].value

      active_value =
        if field == :collapsed_by_default,
          do: if(to_string(value) == "true", do: "true", else: "false"),
          else: rendered_body(value)

      {Atom.to_string(field), active_value}
    end)
  end

  defp form_field_errors(form_field) do
    if Phoenix.Component.used_input?(form_field), do: form_field.errors, else: []
  end

  defp field_error_presentation({message, _opts}),
    do: %{attrs: raw_attributes(%{"class" => "mt-1.5 text-sm text-error"}), text: message}

  defp field_error_presentation(message),
    do: %{attrs: raw_attributes(%{"class" => "mt-1.5 text-sm text-error"}), text: message}

  defp optional_text_presentation(nil, _class), do: nil
  defp optional_text_presentation(false, _class), do: nil

  defp optional_text_presentation(text, class_name) do
    %{attrs: raw_attributes(%{"class" => class_name}), text: rendered_body(text)}
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
