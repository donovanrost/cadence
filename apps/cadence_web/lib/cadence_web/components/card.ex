defmodule CadenceWeb.Components.Card do
  @moduledoc """
  The canonical Cadence card and stat tile.

  Card chrome is always `card bg-base-200 border border-base-300 hud-corners`.
  Body padding defaults to `p-6`; use `padding={:none}` for flush content
  (tables, lists with their own row padding).

  Two heading styles, grounded in existing pages:

    * `title` — an uppercase `hud-label` rendered inside the padded body
      (show-page detail cards).
    * `heading` (+ optional `subtitle` and `:actions`) — a full-bleed header
      bar above the body (list-page cards with a "New X" action).

  Use `accent` for a status-colored left border and `hover_glow` for
  navigation cards. One-off layouts that would need more than a couple of
  `class` escape hatches should stay as raw markup instead.
  """

  use Phoenix.Component

  attr :id, :string, default: nil
  attr :title, :string, default: nil
  attr :heading, :string, default: nil
  attr :subtitle, :string, default: nil
  attr :accent, :atom, values: [nil, :success, :warning, :error, :info], default: nil
  attr :padding, :atom, values: [:default, :none], default: :default
  attr :hover_glow, :boolean, default: false
  attr :class, :string, default: nil
  slot :actions
  slot :inner_block, required: true

  def card(assigns) do
    ~H"""
    <section
      id={@id}
      class={[
        "card bg-base-200 border border-base-300 hud-corners",
        accent_class(@accent),
        @hover_glow && "hover-glow-cyan transition-glow",
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

  defp accent_class(nil), do: nil
  defp accent_class(:success), do: "border-l-2 border-l-success/60"
  defp accent_class(:warning), do: "border-l-2 border-l-warning/60"
  defp accent_class(:error), do: "border-l-2 border-l-error/60"
  defp accent_class(:info), do: "border-l-2 border-l-info/60"

  defp padding_class(:default), do: "p-6"
  defp padding_class(:none), do: "p-0"

  @doc """
  Renders a compact metric tile — an uppercase label over a monospace value.
  Lay several out in a `grid gap-3 md:grid-cols-4` container.

  With `patch`, the tile becomes a filter link; pair with `active` to mark
  the currently-applied filter.
  """
  attr :id, :string, default: nil
  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :patch, :string, default: nil
  attr :active, :boolean, default: false
  attr :class, :string, default: nil

  def stat_tile(assigns) do
    ~H"""
    <%= if @patch do %>
      <.link
        id={@id}
        patch={@patch}
        aria-current={@active && "true"}
        class={[
          "block border bg-base-200 px-3 py-2 hud-corners transition-colors",
          if(@active, do: "border-primary/60", else: "border-base-300 hover:border-primary/40"),
          @class
        ]}
      >
        <.stat_tile_body label={@label} value={@value} active={@active} />
      </.link>
    <% else %>
      <div id={@id} class={["border border-base-300 bg-base-200 px-3 py-2 hud-corners", @class]}>
        <.stat_tile_body label={@label} value={@value} active={false} />
      </div>
    <% end %>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :active, :boolean, required: true

  defp stat_tile_body(assigns) do
    ~H"""
    <%!-- hud-label's color is in the same CSS layer but later in source order,
          so the active tint needs Tailwind's important modifier to win. --%>
    <p class={["hud-label", @active && "text-primary!"]}>{@label}</p>
    <p class="mt-1 font-mono text-xl text-base-content">{@value}</p>
    """
  end
end
