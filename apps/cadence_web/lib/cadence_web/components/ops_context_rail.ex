defmodule CadenceWeb.Components.OpsContextRail do
  @moduledoc """
  Right-side context rail for the ops console pages, mirroring the legacy
  context panel: expanded it stacks context sections; collapsed it shows a
  narrow badge strip (status dot + count per section) that expands on click.

  Expanded/collapsed state lives in a `data-expanded` attribute managed by the
  shared `NavRail` hook (localStorage persistence, re-applied after LiveView
  patches). Composed entirely from Tailwind utilities, daisyUI classes, and
  existing HUD classes — no new CSS selectors.
  """

  use Phoenix.Component

  import CadenceWeb.Components.Badges, only: [severity_badge: 1]
  import CadenceWeb.CoreComponents, only: [icon: 1]

  attr :id, :string, default: "ops-context-rail"

  slot :section do
    attr :key, :string, doc: "stable section key for tests and browser smoke assertions"
    attr :title, :string, required: true
    attr :icon, :string, required: true
    attr :status, :atom, doc: "badge dot: :critical | :warning | :info | :nominal"
    attr :count, :integer, doc: "count shown under the collapsed badge; hidden when nil"
    attr :visible, :boolean, doc: "skip the section entirely when false"
  end

  def ops_context_rail(assigns) do
    assigns = assign(assigns, :sections, Enum.filter(assigns.section, &section_visible?/1))

    ~H"""
    <aside
      id={@id}
      phx-hook="NavRail"
      aria-label="Operational context"
      data-ops-context-rail
      data-storage-key="cadence-ops-context-rail"
      data-rail-role="context"
      class="group/ctx relative w-12 data-[expanded]:w-72 shrink-0 flex flex-col border-l border-primary/20 bg-base-200 hud-grid overflow-hidden transition-[width] duration-150"
    >
      <div
        data-rail-resize
        title="Drag to resize"
        class="absolute inset-y-0 left-0 z-10 w-1.5 cursor-col-resize touch-none hover:bg-primary/40 active:bg-primary/60 hidden group-data-[expanded]/ctx:block"
      >
      </div>
      <button
        id={"#{@id}-toggle"}
        type="button"
        data-rail-toggle
        data-ops-context-rail-toggle
        aria-label="Toggle context panel"
        class="h-9 shrink-0 flex items-center justify-center text-base-content/60 hover:text-base-content"
      >
        <.icon
          name="hero-chevron-double-right"
          class="h-4 w-4 pointer-events-none hidden group-data-[expanded]/ctx:inline"
        />
        <.icon
          name="hero-chevron-double-left"
          class="h-4 w-4 pointer-events-none group-data-[expanded]/ctx:hidden"
        />
      </button>

      <div class="flex flex-col items-stretch gap-1 pt-1 overflow-y-auto group-data-[expanded]/ctx:hidden">
        <button
          :for={section <- @sections}
          type="button"
          data-rail-toggle
          data-ops-context-collapsed-section={section_key(section)}
          data-ops-context-section-status={section[:status]}
          data-ops-context-section-count={section_count(section)}
          title={section.title}
          class="flex flex-col items-center gap-1 py-2 text-base-content/60 hover:text-base-content hover:bg-base-300/40"
        >
          <.icon name={section.icon} class="h-4 w-4 pointer-events-none" />
          <span class={[
            "h-1.5 w-1.5 rounded-full pointer-events-none",
            status_dot_class(section[:status])
          ]}>
          </span>
          <span
            :if={section[:count]}
            class="font-mono text-[0.625rem] leading-none pointer-events-none"
          >
            {section[:count]}
          </span>
        </button>
      </div>

      <div class="hidden group-data-[expanded]/ctx:flex flex-col min-h-0 flex-1 overflow-y-auto">
        <section
          :for={section <- @sections}
          data-ops-context-section={section_key(section)}
          data-ops-context-section-status={section[:status]}
          data-ops-context-section-count={section_count(section)}
          class="border-b border-base-300/60"
        >
          <header class="flex items-center gap-2 px-2 pt-2">
            <.icon name={section.icon} class="h-3.5 w-3.5 text-base-content/60" />
            <span class="hud-label">{section.title}</span>
            <span class={[
              "ml-auto h-2 w-2 rounded-full",
              status_dot_class(section[:status])
            ]}>
            </span>
          </header>
          {render_slot(section)}
        </section>
      </div>
    </aside>
    """
  end

  @doc """
  The baseline rail for ops pages without page-specific context: a single
  fleet-health section fed by the `OpsShellHook` assigns.
  """
  attr :fleet_health, :any, required: true

  def mission_context_rail(assigns) do
    ~H"""
    <.ops_context_rail>
      <:section
        key="fleet_health"
        title="Fleet health"
        icon="hero-rocket-launch"
        status={fleet_health_status(@fleet_health)}
        count={fleet_health_violations(@fleet_health)}
      >
        <.fleet_health_section fleet_health={@fleet_health} />
      </:section>
    </.ops_context_rail>
    """
  end

  attr :fleet_health, :any, required: true

  def fleet_health_section(assigns) do
    ~H"""
    <div :if={@fleet_health} class="flex flex-wrap items-center gap-2 px-2 py-2 text-xs">
      <.severity_badge
        severity={:critical}
        count={@fleet_health.normalized_state_counts.red}
        label="Red"
      />
      <.severity_badge
        severity={:warning}
        count={@fleet_health.normalized_state_counts.yellow}
        label="Yellow"
      />
      <.severity_badge severity={:info} count={@fleet_health.normalized_state_counts.blue} label="Blue" />
      <.severity_badge
        severity={:nominal}
        count={@fleet_health.normalized_state_counts.green}
        label="Green"
      />
      <span class="font-mono text-xs text-base-content/60 basis-full">
        {@fleet_health.violating_points} violating points
      </span>
    </div>
    <p :if={is_nil(@fleet_health)} class="px-2 py-2 text-xs text-base-content/60">
      Fleet health unavailable.
    </p>
    """
  end

  @doc """
  Fleet-health status for the collapsed badge dot.
  """
  def fleet_health_status(%{normalized_state_counts: %{red: red}}) when red > 0, do: :critical

  def fleet_health_status(%{normalized_state_counts: %{yellow: yellow}}) when yellow > 0,
    do: :warning

  def fleet_health_status(%{normalized_state_counts: _counts}), do: :nominal
  def fleet_health_status(_fleet_health), do: nil

  def fleet_health_violations(%{violating_points: count}) when is_integer(count) and count > 0,
    do: count

  def fleet_health_violations(_fleet_health), do: nil

  defp section_visible?(section), do: Map.get(section, :visible, true)

  defp section_key(section), do: Map.get(section, :key) || section.title

  defp section_count(section) do
    case Map.get(section, :count) do
      count when is_integer(count) -> Integer.to_string(count)
      _count -> nil
    end
  end

  defp status_dot_class(:critical), do: "bg-error"
  defp status_dot_class(:warning), do: "bg-warning"
  defp status_dot_class(:info), do: "bg-info"
  defp status_dot_class(:nominal), do: "bg-success"
  defp status_dot_class(_status), do: "bg-base-content/30"
end
