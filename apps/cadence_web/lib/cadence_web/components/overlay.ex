defmodule CadenceWeb.Components.Overlay do
  @moduledoc """
  Canonical Cadence overlay primitives.

  Feature code supplies content and intent; these components own overlay
  semantics, accessibility, layering, dismissal, and LiveView integration.
  """

  use Phoenix.Component

  attr :id, :string, required: true
  attr :label, :string, default: "Actions"
  attr :class, :string, default: nil
  attr :trigger_class, :string, default: nil
  slot :trigger
  slot :item, required: true

  def menu(assigns) do
    ~H"""
    <div
      id={@id}
      phx-hook="Overlay"
      data-overlay-kind="menu"
      data-overlay-placement="bottom-end"
      class={["cadence-overlay", @class]}
    >
      <button
        id={"#{@id}-trigger"}
        type="button"
        data-overlay-trigger
        aria-haspopup="menu"
        aria-expanded="false"
        aria-controls={"#{@id}-menu"}
        aria-label={@label}
        class={["cadence-overlay-trigger", @trigger_class]}
      >
        <%= if @trigger == [] do %>
          <span class="hero-ellipsis-vertical h-5 w-5"></span>
        <% else %>
          {render_slot(@trigger)}
        <% end %>
      </button>
      <div
        id={"#{@id}-menu"}
        role="menu"
        data-overlay-panel
        class="cadence-overlay-panel cadence-menu-panel"
        hidden
      >
        <div :for={item <- @item} role="none" class="cadence-menu-item">
          {render_slot(item)}
        </div>
      </div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :trigger_id, :string, default: nil
  attr :panel_id, :string, default: nil
  attr :placement, :atom, values: [:bottom_start, :bottom_end], default: :bottom_end
  attr :width, :atom, values: [:sm, :md, :lg, :viewport], default: :md
  attr :class, :string, default: nil
  attr :trigger_class, :string, default: nil
  attr :panel_class, :string, default: nil
  attr :rest, :global
  slot :trigger, required: true
  slot :inner_block, required: true

  def popover(assigns) do
    ~H"""
    <div
      id={@id}
      phx-hook="Overlay"
      data-overlay-kind="popover"
      data-overlay-placement={placement_value(@placement)}
      class={["cadence-overlay", @class]}
      {@rest}
    >
      <button
        id={@trigger_id || "#{@id}-trigger"}
        type="button"
        data-overlay-trigger
        aria-haspopup="dialog"
        aria-expanded="false"
        aria-controls={@panel_id || "#{@id}-panel"}
        aria-label={@label}
        class={["cadence-overlay-trigger", @trigger_class]}
      >
        {render_slot(@trigger)}
      </button>
      <section
        id={@panel_id || "#{@id}-panel"}
        data-overlay-panel
        data-overlay-width={@width}
        aria-label={@label}
        class={["cadence-overlay-panel cadence-popover-panel", @panel_class]}
        hidden
      >
        {render_slot(@inner_block)}
      </section>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :open, :boolean, default: false
  attr :class, :string, default: nil
  slot :summary, required: true
  slot :inner_block, required: true

  def disclosure(assigns) do
    ~H"""
    <details id={@id} open={@open} data-persist-disclosure class={@class}>
      <summary>{render_slot(@summary)}</summary>
      {render_slot(@inner_block)}
    </details>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :width, :atom, values: [:sm, :md, :lg], default: :md
  attr :modal, :boolean, default: false
  attr :class, :string, default: nil
  attr :close_event, :string, default: "close_panel"
  attr :close_label, :string, default: "Close panel"
  slot :inner_block, required: true

  def sheet(assigns) do
    ~H"""
    <div id={"#{@id}-layer"} class="cadence-sheet-layer">
      <button
        :if={@modal}
        type="button"
        class="cadence-sheet-scrim"
        phx-click={@close_event}
        aria-label={@close_label}
      >
      </button>
      <section
        id={@id}
        role="dialog"
        aria-modal={to_string(@modal)}
        aria-label={@title}
        data-sheet-width={@width}
        class={["cadence-sheet", @class]}
        phx-window-keydown={@close_event}
        phx-key="Escape"
      >
        <header class="cadence-sheet-header">
          <h2 class="hud-label">{@title}</h2>
          <button
            type="button"
            class="cadence-icon-button"
            phx-click={@close_event}
            aria-label={@close_label}
          >
            <span class="hero-x-mark h-4 w-4"></span>
          </button>
        </header>
        <div class="cadence-sheet-body">{render_slot(@inner_block)}</div>
      </section>
    </div>
    """
  end

  defp placement_value(:bottom_start), do: "bottom-start"
  defp placement_value(:bottom_end), do: "bottom-end"
end
