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
  attr :class, :string, default: nil
  attr :rest, :global, include: ~w(autocomplete autofocus disabled maxlength minlength pattern)

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
              :for={{label, option_value} <- @options}
              value={option_value}
              selected={to_string(@value) == to_string(option_value)}
            >
              {label}
            </option>
          </select>
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
      </label>
      <p :for={{msg, _opts} <- @errors} class="mt-1.5 text-sm text-error">
        {msg}
      </p>
    </div>
    """
  end
end
