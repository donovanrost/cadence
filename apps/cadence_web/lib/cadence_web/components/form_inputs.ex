defmodule CadenceWeb.Components.FormInputs do
  @moduledoc """
  The canonical form field. Use `<.input>` for every form input — it handles
  the `hud-label`, daisyUI styling, and error display.

  Bind it to a `Phoenix.HTML.FormField` (`field={@form[:name]}`) inside
  `<.form>`. For standalone controls outside a form binding (filter boxes,
  `phx-change` selectors), pass `name`/`value` directly instead — errors are
  skipped in that mode.
  """

  use Phoenix.Component

  alias Phoenix.HTML.FormField

  attr :field, FormField, default: nil
  attr :id, :string, default: nil
  attr :name, :string, default: nil
  attr :value, :any, default: nil
  attr :type, :string, default: "text"
  attr :label, :string, default: nil
  attr :placeholder, :string, default: nil
  attr :options, :list, default: []
  attr :required, :boolean, default: false
  attr :errors, :list, default: []
  attr :compact, :boolean, default: false, doc: "drops the wrapper margin for toolbar use"
  attr :description, :string, default: nil, doc: "helper text under a checkbox label"
  attr :class, :string, default: nil

  attr :rest, :global,
    include: ~w(autocomplete autofocus disabled max maxlength min minlength pattern step)

  def input(%{field: %FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(:field, nil)
    |> assign(:errors, errors)
    |> assign(:id, assigns.id || field.id)
    |> assign(:name, assigns.name || field.name)
    |> assign(:value, if(is_nil(assigns.value), do: field.value, else: assigns.value))
    |> input()
  end

  def input(assigns) do
    assigns =
      update(assigns, :value, fn value, %{type: type} ->
        if type == "password", do: nil, else: value
      end)

    ~H"""
    <%= if @type == "checkbox" do %>
      <div class={["fieldset", !@compact && "mb-3"]}>
        <label class="flex cursor-pointer items-start gap-3">
          <input type="hidden" name={@name} value="false" />
          <input
            type="checkbox"
            id={@id}
            name={@name}
            value="true"
            checked={to_string(@value) == "true"}
            class={["checkbox checkbox-sm mt-0.5", @class]}
            {@rest}
          />
          <span>
            <span :if={@label} class="block text-sm font-medium">{@label}</span>
            <span :if={@description} class="mt-0.5 block text-xs text-base-content/70">
              {@description}
            </span>
          </span>
        </label>
      </div>
    <% else %>
    <div class={["fieldset", !@compact && "mb-3"]}>
      <label>
        <span :if={@label} class="hud-label block mb-1.5">{@label}</span>
        <%= if @type == "select" do %>
          <select
            id={@id}
            name={@name}
            required={@required}
            class={["w-full select", @errors != [] && "select-error", @class]}
            {@rest}
          >
            <option :if={@placeholder} value="">{@placeholder}</option>
            <option
              :for={option <- @options}
              value={option_value(option)}
              selected={to_string(@value) == to_string(option_value(option))}
              disabled={option_disabled?(option)}
              title={option_title(option)}
            >
              {option_label(option)}
            </option>
          </select>
        <% else %>
          <%= if @type == "textarea" do %>
            <textarea
              id={@id}
              name={@name}
              placeholder={@placeholder}
              required={@required}
              class={["w-full textarea", @errors != [] && "textarea-error", @class]}
              {@rest}
            >{Phoenix.HTML.Form.normalize_value("textarea", @value)}</textarea>
          <% else %>
            <input
              id={@id}
              name={@name}
              type={@type}
              value={@value}
              placeholder={@placeholder}
              required={@required}
              class={["w-full input", @errors != [] && "input-error", @class]}
              {@rest}
            />
          <% end %>
        <% end %>
      </label>
      <p :for={{msg, _opts} <- @errors} class="mt-1.5 text-sm text-error">
        {msg}
      </p>
    </div>
    <% end %>
    """
  end

  defp option_label({label, _value}), do: label
  defp option_label({label, _value, _attrs}), do: label
  defp option_label(%{label: label}), do: label

  defp option_value({_label, value}), do: value
  defp option_value({_label, value, _attrs}), do: value
  defp option_value(%{value: value}), do: value

  defp option_disabled?({_label, _value}), do: false

  defp option_disabled?({_label, _value, attrs}) when is_list(attrs) do
    Keyword.get(attrs, :disabled, false)
  end

  defp option_disabled?(%{} = option), do: Map.get(option, :disabled, false)

  defp option_title({_label, _value}), do: nil

  defp option_title({_label, _value, attrs}) when is_list(attrs) do
    Keyword.get(attrs, :title)
  end

  defp option_title(%{} = option), do: Map.get(option, :title)
end
