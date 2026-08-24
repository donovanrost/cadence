defmodule CadenceWeb.Components.OpsApplicationDock do
  @moduledoc "Host-owned bottom dock chrome for installed application surface contributions."

  use CadenceWeb, :html

  alias Cadence.Applications.OpsDockSurface

  attr :surfaces, :list, required: true

  def ops_application_dock(assigns) do
    assigns = assign(assigns, :presentation, presentation(assigns.surfaces))

    ~H"""
    <.vue
      id="ops-application-dock-component"
      v-component="OpsApplicationDock"
      presentation={@presentation}
      v-ssr={false}
      class="contents"
    />
    """
  end

  @doc false
  @spec presentation([OpsDockSurface.t()]) :: map()
  def presentation(surfaces) when is_list(surfaces) do
    %{
      "root" => %{
        "attrs" => raw_attrs(%{"id" => "ops-application-dock", "open" => true}),
        "class" => "group shrink-0 border-t border-primary/25 bg-base-200/80"
      },
      "summary" => %{
        "class" =>
          "flex h-8 cursor-pointer list-none items-center border-b border-base-300/70 px-3 marker:hidden"
      },
      "label" => %{
        "class" => "hud-label mr-4",
        "text" => "Operations dock"
      },
      "navigation" => %{
        "attrs" => raw_attrs(%{"aria-label" => "Application dock surfaces"}),
        "class" => "flex min-w-0 flex-1 items-stretch gap-1 self-stretch",
        "tabs" =>
          surfaces
          |> Enum.with_index()
          |> Enum.map(fn {surface, index} -> tab_dto(surface, index) end)
      },
      "chevron" => %{
        "class" =>
          "hero-chevron-down size-4 text-base-content/45 transition-transform group-open:rotate-180"
      },
      "panel" => %{
        "attrs" => raw_attrs(%{"id" => "ops-dock-surface-host", "role" => "tabpanel"}),
        "class" => "h-40 overflow-hidden bg-base-100",
        "message" => %{
          "class" => "flex h-full items-center justify-center text-sm text-base-content/45",
          "text" => "The application surface is registered with the Ops host."
        }
      }
    }
  end

  defp tab_dto(%OpsDockSurface{} = surface, index) do
    selected? = index == 0

    %{
      "key" => surface.id,
      "attrs" =>
        raw_attrs(%{
          "id" => "ops-dock-tab-#{dom_id(surface)}",
          "type" => "button",
          "role" => "tab",
          "aria-selected" => to_string(selected?),
          "data-application-key" => surface.application_key,
          "data-surface-id" => surface.surface_definition.surface_id
        }),
      "class" =>
        Enum.join(
          [
            "relative px-3 font-mono text-[0.68rem] font-semibold uppercase tracking-[0.1em]",
            if(selected?,
              do:
                "text-primary after:absolute after:inset-x-2 after:bottom-0 after:h-px after:bg-primary",
              else: "text-base-content/50"
            )
          ],
          " "
        ),
      "label" => surface.label
    }
  end

  defp dom_id(%OpsDockSurface{id: id}) do
    String.replace(id, ~r/[^a-zA-Z0-9_-]/, "-")
  end

  defp raw_attrs(attrs) do
    Enum.reduce(attrs, %{}, fn
      {_name, value}, rendered when value in [nil, false] ->
        rendered

      {name, true}, rendered ->
        Map.put(rendered, name, "")

      {name, value}, rendered ->
        Map.put(rendered, name, to_string(value))
    end)
  end
end
