# Test-only compatibility renderer preserving the pre-LiveVue component contract.
defmodule CadenceWeb.Components.PageHeader do
  @moduledoc false

  use Phoenix.Component

  attr :title, :string, required: true
  attr :subtitle, :string, default: nil
  attr :eyebrow, :string, default: nil
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

  attr :items, :list, required: true

  defp breadcrumbs(assigns) do
    assigns = assign(assigns, :last_index, length(assigns.items) - 1)

    ~H"""
    <nav
      aria-label="Breadcrumb"
      class="flex flex-wrap items-center gap-2 text-[0.7rem] font-semibold uppercase tracking-[0.12em] text-base-content/60"
    >
      <%= for {{label, path}, index} <- Enum.with_index(@items) do %>
        <span :if={index > 0} class="text-base-content/20" aria-hidden="true">/</span>
        <%= cond do %>
          <% index == @last_index -> %>
            <span class="text-primary/90">{label}</span>
          <% path -> %>
            <.link navigate={path} class="hover:text-primary transition-colors">{label}</.link>
          <% true -> %>
            <span>{label}</span>
        <% end %>
      <% end %>
    </nav>
    """
  end
end
