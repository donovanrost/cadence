defmodule CadenceWeb.Components.Button do
  @moduledoc """
  The canonical Cadence button.

  Renders a `<button>` — or a `<.link>` styled as one when `navigate`,
  `patch`, or `href` is set. Conventions baked in:

    * Buttons never glow. Glow (`hover-glow-*`) is reserved for navigation
      cards and future live/alert signals.
    * `:sm` is the default size. Reserve `:md` for form-submit and page-level
      CTAs, `:xs` for inline table controls.
    * `:danger` is the outline error treatment for destructive actions.
  """

  use Phoenix.Component

  attr :variant, :atom, values: [:primary, :ghost, :secondary, :danger], default: :primary
  attr :size, :atom, values: [:xs, :sm, :md], default: :sm
  attr :type, :string, default: "button"
  attr :navigate, :string, default: nil
  attr :patch, :string, default: nil
  attr :href, :string, default: nil
  attr :class, :string, default: nil
  attr :rest, :global, include: ~w(disabled form name value data-confirm)
  slot :inner_block, required: true

  def button(assigns) do
    assigns = assign(assigns, :btn_class, btn_class(assigns))

    ~H"""
    <%= if @navigate || @patch || @href do %>
      <.link navigate={@navigate} patch={@patch} href={@href} class={@btn_class} {@rest}>
        {render_slot(@inner_block)}
      </.link>
    <% else %>
      <button type={@type} class={@btn_class} {@rest}>
        {render_slot(@inner_block)}
      </button>
    <% end %>
    """
  end

  defp btn_class(assigns) do
    ["btn", variant_class(assigns.variant), size_class(assigns.size), assigns.class]
  end

  defp variant_class(:primary), do: "btn-primary"
  defp variant_class(:ghost), do: "btn-ghost"
  defp variant_class(:secondary), do: "btn-secondary"
  defp variant_class(:danger), do: "btn-error btn-outline"

  defp size_class(:xs), do: "btn-xs"
  defp size_class(:sm), do: "btn-sm"
  defp size_class(:md), do: nil
end
