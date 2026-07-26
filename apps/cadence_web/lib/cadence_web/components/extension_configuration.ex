defmodule CadenceWeb.Components.ExtensionConfiguration do
  @moduledoc "Host-owned renderer for bounded typed extension configuration sections."

  use Phoenix.Component

  import CadenceWeb.Components.FormInputs, only: [input: 1]
  import CadenceWeb.Components.Forms, only: [form_section: 1]

  alias Cadence.Extensions.Presentation.{ConfigurationDefinition, FieldDefinition}
  alias Phoenix.HTML.Form

  attr :definition, ConfigurationDefinition, required: true
  attr :form, Form, required: true
  attr :kind, :string, required: true

  def extension_configuration(assigns) do
    ~H"""
    <div
      id={@definition.id}
      data-extension-presentation={@kind}
      class="space-y-8"
    >
      <p :if={@definition.description} class="text-sm text-base-content/65">
        {@definition.description}
      </p>

      <.form_section
        :for={section <- @definition.sections}
        id={section.id}
        number={section.number}
        title={section.title}
      >
        <p :if={section.description} class="text-sm text-base-content/65">
          {section.description}
        </p>
        <div id={"#{section.id}-fields"} class="grid gap-x-4 sm:grid-cols-2">
          <div
            :for={field <- section.fields}
            :if={visible?(field.visible_when, @form)}
            id={field_wrapper_id(@definition.id, field.field)}
          >
            <.input
              id={field_input_id(@definition.id, field.field)}
              field={@form[field.field]}
              type={input_type(field)}
              label={field.label}
              placeholder={field.placeholder}
              required={field.required}
              options={field.options}
              step={field.step}
              min={field.min}
              max={field.max}
            />
            <p :if={field.help} class="-mt-1 mb-3 text-xs text-base-content/55">
              {field.help}
            </p>
          </div>
        </div>
      </.form_section>
    </div>
    """
  end

  defp visible?(nil, _form), do: true

  defp visible?(%{field: controlling_field, equals: expected}, form) do
    to_string(Form.input_value(form, controlling_field)) == to_string(expected)
  end

  defp field_wrapper_id(definition_id, field),
    do: "#{definition_id}-field-#{dom_field(field)}"

  defp field_input_id(definition_id, field),
    do: "#{definition_id}-input-#{dom_field(field)}"

  defp dom_field(field), do: field |> Atom.to_string() |> String.replace("_", "-")

  defp input_type(%FieldDefinition{type: :reference}), do: "select"
  defp input_type(%FieldDefinition{type: type}), do: Atom.to_string(type)
end
