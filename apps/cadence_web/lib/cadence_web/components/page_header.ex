defmodule CadenceWeb.Components.PageHeader do
  @moduledoc """
  The canonical page header: title block over the standard
  `border-b border-primary/20 pb-4` rule.

  Navigation context goes above the title — either a `back_label`/
  `back_navigate` pair (the "← Section" link family) or a `breadcrumbs`
  list (delegated to `CadenceWeb.UI.breadcrumbs/1`), or a plain `eyebrow`
  label. Right-side buttons and status pills go in the `:actions` slot;
  inline counts next to the title go in `:title_suffix`.
  """

  use Phoenix.Component

  import CadenceWeb.UI, only: [breadcrumbs: 1]

  attr :title, :string, required: true
  attr :subtitle, :string, default: nil
  attr :eyebrow, :string, default: nil
  attr :back_label, :string, default: nil
  attr :back_navigate, :string, default: nil
  attr :breadcrumbs, :list, default: nil
  attr :class, :string, default: nil
  slot :title_suffix
  slot :actions

  def page_header(assigns) do
    ~H"""
    <header class={["border-b border-primary/20 pb-4", @class]}>
      <div class={@actions != [] && "flex items-end justify-between gap-4"}>
        <div>
          <.breadcrumbs :if={@breadcrumbs} items={@breadcrumbs} />
          <.link
            :if={@back_navigate}
            navigate={@back_navigate}
            class="hud-label hover:text-primary"
          >
            &larr; {@back_label}
          </.link>
          <p :if={@eyebrow} class="hud-label">{@eyebrow}</p>
          <h1 class="mt-2 text-2xl font-bold text-base-content tracking-tight">
            {@title}
            <span :if={@title_suffix != []} class="ml-3 font-mono text-base text-base-content/60">
              {render_slot(@title_suffix)}
            </span>
          </h1>
          <p :if={@subtitle} class="mt-1 max-w-3xl text-sm text-base-content/70">{@subtitle}</p>
        </div>
        <div :if={@actions != []} class="flex items-center gap-2">
          {render_slot(@actions)}
        </div>
      </div>
    </header>
    """
  end
end
