defmodule CadenceWeb.Components.OpsApplicationDock do
  @moduledoc "Host-owned bottom dock chrome for installed application surface contributions."

  use CadenceWeb, :html

  alias Cadence.Applications.OpsDockSurface

  attr :surfaces, :list, required: true

  def ops_application_dock(assigns) do
    ~H"""
    <details
      id="ops-application-dock"
      open
      class="group shrink-0 border-t border-primary/25 bg-base-200/80"
    >
      <summary class="flex h-8 cursor-pointer list-none items-center border-b border-base-300/70 px-3 marker:hidden">
        <span class="hud-label mr-4">Operations dock</span>
        <nav aria-label="Application dock surfaces" class="flex min-w-0 flex-1 items-stretch gap-1 self-stretch">
          <button
            :for={{surface, index} <- Enum.with_index(@surfaces)}
            id={"ops-dock-tab-#{dom_id(surface)}"}
            type="button"
            role="tab"
            aria-selected={to_string(index == 0)}
            data-application-key={surface.application_key}
            data-surface-id={surface.surface_definition.surface_id}
            class={[
              "relative px-3 font-mono text-[0.68rem] font-semibold uppercase tracking-[0.1em]",
              index == 0 && "text-primary after:absolute after:inset-x-2 after:bottom-0 after:h-px after:bg-primary",
              index != 0 && "text-base-content/50"
            ]}
          >
            {surface.label}
          </button>
        </nav>
        <.icon
          name="hero-chevron-down"
          class="size-4 text-base-content/45 transition-transform group-open:rotate-180"
        />
      </summary>

      <div
        id="ops-dock-surface-host"
        role="tabpanel"
        class="h-40 overflow-hidden bg-base-100"
      >
        <div class="flex h-full items-center justify-center text-sm text-base-content/45">
          The application surface is registered with the Ops host.
        </div>
      </div>
    </details>
    """
  end

  defp dom_id(%OpsDockSurface{id: id}) do
    String.replace(id, ~r/[^a-zA-Z0-9_-]/, "-")
  end
end
