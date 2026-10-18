# Test-only compatibility renderer preserving the pre-LiveVue component contract.
defmodule CadenceWeb.Components.Table do
  @moduledoc false

  use Phoenix.Component

  attr :id, :string, required: true
  attr :rows, :any, required: true
  attr :body_id, :string, default: nil
  attr :row_id, :any, default: nil
  attr :row_accent, :boolean, default: true
  attr :sort_by, :string, default: nil
  attr :sort_dir, :atom, values: [:asc, :desc], default: :asc
  attr :on_sort, :string, default: "sort"
  attr :class, :string, default: nil

  slot :col, required: true do
    attr :label, :string
    attr :align, :atom
    attr :mono, :boolean
    attr :sort, :string
    attr :class, :string
  end

  slot :empty

  def table(assigns) do
    assigns =
      case assigns.rows do
        %Phoenix.LiveView.LiveStream{} ->
          assigns
          |> assign(:stream?, true)
          |> assign(:row_id, assigns.row_id || fn {id, _item} -> id end)
          |> assign(:row_item, fn {_id, item} -> item end)

        _list ->
          assigns
          |> assign(:stream?, false)
          |> assign(:row_item, &Function.identity/1)
      end

    ~H"""
    <table id={@id} class={["table", @class]}>
      <thead>
        <tr>
          <.sort_header
            :for={col <- @col}
            col={col}
            sort_by={@sort_by}
            sort_dir={@sort_dir}
            on_sort={@on_sort}
          />
        </tr>
      </thead>
      <tbody id={@body_id || "#{@id}-body"} phx-update={@stream? && "stream"}>
        <tr :if={@empty != [] && @rows == []}>
          <td colspan={length(@col)}>{render_slot(@empty)}</td>
        </tr>
        <tr
          :for={row <- @rows}
          id={@row_id && @row_id.(row)}
          class={
            @row_accent &&
              "border-l-2 border-l-transparent hover:border-l-primary/60 transition-colors"
          }
        >
          <td
            :for={col <- @col}
            class={[
              col[:align] == :right && "text-right",
              col[:mono] && "font-mono text-sm",
              col[:class]
            ]}
          >
            {render_slot(col, @row_item.(row))}
          </td>
        </tr>
      </tbody>
    </table>
    """
  end

  attr :col, :map, required: true
  attr :sort_by, :string, required: true
  attr :sort_dir, :atom, required: true
  attr :on_sort, :string, required: true

  defp sort_header(%{col: col} = assigns) do
    assigns = assign(assigns, :active?, col[:sort] && col[:sort] == assigns.sort_by)

    ~H"""
    <th
      class={["hud-label", @col[:align] == :right && "text-right"]}
      aria-sort={@active? && to_string(@sort_dir) <> "ending"}
    >
      <%= if @col[:sort] do %>
        <button
          type="button"
          phx-click={@on_sort}
          phx-value-sort={@col[:sort]}
          class="inline-flex cursor-pointer items-center gap-1 uppercase hover:text-primary"
        >
          {@col[:label]}
          <span
            :if={@active?}
            class={[
              "h-3 w-3",
              if(@sort_dir == :asc, do: "hero-chevron-up", else: "hero-chevron-down")
            ]}
          >
          </span>
        </button>
      <% else %>
        {@col[:label]}
      <% end %>
    </th>
    """
  end
end
