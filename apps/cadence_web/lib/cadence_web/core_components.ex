defmodule CadenceWeb.CoreComponents do
  @moduledoc false

  use Phoenix.Component

  alias Phoenix.HTML.FormField

  attr :field, FormField, required: true
  attr :type, :string, default: "text"
  attr :label, :string, default: nil
  attr :placeholder, :string, default: nil
  attr :required, :boolean, default: false
  attr :class, :string, default: nil
  attr :rest, :global, include: ~w(autocomplete autofocus disabled maxlength minlength pattern)

  def input(assigns) do
    value =
      case assigns.type do
        "password" -> nil
        _other -> assigns.field.value
      end

    assigns = assign(assigns, :value, value)

    ~H"""
    <div class="field">
      <label :if={@label} class="field__label" for={@field.id}>
        {@label}
      </label>
      <input
        id={@field.id}
        name={@field.name}
        type={@type}
        value={@value}
        placeholder={@placeholder}
        required={@required}
        class={["field__input", @class]}
        {@rest}
      />
    </div>
    """
  end
end
