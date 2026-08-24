defmodule CadenceWeb.Components.Card do
  @moduledoc """
  The canonical Cadence card.

  Card chrome is `card bg-base-200 border border-base-300`. Body padding
  defaults to `p-6`; use `padding={:none}` for flush content (tables, lists
  with their own row padding).

  Two heading styles, grounded in existing pages:

    * `title` — an uppercase `hud-label` rendered inside the padded body
      (show-page detail cards).
    * `heading` (+ optional `subtitle` and `:actions`) — a full-bleed header
      bar above the body (list-page cards with a "New X" action).

  The cyan `hud-corners` brackets are a navigation/hero signal, not default
  chrome: `hover_glow` (navigation cards) applies them automatically, and
  `corners` opts a non-navigating hero panel in. Content cards stay bare.
  Status on a card is carried by the `<.status_badge>` inside it — there is
  deliberately no status-colored border. One-off layouts that would need more
  than a couple of `class` escape hatches should stay as raw markup instead.
  """

  use Phoenix.Component

  attr :id, :string, default: nil
  attr :title, :string, default: nil
  attr :heading, :string, default: nil
  attr :subtitle, :string, default: nil
  attr :padding, :atom, values: [:default, :none], default: :default
  attr :hover_glow, :boolean, default: false
  attr :corners, :boolean, default: false
  attr :class, :string, default: nil
  slot :actions
  slot :inner_block, required: true

  def card(assigns) do
    ~H"""
    <section
      id={@id}
      class={[
        "card bg-base-200 border border-base-300",
        (@hover_glow || @corners) && "hud-corners",
        @hover_glow &&
          "hover-glow-cyan transition-glow hover:bg-[linear-gradient(var(--state-hover),var(--state-hover))]",
        @class
      ]}
    >
      <div
        :if={@heading}
        class="flex items-start justify-between gap-4 border-b border-base-300 px-4 py-3"
      >
        <div>
          <h2 class="text-base font-semibold text-base-content">{@heading}</h2>
          <p :if={@subtitle} class="mt-1 text-xs text-base-content/70">{@subtitle}</p>
        </div>
        <div :if={@actions != []} class="flex items-center gap-2">
          {render_slot(@actions)}
        </div>
      </div>
      <div class={["card-body", padding_class(@padding)]}>
        <p :if={@title} class="hud-label">{@title}</p>
        {render_slot(@inner_block)}
      </div>
    </section>
    """
  end

  defp padding_class(:default), do: "p-6"
  defp padding_class(:none), do: "p-0"
end
