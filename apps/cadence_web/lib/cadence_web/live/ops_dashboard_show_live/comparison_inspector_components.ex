defmodule CadenceWeb.OpsDashboardShowLive.ComparisonInspectorComponents do
  @moduledoc """
  Page-local Dashboard Compare presentation. Operational awareness remains in
  the shell-owned Ops context rail beside this inspector.
  """

  use CadenceWeb, :html

  import CadenceWeb.OpsDashboardShowLive.Components,
    only: [comparison_rollup_strip: 1]

  attr :open?, :boolean, required: true
  attr :rollup, :map, required: true
  attr :preset, :map, default: nil
  attr :open_review_summary, :map, default: %{}
  attr :saved_presets, :list, default: []

  def comparison_inspector(assigns) do
    assigns = assign(assigns, :header, comparison_inspector_header_dto())

    ~H"""
    <aside
      :if={@open? and available?(@rollup, @saved_presets)}
      id="dashboard-comparison-inspector"
      aria-label="Dashboard comparison inspector"
      data-dashboard-comparison-inspector
      class="relative flex w-[22rem] max-w-[42vw] shrink-0 flex-col overflow-hidden border-l border-info/35 bg-base-200/95 shadow-[-12px_0_28px_-20px_rgba(0,0,0,0.65)] backdrop-blur"
    >
      <div class="absolute inset-y-0 left-0 w-px bg-gradient-to-b from-info/80 via-info/20 to-transparent">
      </div>
      <.vue
        id="dashboard-comparison-inspector-header-component"
        v-component="DashboardComparisonInspectorHeader"
        presentation={@header}
        v-ssr={false}
        class="contents"
      />
      <div class="min-h-0 flex-1 overflow-y-auto">
        <.comparison_rollup_strip
          rollup={@rollup}
          preset={@preset}
          open_review_summary={@open_review_summary}
          saved_presets={@saved_presets}
        />
      </div>
    </aside>
    """
  end

  defp available?(rollup, saved_presets) do
    Map.get(rollup, :visible?) == true or saved_presets != []
  end

  defp comparison_inspector_header_dto do
    %{
      root: %{
        tag: "header",
        class: "flex min-h-12 items-center gap-2 border-b border-base-300/60 px-3 py-2",
        attrs: %{}
      },
      leading: %{
        tag: "div",
        class:
          "flex h-7 w-7 shrink-0 items-center justify-center rounded border border-info/35 bg-info/10 text-info",
        attrs: %{},
        icon: %{name: "hero-scale", class: "h-4 w-4", text: ""}
      },
      copy: %{
        tag: "div",
        class: "min-w-0 flex-1",
        attrs: %{},
        title: %{
          tag: "p",
          class: "hud-label text-info",
          attrs: %{},
          text: "Dashboard compare"
        },
        subtitle: %{
          tag: "p",
          class: "truncate text-[0.65rem] text-base-content/50",
          attrs: %{},
          text: "Page-local revision evidence"
        }
      },
      close: %{
        tag: "button",
        class: "btn btn-ghost btn-xs btn-square",
        attrs: %{
          "id" => "dashboard-comparison-inspector-close",
          "type" => "button",
          "phx-click" => "close_comparison_inspector",
          "aria-label" => "Close dashboard comparison inspector"
        },
        icon: %{name: "hero-x-mark", class: "h-4 w-4", text: ""}
      }
    }
  end
end
