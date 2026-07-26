defmodule CadenceWeb.Components.ApplicationDiagnostics do
  @moduledoc "Host-owned renderer for bounded application diagnostics."

  use Phoenix.Component

  import CadenceWeb.Components.Badges, only: [status_badge: 1]
  import CadenceWeb.CoreComponents, only: [icon: 1]

  alias Cadence.Applications.SurfaceElements.Diagnostics

  attr :definition, Diagnostics, required: true

  def application_diagnostics(%{definition: %Diagnostics{items: []}} = assigns), do: ~H""

  def application_diagnostics(assigns) do
    assigns = assign(assigns, :severity, overall_severity(assigns.definition.items))

    ~H"""
    <section
      id={@definition.id}
      role={if(@severity == :error, do: "alert", else: "status")}
      aria-live="polite"
      data-diagnostic-severity={Atom.to_string(@severity)}
      data-diagnostic-count={length(@definition.items)}
      data-diagnostic-total={@definition.total_count}
      class="overflow-hidden border border-base-300/80 bg-base-200/30"
    >
      <header class="grid gap-4 border-b border-base-300/70 px-4 py-3 sm:grid-cols-[auto_minmax(0,1fr)_auto] sm:items-center">
        <div class={[
          "grid size-9 place-items-center border",
          header_icon_class(@severity)
        ]}>
          <.icon name={header_icon(@severity)} class="size-4" />
        </div>
        <div class="min-w-0">
          <div class="flex flex-wrap items-center gap-x-3 gap-y-1">
            <h2 class="text-sm font-semibold uppercase tracking-[0.14em]">
              {@definition.title}
            </h2>
            <span class="font-mono text-[0.65rem] uppercase tracking-[0.16em] text-base-content/45">
              {count_label(@definition)}
            </span>
          </div>
          <p :if={@definition.description} class="mt-1 text-sm text-base-content/65">
            {@definition.description}
          </p>
        </div>
        <.status_badge status={status_tone(@severity)} label={severity_label(@severity)} />
      </header>

      <div id={"#{@definition.id}-items"} class="divide-y divide-base-300/60">
        <article
          :for={item <- @definition.items}
          id={"#{@definition.id}-item-#{item.id}"}
          data-diagnostic-code={item.code}
          data-diagnostic-severity={Atom.to_string(item.severity)}
          class="group grid grid-cols-[0.25rem_minmax(0,1fr)_auto] gap-4 px-4 py-3"
        >
          <span class={["rounded-full", rail_class(item.severity)]}></span>
          <div class="min-w-0">
            <div class="flex flex-wrap items-center gap-2">
              <span class="font-mono text-[0.62rem] uppercase tracking-[0.13em] text-base-content/45">
                {item.code}
              </span>
              <h3 class="text-sm font-medium text-base-content">{item.title}</h3>
            </div>
            <p class="mt-1 text-xs leading-5 text-base-content/60">{item.detail}</p>
          </div>
          <div class="flex items-center gap-3 self-center">
            <span :if={item.value} class="max-w-56 truncate font-mono text-xs text-base-content/65">
              {item.value}
            </span>
            <.icon
              name={item_icon(item.severity)}
              class={item_icon_class(item.severity)}
            />
          </div>
        </article>
      </div>
    </section>
    """
  end

  defp overall_severity(items) do
    cond do
      Enum.any?(items, &(&1.severity == :error)) -> :error
      Enum.any?(items, &(&1.severity == :warning)) -> :warning
      true -> :info
    end
  end

  defp count_label(%Diagnostics{items: items, total_count: total_count}) do
    visible_count = length(items)

    if visible_count < total_count do
      "#{visible_count} shown · #{total_count} total"
    else
      "#{total_count} #{if(total_count == 1, do: "finding", else: "findings")}"
    end
  end

  defp status_tone(:error), do: :blocked
  defp status_tone(:warning), do: :attention
  defp status_tone(:info), do: :info

  defp severity_label(:error), do: "Blocked"
  defp severity_label(:warning), do: "Advisory"
  defp severity_label(:info), do: "Notice"

  defp header_icon(:error), do: "hero-exclamation-triangle"
  defp header_icon(:warning), do: "hero-exclamation-circle"
  defp header_icon(:info), do: "hero-information-circle"

  defp header_icon_class(:error), do: "border-error/35 bg-error/10 text-error"
  defp header_icon_class(:warning), do: "border-warning/35 bg-warning/10 text-warning"
  defp header_icon_class(:info), do: "border-info/35 bg-info/10 text-info"

  defp rail_class(:error), do: "bg-error"
  defp rail_class(:warning), do: "bg-warning"
  defp rail_class(:info), do: "bg-info"

  defp item_icon(:error), do: "hero-x-circle"
  defp item_icon(:warning), do: "hero-exclamation-circle"
  defp item_icon(:info), do: "hero-information-circle"

  defp item_icon_class(:error), do: "size-4 shrink-0 text-error"
  defp item_icon_class(:warning), do: "size-4 shrink-0 text-warning"
  defp item_icon_class(:info), do: "size-4 shrink-0 text-info"
end
