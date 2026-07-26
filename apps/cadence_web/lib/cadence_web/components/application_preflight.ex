defmodule CadenceWeb.Components.ApplicationPreflight do
  @moduledoc "Host-owned renderer for typed application activation checks."

  use Phoenix.Component

  import CadenceWeb.Components.Badges, only: [status_badge: 1]
  import CadenceWeb.CoreComponents, only: [icon: 1]

  alias Cadence.Applications.PreflightReport

  attr :report, PreflightReport, required: true

  def application_preflight(assigns) do
    ~H"""
    <section
      id="application-activation-preflight"
      data-preflight-state={Atom.to_string(@report.state)}
      data-activation-ready={to_string(PreflightReport.ready?(@report))}
      class="overflow-hidden border border-base-300/80 bg-base-200/30"
    >
      <header class="grid gap-4 border-b border-base-300/70 px-4 py-4 sm:grid-cols-[auto_minmax(0,1fr)_auto] sm:items-center">
        <div class={[
          "grid size-10 place-items-center border",
          preflight_icon_class(@report.state)
        ]}>
          <.icon name={preflight_icon(@report.state)} class="size-5" />
        </div>
        <div>
          <div class="flex flex-wrap items-center gap-x-3 gap-y-1">
            <h2 class="text-sm font-semibold uppercase tracking-[0.14em]">Activation preflight</h2>
            <span class="font-mono text-[0.65rem] uppercase tracking-[0.16em] text-base-content/45">
              {length(@report.checks)} checks · v{@report.application_version}
            </span>
          </div>
          <p class="mt-1 text-sm text-base-content/65">{@report.summary}</p>
        </div>
        <.status_badge
          status={@report.state}
          label={preflight_label(@report.state)}
          data-preflight-summary-status
        />
      </header>

      <div id="application-preflight-checks" class="divide-y divide-base-300/60">
        <article
          :for={check <- @report.checks}
          id={"application-preflight-check-#{check.id}"}
          data-check-category={Atom.to_string(check.category)}
          data-check-state={Atom.to_string(check.state)}
          class="group grid grid-cols-[0.25rem_minmax(0,1fr)_auto] gap-4 px-4 py-3"
        >
          <span class={["rounded-full", check_rail_class(check.state)]}></span>
          <div class="min-w-0">
            <div class="flex flex-wrap items-center gap-2">
              <span class="font-mono text-[0.62rem] uppercase tracking-[0.16em] text-base-content/45">
                {check.category}
              </span>
              <h3 class="text-sm font-medium text-base-content">{check.title}</h3>
            </div>
            <p class="mt-1 text-xs leading-5 text-base-content/60">{check.detail}</p>
          </div>
          <div class="flex items-center gap-3 self-center">
            <span :if={check.value} class="font-mono text-xs text-base-content/65">
              {check.value}
            </span>
            <.icon
              name={check_icon(check.state)}
              class={"size-4 #{check_icon_class(check.state)}"}
            />
          </div>
        </article>
      </div>
    </section>
    """
  end

  defp preflight_icon(:ready), do: "hero-shield-check"
  defp preflight_icon(:attention), do: "hero-exclamation-circle"
  defp preflight_icon(:blocked), do: "hero-shield-exclamation"

  defp preflight_icon_class(:ready), do: "border-success/35 bg-success/10 text-success"
  defp preflight_icon_class(:attention), do: "border-warning/35 bg-warning/10 text-warning"
  defp preflight_icon_class(:blocked), do: "border-error/35 bg-error/10 text-error"

  defp preflight_label(:ready), do: "Ready"
  defp preflight_label(:attention), do: "Advisory"
  defp preflight_label(:blocked), do: "Blocked"

  defp check_rail_class(:ready), do: "bg-success"
  defp check_rail_class(:attention), do: "bg-warning"
  defp check_rail_class(:blocked), do: "bg-error"

  defp check_icon(:ready), do: "hero-check-circle"
  defp check_icon(:attention), do: "hero-exclamation-circle"
  defp check_icon(:blocked), do: "hero-x-circle"

  defp check_icon_class(:ready), do: "text-success"
  defp check_icon_class(:attention), do: "text-warning"
  defp check_icon_class(:blocked), do: "text-error"
end
