defmodule CadenceWeb.OpsDashboardShowLive.DashboardEditorConflictComponents do
  @moduledoc false
  use CadenceWeb, :html

  alias Phoenix.LiveView.JS

  attr(:conflict, :map, default: nil)

  def dashboard_editor_conflict(assigns) do
    assigns = assign(assigns, :presentation, presentation(assigns.conflict))

    ~H"""
    <.vue
      :if={@presentation}
      id="dashboard-editor-conflict-component"
      v-component="DashboardEditorConflict"
      presentation={@presentation}
      v-on:reload_editor={JS.push("reload_editor")}
      v-ssr={false}
      class="contents"
    />
    """
  end

  def presentation(nil), do: nil

  def presentation(conflict) when is_map(conflict) do
    starting_version = conflict.starting_version
    current_version = conflict.current_version

    %{
      root: %{
        attrs:
          %{
            id: "dashboard-editor-conflict",
            class:
              "flex shrink-0 items-center gap-3 border-b border-error/40 bg-error/10 px-3 py-2 text-sm"
          }
          |> Map.merge(
            data_attrs(%{
              "data-editor-starting-version" => starting_version,
              "data-editor-current-version" => current_version
            })
          )
      },
      icon: %{
        attrs: %{
          class: "hero-exclamation-triangle h-4 w-4 shrink-0 text-error"
        }
      },
      message: %{
        class: "min-w-0 flex-1",
        text:
          "Version #{dom_text(current_version)} was saved elsewhere. Your staged candidate is intact; reload before continuing to avoid an accidental overwrite."
      },
      reload: %{
        attrs: %{
          id: "dashboard-editor-reload",
          type: "button",
          class: "btn btn-ghost btn-xs"
        },
        text: "Reload latest"
      }
    }
  end

  defp data_attrs(attrs) do
    Enum.reduce(attrs, %{}, fn
      {_name, value}, rendered when value in [nil, false] ->
        rendered

      {name, true}, rendered ->
        Map.put(rendered, name, "")

      {name, value}, rendered ->
        Map.put(rendered, name, dom_text(value))
    end)
  end

  defp dom_text(nil), do: ""
  defp dom_text(value) when is_binary(value), do: value
  defp dom_text(value) when is_atom(value), do: Atom.to_string(value)
  defp dom_text(value) when is_number(value), do: to_string(value)
  defp dom_text(value), do: to_string(value)
end
