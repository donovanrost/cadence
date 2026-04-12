defmodule CadenceWeb.CoreComponents do
  @moduledoc false

  use Phoenix.Component

  alias Phoenix.HTML.FormField

  attr :field, FormField, required: true
  attr :type, :string, default: "text"
  attr :label, :string, default: nil
  attr :placeholder, :string, default: nil
  attr :options, :list, default: []
  attr :required, :boolean, default: false
  attr :class, :string, default: nil
  attr :rest, :global, include: ~w(autocomplete autofocus disabled maxlength minlength pattern)

  def input(assigns) do
    value =
      case assigns.type do
        "password" -> nil
        _other -> assigns.field.value
      end

    errors =
      if Phoenix.Component.used_input?(assigns.field),
        do: assigns.field.errors,
        else: []

    assigns = assigns |> assign(:value, value) |> assign(:errors, errors)

    ~H"""
    <div class="fieldset mb-3">
      <label>
        <span :if={@label} class="hud-label block mb-1.5">{@label}</span>
        <%= if @type == "select" do %>
          <select
            id={@field.id}
            name={@field.name}
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
            id={@field.id}
            name={@field.name}
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
